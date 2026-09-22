import Foundation

/// 快速滚动封面预取（SwiftUI 的 LazyVStack/LazyVGrid 没有等价 UIKit 的
/// prefetch 回调，行/卡片只有进入可见区后才会开始解码封面——快速甩滚停下时
/// 可见封面往往还在文件队列里排队，表现为长时间灰块）。
///
/// 方案两部分：
/// - `ScrollArtworkWindow`：挂在列表/网格上，收集近期可见项的索引（onAppear），
///   防抖后按"可见区前后各一屏多"切出窗口，交给预取器；
/// - `ArtworkWindowPrefetcher`：窗口变化时取消上一轮窗口任务，用低优先级
///   （pipeline 的 prefetch 并发池）逐项解码入缓存。行真正进入可见区时
///   `LazyArtworkView` 同步命中缓存，未就绪的请求会把排队中的预取升级为高优。
@MainActor
final class ScrollArtworkWindow: ObservableObject {
    /// 索引 → 该位置卡片的代表曲目（网格里无封面的卡片返回 nil）。
    private var provider: (Int) -> Track? = { _ in nil }
    private var listID: AnyHashable?
    private var count = 0
    private var pixelSize = ArtworkPixelTier.small.pixels
    /// 窗口向前/向后探的项数。
    private var lead = 16

    /// 近期可见项索引（去重、保序、 capped），滚动停止后其 min/max 即当前区域。
    private var recentIndices: [Int] = []
    private var debounceTask: Task<Void, Never>?

    private let recentLimit = 40
    private let debounceNanoseconds: UInt64 = 120_000_000

    /// 每次列表 body 求值时调用（幂等）。`listID` 变化（搜索/排序/切列表）时
    /// 清空可见索引并撤销待发窗口，避免新列表沿用旧索引预取错位置。
    func configure(
        listID: AnyHashable,
        count: Int,
        pixelSize: Int,
        lead: Int,
        provider: @escaping (Int) -> Track?
    ) {
        if listID != self.listID {
            self.listID = listID
            recentIndices = []
            debounceTask?.cancel()
            ArtworkWindowPrefetcher.shared.cancelWindow()
        }
        self.count = count
        self.pixelSize = pixelSize
        self.lead = lead
        self.provider = provider
    }

    /// 行/卡片 onAppear 时上报其在当前列表中的索引。
    func report(_ index: Int) {
        guard index >= 0, index < count else { return }
        if recentIndices.last != index {
            recentIndices.removeAll { $0 == index }
            recentIndices.append(index)
            if recentIndices.count > recentLimit {
                recentIndices.removeFirst(recentIndices.count - recentLimit)
            }
        }

        debounceTask?.cancel()
        let windowIndices = recentIndices
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceNanoseconds ?? 120_000_000)
            guard !Task.isCancelled, let self else { return }
            self.schedule(windowIndices: windowIndices)
        }
    }

    private func schedule(windowIndices: [Int]) {
        guard count > 0, !windowIndices.isEmpty,
              let minIndex = windowIndices.min(),
              let maxIndex = windowIndices.max() else { return }
        let lo = max(0, minIndex - lead)
        let hi = min(count - 1, maxIndex + lead)
        var window: [Track] = []
        window.reserveCapacity(hi - lo + 1)
        for index in lo...hi {
            if let track = provider(index) {
                window.append(track)
            }
        }
        ArtworkWindowPrefetcher.shared.updateWindow(window, pixelSize: pixelSize)
    }
}

/// 全局预取调度器：同一时刻只有一个窗口任务，窗口移动即取消旧任务
/// （仅取消尚未占槽的请求；已在读文件的请求会跑完并暖缓存，见 ArtworkPipeline）。
@MainActor
final class ArtworkWindowPrefetcher {
    static let shared = ArtworkWindowPrefetcher()

    private var windowTask: Task<Void, Never>?
    private var lastSignature: [UUID] = []

    private init() {}

    func updateWindow(_ tracks: [Track], pixelSize: Int) {
        let signature = tracks.map(\.id)
        guard !signature.isEmpty, signature != lastSignature else { return }
        lastSignature = signature

        windowTask?.cancel()
        windowTask = Task(priority: .utility) {
            // 已缓存 / 已标记无封面的项目 pipeline 内部立即返回，无额外开销。
            for track in tracks {
                if Task.isCancelled { break }
                _ = await ArtworkPipeline.shared.artwork(
                    for: track,
                    pixelSize: pixelSize,
                    urgent: false
                )
            }
        }
    }

    func cancelWindow() {
        windowTask?.cancel()
        windowTask = nil
        lastSignature = []
    }
}
