import AppKit
import SwiftUI


extension Color {
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6 || value.count == 8 else { return nil }
        var integer: UInt64 = 0
        guard Scanner(string: value).scanHexInt64(&integer) else { return nil }

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        if value.count == 8 {
            red = Double((integer >> 24) & 0xff) / 255
            green = Double((integer >> 16) & 0xff) / 255
            blue = Double((integer >> 8) & 0xff) / 255
            alpha = Double(integer & 0xff) / 255
        } else {
            red = Double((integer >> 16) & 0xff) / 255
            green = Double((integer >> 8) & 0xff) / 255
            blue = Double(integer & 0xff) / 255
            alpha = 1
        }
        self.init(red: red, green: green, blue: blue, opacity: alpha)
    }
}

private func adaptiveColor(dark: NSColor, light: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}

extension Color {
    static let hpAccent = Color(red: 0.30, green: 0.72, blue: 1.00)
    static let hpAccentSecondary = Color(red: 0.18, green: 0.48, blue: 0.96)
    static let hpViolet = Color(red: 0.53, green: 0.56, blue: 0.98)
    static let hpPink = Color(red: 0.94, green: 0.35, blue: 0.62)
    static let hpMint = Color(red: 0.33, green: 0.80, blue: 0.68)
    static let hpGold = Color(red: 0.96, green: 0.70, blue: 0.30)
    static let hpIce = Color(red: 0.85, green: 0.95, blue: 1.00)
    static let hpOnAccent = Color(red: 0.025, green: 0.07, blue: 0.13)

    /// 文件格式徽标颜色：FLAC 金、MP3 蓝、MP4 家族淡红、其余按格式分色，未识别回退灰色。
    /// 用法：徽标文字色 = `Color.formatColor(forExtension:)`，背景 = 同色 opacity 0.13~0.15。
    static func formatColor(forExtension ext: String) -> Color {
        switch ext.lowercased() {
        case "flac": return .hpGold
        case "mp3": return .hpAccent
        case "mp4", "m4a", "m4b", "m4r", "m4v", "mov": return Color(red: 0.95, green: 0.42, blue: 0.45) // 淡红
        case "wav": return .hpMint
        case "aiff", "aif", "aifc": return Color(red: 0.95, green: 0.58, blue: 0.30) // 橙
        case "ogg", "oga": return Color(red: 0.55, green: 0.80, blue: 0.42) // 绿
        case "opus": return Color(red: 0.68, green: 0.52, blue: 0.92) // 紫
        case "aac": return .hpViolet
        case "wma": return Color(red: 0.85, green: 0.50, blue: 0.30) // 棕橙
        case "alac": return Color(red: 0.80, green: 0.65, blue: 0.30) // 麦金
        default: return .hpTextSecondary
        }
    }

    static let hpNavy = adaptiveColor(
        dark: NSColor(srgbRed: 0.035, green: 0.065, blue: 0.125, alpha: 1),
        light: NSColor(srgbRed: 0.91, green: 0.96, blue: 1.00, alpha: 1)
    )
    static let hpNavyDeep = adaptiveColor(
        dark: NSColor(srgbRed: 0.018, green: 0.032, blue: 0.065, alpha: 1),
        light: NSColor(srgbRed: 0.975, green: 0.992, blue: 1.00, alpha: 1)
    )
    static let hpSurface = adaptiveColor(
        dark: NSColor(srgbRed: 0.065, green: 0.115, blue: 0.205, alpha: 1),
        light: NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.96)
    )
    static let hpSurfaceRaised = adaptiveColor(
        dark: NSColor(srgbRed: 0.085, green: 0.15, blue: 0.26, alpha: 1),
        light: NSColor(srgbRed: 0.88, green: 0.94, blue: 1.00, alpha: 1)
    )
    static let hpTextPrimary = adaptiveColor(
        dark: .white,
        light: NSColor(srgbRed: 0.035, green: 0.09, blue: 0.16, alpha: 1)
    )
    static let hpTextSecondary = adaptiveColor(
        dark: NSColor.white.withAlphaComponent(0.58),
        light: NSColor(srgbRed: 0.18, green: 0.30, blue: 0.42, alpha: 0.72)
    )
    static let hpHairline = adaptiveColor(
        dark: NSColor.white.withAlphaComponent(0.08),
        light: NSColor.black.withAlphaComponent(0.07)
    )
}

/// 统一布局度量（椒盐风格：扁平、克制的圆角层次，不再使用椭圆造型）。
enum HPMetrics {
    /// 列表行 / 小型交互件的圆角
    static let radiusRow: CGFloat = 10
    /// 卡片容器圆角
    static let radiusCard: CGFloat = 16
    /// 封面瓦片 / 大图块圆角
    static let radiusTile: CGFloat = 20
}

extension LinearGradient {
    static let hpAccentFill = LinearGradient(
        colors: [.hpAccentSecondary, .hpAccent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let hpBrandFill = LinearGradient(
        colors: [.hpAccentSecondary, .hpAccent, .hpIce],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let hpSelectedRow = LinearGradient(
        colors: [Color.hpAccent.opacity(0.26), Color.hpAccentSecondary.opacity(0.10)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// Apple Music 风格的悬停高亮按钮：默认与底色融合（无背景、无描边），
/// 悬停时以圆角矩形渐显柔和主题色，按下加深。遵循系统"减弱动态效果"设置。
struct HoverHighlightButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 9
    var hoverOpacity: Double = 0.16
    var pressedOpacity: Double = 0.26

    func makeBody(configuration: Configuration) -> some View {
        HoverHighlightBody(
            configuration: configuration,
            cornerRadius: cornerRadius,
            hoverOpacity: hoverOpacity,
            pressedOpacity: pressedOpacity
        )
    }

    private struct HoverHighlightBody: View {
        let configuration: Configuration
        var cornerRadius: CGFloat
        var hoverOpacity: Double
        var pressedOpacity: Double

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient.hpAccentFill.opacity(
                                configuration.isPressed ? pressedOpacity : (isHovering ? hoverOpacity : 0)
                            )
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .onHover { hovering in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        isHovering = hovering
                    }
                }
        }
    }
}

/// 主操作按钮：主题色圆角矩形填充，悬停轻微提亮上浮，按下回缩。
struct AccentFillButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 9

    func makeBody(configuration: Configuration) -> some View {
        AccentFillBody(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct AccentFillBody: View {
        let configuration: Configuration
        var cornerRadius: CGFloat

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovering = false

        private var isEngaged: Bool { isHovering && !configuration.isPressed }

        var body: some View {
            configuration.label
                .background(
                    LinearGradient.hpAccentFill,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .brightness(isEngaged ? 0.08 : 0)
                .scaleEffect(
                    configuration.isPressed ? 0.97 : (isEngaged && !reduceMotion ? 1.02 : 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
                .onHover { hovering in
                    isHovering = hovering
                }
        }
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.hpNavyDeep, .hpNavy, .hpSurfaceRaised],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.hpAccent.opacity(0.16))
                .frame(width: 620, height: 620)
                .blur(radius: 150)
                .offset(x: 420, y: -360)

            Circle()
                .fill(Color.hpAccentSecondary.opacity(0.12))
                .frame(width: 520, height: 520)
                .blur(radius: 150)
                .offset(x: -450, y: 330)

            Circle()
                .fill(Color.hpViolet.opacity(0.07))
                .frame(width: 420, height: 420)
                .blur(radius: 160)
                .offset(x: 240, y: 390)
        }
        .ignoresSafeArea()
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct ArtworkView: View {
    let image: NSImage?
    var size: CGFloat
    var cornerRadius: CGFloat = 12

    /// Thumbnails skip the drop shadow: a blurred shadow per cover is a real cost
    /// when a list renders hundreds of 44pt rows.
    private var showsShadow: Bool { size > 64 }

    var body: some View {
        if showsShadow {
            artwork.shadow(color: .black.opacity(0.26), radius: 10, y: 6)
        } else {
            artwork
        }
    }

    private var artwork: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [.white, Color.hpIce],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Circle()
                        .fill(Color.hpAccent.opacity(0.92))
                        .frame(width: size * 0.64, height: size * 0.64)
                        .offset(x: size * 0.20, y: -size * 0.17)

                    Image(systemName: "waveform")
                        .font(.system(size: max(13, size * 0.29), weight: .bold))
                        .foregroundStyle(Color.hpAccentSecondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
    }
}

struct PlaybackStateBadge: View {
    let isPlaying: Bool
    var size: CGFloat = 28
    var palette: ArtworkPalette?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)

            Circle()
                .fill(badgeGradient)

            Circle()
                .trim(from: 0.08, to: 0.28)
                .stroke(.white.opacity(colorScheme == .dark ? 0.42 : 0.52), lineWidth: 1.2)
                .rotationEffect(.degrees(-35))
                .padding(size * 0.12)

            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.37, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: isPlaying ? 0 : size * 0.035)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isPlaying)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.15), radius: 7, y: 4)
    }

    private var badgeGradient: LinearGradient {
        if let palette {
            return LinearGradient(
                colors: [
                    Color(nsColor: palette.secondary).opacity(colorScheme == .dark ? 0.72 : 0.88),
                    Color(nsColor: palette.primary).opacity(colorScheme == .dark ? 0.64 : 0.80),
                    Color.white.opacity(colorScheme == .dark ? 0.20 : 0.34)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.hpAccent.opacity(0.68),
                    Color.hpViolet.opacity(0.52)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.hpAccentSecondary.opacity(0.94),
                Color.hpAccent.opacity(0.88),
                Color.hpViolet.opacity(0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct IconButton: View {
    var systemName: String? = nil
    var textLabel: String? = nil
    var isActive = false
    var activeColor: Color = .hpAccent
    /// 开启态不使用高亮底色与着色，改为图标底部一枚小圆点（与播放模式按钮同款）。
    var showsActivityDot = false
    var help: String
    var size: CGFloat = 15
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    @ViewBuilder
    private var glyph: some View {
        if let textLabel {
            Text(verbatim: textLabel)
        } else {
            Image(systemName: systemName ?? "")
        }
    }

    /// 圆点模式下开启态不着色、不铺高亮底色，状态只由底部小点表达。
    private var showsActiveFill: Bool { isActive && !showsActivityDot }

    var body: some View {
        Button(action: action) {
            glyph
                .font(.system(size: size, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(showsActiveFill ? activeColor : Color.hpTextPrimary.opacity(0.78))
                .modifier(GlyphTransition(reduceMotion: reduceMotion, systemName: systemName))
                .overlay(alignment: .bottom) {
                    if showsActivityDot {
                        Circle()
                            .fill(activeColor)
                            .frame(width: 3.5, height: 3.5)
                            .offset(y: -2.5)
                            .scaleEffect(isActive ? 1 : 0.4, anchor: .center)
                            .opacity(isActive ? 1 : 0)
                            .animation(reduceMotion
                                       ? nil
                                       : .spring(response: 0.22, dampingFraction: 0.55),
                                       value: isActive)
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            showsActiveFill
                                ? activeColor.opacity(0.15)
                                : Color.hpTextPrimary.opacity(isHovering ? 0.08 : 0)
                        )
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PlaybackPressButtonStyle(reduceMotion: reduceMotion))
        .onHover { isHovering = $0 }
        .help(help)
    }
}

/// SF Symbol 切换时的符号过渡动画；纯文字图标不加 symbolEffect（对 Text 无意义）。
private struct GlyphTransition: ViewModifier {
    let reduceMotion: Bool
    let systemName: String?

    func body(content: Content) -> some View {
        if systemName != nil {
            content
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: systemName)
        } else {
            content
        }
    }
}

final class ArtworkCache {
    static let shared = ArtworkCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        // 启动预加载开启后，小档（全部曲目）与中档（按专辑）会同时驻留，键数约
        // 曲目数 + 专辑数；再加上浏览过程中产生的大档（768px）专辑详情图。
        // 48MB 预算：实测驻留内存 ≈ 基线(约 170MB，含 CA 图层/系统服务) + 本预算。
        // 超出时 NSCache 按 LRU 淘汰尾部，最近浏览的封面优先保留；淘汰项下次
        // 显示按需重解码（毫秒级）。系统内存压力下也会自动淘汰。
        cache.countLimit = 320
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    /// Cache key: file URL + pixel tier, so tiers never evict each other and the
    /// key space stays bounded (three tiers per file).
    static func key(for url: URL, tier: ArtworkPixelTier) -> String {
        "\(url.path)|\(tier.pixels)"
    }

    func image(for url: URL, tier: ArtworkPixelTier) -> NSImage? {
        cache.object(forKey: Self.key(for: url, tier: tier) as NSString)
    }

    func insert(_ image: NSImage, for url: URL, tier: ArtworkPixelTier) {
        let pixels = max(1, image.size.width * image.size.height)
        cache.setObject(image, forKey: Self.key(for: url, tier: tier) as NSString, cost: Int(pixels * 4))
    }

    /// 系统内存压力下的兜底清理：NSCache 自身会自动淘汰，这里显式清空、
    /// 立即释放。清掉的都是可再生成的封面（下次显示时按需重新解码）。
    func removeAllObjects() {
        cache.removeAllObjects()
    }

    // Kept for callers that only know a URL: equivalent to the default 768px tier.
    func image(for url: URL) -> NSImage? {
        image(for: url, tier: .large)
    }

    func insert(_ image: NSImage, for url: URL) {
        insert(image, for: url, tier: .large)
    }
}

private struct ArtworkRequestID: Hashable {
    let url: URL
    let size: CGFloat
    let tier: ArtworkPixelTier
}

/// 专辑封面统一布局（播放页大封面除外，它保持自己的 22pt 观感）。
/// 圆角与播放条 48pt/7pt 小封面同比例：任何尺寸的封面都按 7:48 取圆角，
/// 视觉语言一致，改基准值这里一处即可全局生效。艺术家圆形头像不走这里。
enum ArtworkLayout {
    static func cornerRadius(for size: CGFloat) -> CGFloat {
        (size * 7.0 / 48.0).rounded()
    }
}

struct LazyArtworkView: View {
    let track: Track
    var size: CGFloat
    var cornerRadius: CGFloat = 10

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loadedImage: NSImage?
    @State private var loadedRequestID: ArtworkRequestID?

    private var tier: ArtworkPixelTier {
        ArtworkPixelTier.tier(for: size, displayScale: displayScale)
    }

    private var requestID: ArtworkRequestID {
        ArtworkRequestID(url: track.url, size: size, tier: tier)
    }

    /// 首帧同步出图：缓存里有（预加载过的、或看过的）直接随本次渲染返回，
    /// 不再经历"占位图 → task 下一帧换图"的闪烁；快速滚动时封面即取即用。
    /// 状态里的图只在属于当前请求时才参与，避免视图复用换曲目时闪上一首的封面。
    private var currentImage: NSImage? {
        if let cached = ArtworkCache.shared.image(for: track.url, tier: tier) {
            return cached
        }
        if let loadedRequestID, loadedRequestID == requestID {
            return loadedImage
        }
        return nil
    }

    var body: some View {
        ArtworkView(image: currentImage, size: size, cornerRadius: cornerRadius)
            .task(id: requestID) {
                // 缓存命中时 body 已经直接渲染，无需再做任何事。
                guard ArtworkCache.shared.image(for: track.url, tier: tier) == nil else { return }

                // 可见请求走 urgent 池；可能与滚动预取共享同一个合并任务。
                _ = await AudioMetadataLoader.artwork(for: track, pixelSize: tier.pixels)

                // 以缓存为权威：合并任务完成、取消竞态等情况下图可能已由别的路径
                // 写入缓存。无封面文件缓存永远为 nil，保持占位图。
                guard !Task.isCancelled else { return }
                guard let resolved = ArtworkCache.shared.image(for: track.url, tier: tier) else { return }

                if reduceMotion {
                    loadedImage = resolved
                } else {
                    withAnimation(.easeOut(duration: 0.18)) {
                        loadedImage = resolved
                    }
                }
                loadedRequestID = requestID
            }
    }
}
