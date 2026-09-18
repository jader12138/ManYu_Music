import Foundation

/// 长时间听歌会话的内存兜底：系统发出内存压力（警告/危急）时，主动清空
/// 可再生成的缓存——封面缓存（NSCache 条目）与歌词文本缓存。背景与光斑
/// 渲染全程走 CPU（vImage / CGContext），无 CoreImage 表面池，无额外驻留
/// 需要处理。
enum MemoryPressureMonitor {
    private static let source: DispatchSourceMemoryPressure = {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler {
            ArtworkCache.shared.removeAllObjects()
            LyricsCache.shared.removeAll()
        }
        source.resume()
        return source
    }()

    /// 应用启动时调用一次；静态常量保活事件源。
    static func install() {
        _ = source
    }
}
