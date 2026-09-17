import Foundation

/// 长时间听歌会话的内存兜底：系统发出内存压力（警告/危急）时，主动清空
/// 可再生成的缓存——封面缓存（NSCache 条目）。播放页背景与光斑的渲染
/// 表面随一次性 CIContext 用完即释放，无需额外处理。
enum MemoryPressureMonitor {
    private static let source: DispatchSourceMemoryPressure = {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler {
            ArtworkCache.shared.removeAllObjects()
        }
        source.resume()
        return source
    }()

    /// 应用启动时调用一次；静态常量保活事件源。
    static func install() {
        _ = source
    }
}
