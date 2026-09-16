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
    let systemName: String
    var isActive = false
    var help: String
    var size: CGFloat = 15
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(isActive ? Color.hpAccent : Color.hpTextPrimary.opacity(0.78))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: systemName)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            isActive
                                ? Color.hpAccent.opacity(0.15)
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

final class ArtworkCache {
    static let shared = ArtworkCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 320
        cache.totalCostLimit = 128 * 1024 * 1024
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

struct LazyArtworkView: View {
    let track: Track
    var size: CGFloat
    var cornerRadius: CGFloat = 10

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?

    private var tier: ArtworkPixelTier {
        ArtworkPixelTier.tier(for: size, displayScale: displayScale)
    }

    private var requestID: ArtworkRequestID {
        ArtworkRequestID(url: track.url, size: size, tier: tier)
    }

    var body: some View {
        ArtworkView(image: image, size: size, cornerRadius: cornerRadius)
            .task(id: requestID) {
                if let cached = ArtworkCache.shared.image(for: track.url, tier: tier) {
                    image = cached
                    return
                }

                // A new request on a reused view must not keep the previous cover.
                image = nil

                let loaded = await AudioMetadataLoader.artwork(for: track, pixelSize: tier.pixels)
                guard !Task.isCancelled, let loaded else { return }

                if reduceMotion {
                    image = loaded
                } else {
                    withAnimation(.easeOut(duration: 0.18)) {
                        image = loaded
                    }
                }
            }
    }
}
