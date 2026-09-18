import Foundation

/// 会话级歌词缓存：LRC/内嵌歌词都是纯文本，解析结果按曲目缓存一份，
/// 启动预热、首页推荐、播放切歌共用。
///
/// 解决的问题：切歌时播放流程要异步打开文件读歌词，歌词视图先渲染
/// “正在等待歌词”占位，几百毫秒后再替换成歌词——每切一首都跳一下。
/// 预热把大部分歌词提前解析好，`immediateResult(for:)` 让切歌在主线程
/// 同一轮状态更新里直接拿到歌词，占位不再出现。
final class LyricsCache: @unchecked Sendable {
    static let shared = LyricsCache()

    enum Outcome: Sendable {
        case ready([LyricLine])
        case missing

        var lines: [LyricLine] {
            if case .ready(let lines) = self { return lines }
            return []
        }
    }

    private let lock = NSLock()
    private var stored: [UUID: [LyricLine]] = [:]
    private var missingIDs = Set<UUID>()
    private var inFlight: [UUID: Task<[LyricLine]?, Never>] = [:]
    private var preloadTask: Task<Void, Never>?

    private init() {}

    /// 同步读取已缓存结果（在主线程切歌的同一轮状态更新中使用）。
    /// 返回 nil 表示尚未加载，需要走异步 `load(track:)`。
    func immediateResult(for id: UUID) -> Outcome? {
        lock.lock()
        defer { lock.unlock() }
        if let lines = stored[id] { return .ready(lines) }
        if missingIDs.contains(id) { return .missing }
        return nil
    }

    /// 合并去重的加载：同一首歌同时只允许一次磁盘 IO。
    @discardableResult
    func load(track: Track) -> Task<[LyricLine]?, Never> {
        lock.lock()
        if let lines = stored[track.id] {
            lock.unlock()
            return Task { lines }
        }
        if missingIDs.contains(track.id) {
            lock.unlock()
            return Task { nil }
        }
        if let task = inFlight[track.id] {
            lock.unlock()
            return task
        }

        let task = Task.detached(priority: .utility) { [weak self] () -> [LyricLine]? in
            let raw = await AudioMetadataLoader.lyrics(for: track)
            let parsed = LyricsParser.parse(raw)
            let outcome: [LyricLine]? = parsed.isEmpty ? nil : parsed
            self?.store(outcome, for: track.id)
            return outcome
        }
        inFlight[track.id] = task
        lock.unlock()
        return task
    }

    private func store(_ lines: [LyricLine]?, for id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        inFlight[id] = nil
        if let lines {
            stored[id] = lines
        } else {
            missingIDs.insert(id)
        }
    }

    /// 资料库加载完成后的后台预热：逐项低优先级解析全部曲目歌词。
    /// 已缓存或在途中的项目直接快进；纯文本体积小，整体内存可忽略。
    func preload(_ tracks: [Track]) {
        preloadTask?.cancel()
        preloadTask = Task(priority: .utility) {
            for track in tracks {
                guard !Task.isCancelled else { break }
                _ = await load(track: track).value
                // 微让步：避免连续打开文件挤占前台滚动/播放。
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
        }
    }

    /// 小范围急着要的曲目（队列接下来要播的几首）：已有在途任务则复用，
    /// 不等待、不让步，尽快发起读取。
    func preloadNext(_ tracks: [Track]) {
        for track in tracks {
            _ = load(track: track)
        }
    }

    /// 系统内存压力时清空；在途任务完成后照常落库，可重新生成。
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        stored.removeAll()
        missingIDs.removeAll()
    }
}
