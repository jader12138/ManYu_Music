import Foundation

/// 启动预热：把资料库封面按显示档位提前解码进缓存，减少后续浏览各页面时的解码开销。
///
/// 只预热两档：
/// - 小档（128px）：歌曲列表 / 首页 / 收藏等所有行缩略图，按曲目文件逐一加载；
/// - 中档（384px）：专辑 / 艺术家网格与首页卡片封面，按专辑去重后取代表曲目加载。
/// 大档（768px）只有播放中的曲目会用到，由播放流程自行加载，不预热。
///
/// 预热以低优先级逐项进行，每项之间稍作让步，滚动/播放等前台工作永远优先。
@MainActor
final class ArtworkPreloader {
    static let shared = ArtworkPreloader()

    static let enabledKey = "ManyuMusic.preloadArtwork"

    private var runningTask: Task<Void, Never>?

    private init() {}

    var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: Self.enabledKey) != nil else { return false }
        return UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// 幂等入口：开关开启且当前没有在跑的预热时才启动一轮；
    /// 资料库加载完成后、或在设置里打开开关时调用。
    func preloadIfNeeded(tracks: [Track]) {
        guard isEnabled, runningTask == nil, !tracks.isEmpty else { return }

        // 中档按专辑去重：同一张专辑的多首歌各嵌各的封面数据，取每张专辑一个代表文件。
        var seenAlbums = Set<String>()
        var albumRepresentatives: [Track] = []
        for track in tracks {
            let key = track.displayAlbum + "\u{1F}" + track.displayArtist
            if seenAlbums.insert(key).inserted {
                albumRepresentatives.append(track)
            }
        }

        let allTracks = tracks
        runningTask = Task(priority: .utility) {
            // 小档在前：列表行缩略图的使用频率最高。已缓存的项目无需让步，直接快进。
            // urgent: false 走低优先级预取池，浏览时可见行的 urgent 请求在独立池即时响应。
            for track in allTracks {
                guard !Task.isCancelled, isEnabled else { break }
                let hit = ArtworkCache.shared.image(for: track.url, tier: .small) != nil
                _ = await ArtworkPipeline.shared.artwork(
                    for: track,
                    pixelSize: ArtworkPixelTier.small.pixels,
                    urgent: false
                )
                if !hit {
                    try? await Task.sleep(for: .milliseconds(3))
                }
            }
            for track in albumRepresentatives {
                guard !Task.isCancelled, isEnabled else { break }
                let hit = ArtworkCache.shared.image(for: track.url, tier: .medium) != nil
                _ = await ArtworkPipeline.shared.artwork(
                    for: track,
                    pixelSize: ArtworkPixelTier.medium.pixels,
                    urgent: false
                )
                if !hit {
                    try? await Task.sleep(for: .milliseconds(3))
                }
            }
            runningTask = nil
        }
    }
}
