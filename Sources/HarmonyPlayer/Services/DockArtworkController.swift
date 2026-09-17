import AppKit

@MainActor
final class DockArtworkController {
    static let shared = DockArtworkController()

    static let showsArtworkKey = "ManyuMusic.dockArtwork"

    private var renderedArtwork: NSImage?
    private var renderedPlayingState: Bool?
    private var renderedForSetting = false

    /// 图标渲染（512px 画布 + 阴影 + 渐变 + 封面主色提取）是重活，放到后台串行
    /// 队列执行；回主线程只做最终赋值。代数号用于丢弃过期的在途渲染。
    private let renderQueue = DispatchQueue(label: "ManyuMusic.dockArtworkRender", qos: .userInitiated)
    private var renderGeneration = 0

    private init() {}

    func update(artwork: NSImage?, isPlaying: Bool) {
        let enabled: Bool
        if UserDefaults.standard.object(forKey: Self.showsArtworkKey) == nil {
            enabled = true
        } else {
            enabled = UserDefaults.standard.bool(forKey: Self.showsArtworkKey)
        }

        guard enabled else {
            restoreDefaultIcon()
            return
        }

        guard let artwork else {
            restoreDefaultIcon()
            return
        }

        guard renderedArtwork !== artwork
                || renderedPlayingState != isPlaying
                || !renderedForSetting else {
            return
        }

        renderedArtwork = artwork
        renderedPlayingState = isPlaying
        renderedForSetting = true

        renderGeneration += 1
        let generation = renderGeneration
        let source = artwork
        renderQueue.async {
            let icon = Self.makeDockIcon(artwork: source, isPlaying: isPlaying)
            DispatchQueue.main.async {
                guard generation == self.renderGeneration else { return }
                NSApplication.shared.applicationIconImage = icon
                NSApplication.shared.dockTile.display()
            }
        }
    }

    func refreshSetting() {
        renderGeneration += 1
        renderedForSetting = false
        renderedArtwork = nil
        renderedPlayingState = nil
    }

    private func restoreDefaultIcon() {
        renderGeneration += 1
        AppIconStyleManager.apply()
        renderedArtwork = nil
        renderedPlayingState = nil
        renderedForSetting = false
    }

    private static func makeDockIcon(artwork: NSImage, isPlaying: Bool) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let icon = NSImage(size: size)
        icon.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high

        let canvas = NSRect(origin: .zero, size: size)
        let plateRect = canvas.insetBy(dx: 16, dy: 16)
        let artworkPadding: CGFloat = 30
        let artworkRect = plateRect.insetBy(dx: artworkPadding, dy: artworkPadding)

        let palette = ArtworkPaletteExtractor.palette(from: artwork)
        let platePrimary = palette.primary.blended(withFraction: 0.38, of: .white) ?? palette.primary
        let plateSecondary = palette.secondary.blended(withFraction: 0.30, of: .white) ?? palette.secondary

        let platePath = NSBezierPath(roundedRect: plateRect, xRadius: 108, yRadius: 108)
        NSGraphicsContext.saveGraphicsState()
        let plateShadow = NSShadow()
        plateShadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        plateShadow.shadowBlurRadius = 18
        plateShadow.shadowOffset = NSSize(width: 0, height: -5)
        plateShadow.set()
        NSColor.white.withAlphaComponent(0.24).setFill()
        platePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        platePath.addClip()
        NSGradient(
            colors: [
                platePrimary.withAlphaComponent(0.30),
                plateSecondary.withAlphaComponent(0.20),
                NSColor.white.withAlphaComponent(0.16)
            ]
        )?.draw(in: plateRect, angle: -35)
        NSGraphicsContext.restoreGraphicsState()

        platePath.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.28).setStroke()
        platePath.stroke()

        let artworkPath = NSBezierPath(roundedRect: artworkRect, xRadius: 88, yRadius: 88)
        NSGraphicsContext.saveGraphicsState()
        artworkPath.addClip()
        let targetAspect = artworkRect.width / artworkRect.height
        let sourceRect = aspectFillRect(for: artwork.size, targetAspect: targetAspect)
        artwork.draw(
            in: artworkRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        let badgeSize: CGFloat = 94
        let badgeRect = NSRect(
            x: plateRect.maxX - badgeSize - 14,
            y: plateRect.minY + 14,
            width: badgeSize,
            height: badgeSize
        )
        let badgePath = NSBezierPath(ovalIn: badgeRect)

        let primary = palette.primary.blended(withFraction: 0.26, of: .white) ?? palette.primary
        let secondary = palette.secondary.blended(withFraction: 0.18, of: .white) ?? palette.secondary
        let accent = palette.accent.blended(withFraction: 0.12, of: .white) ?? palette.accent

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 16
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        NSGradient(colors: [primary, secondary, accent])?.draw(in: badgePath, angle: -38)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        badgePath.addClip()
        let glassHighlight = NSBezierPath(
            ovalIn: badgeRect.insetBy(dx: 7, dy: 7)
        )
        NSColor.white.withAlphaComponent(0.10).setFill()
        glassHighlight.fill()
        NSGraphicsContext.restoreGraphicsState()

        let highlight = NSBezierPath()
        highlight.appendArc(
            withCenter: NSPoint(x: badgeRect.midX, y: badgeRect.midY),
            radius: badgeSize * 0.33,
            startAngle: 102,
            endAngle: 192
        )
        NSColor.white.withAlphaComponent(0.48).setStroke()
        highlight.lineWidth = 3
        highlight.lineCapStyle = .round
        highlight.stroke()

        NSColor.white.setFill()
        if isPlaying {
            let barWidth: CGFloat = 11
            let barHeight: CGFloat = 36
            let spacing: CGFloat = 13
            let totalWidth = barWidth * 2 + spacing
            let leftX = badgeRect.midX - totalWidth / 2
            let barY = badgeRect.midY - barHeight / 2
            NSBezierPath(
                roundedRect: NSRect(x: leftX, y: barY, width: barWidth, height: barHeight),
                xRadius: 5,
                yRadius: 5
            ).fill()
            NSBezierPath(
                roundedRect: NSRect(x: leftX + barWidth + spacing, y: barY, width: barWidth, height: barHeight),
                xRadius: 5,
                yRadius: 5
            ).fill()
        } else {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: badgeRect.midX - 12, y: badgeRect.midY - 19))
            path.line(to: NSPoint(x: badgeRect.midX + 21, y: badgeRect.midY))
            path.line(to: NSPoint(x: badgeRect.midX - 12, y: badgeRect.midY + 19))
            path.close()
            path.fill()
        }

        icon.unlockFocus()
        icon.isTemplate = false
        return icon
    }

    private static func aspectFillRect(for sourceSize: NSSize, targetAspect: CGFloat) -> NSRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return NSRect(origin: .zero, size: sourceSize)
        }

        let sourceAspect = sourceSize.width / sourceSize.height
        if sourceAspect > targetAspect {
            let width = sourceSize.height * targetAspect
            return NSRect(
                x: (sourceSize.width - width) / 2,
                y: 0,
                width: width,
                height: sourceSize.height
            )
        } else {
            let height = sourceSize.width / targetAspect
            return NSRect(
                x: 0,
                y: (sourceSize.height - height) / 2,
                width: sourceSize.width,
                height: height
            )
        }
    }
}
