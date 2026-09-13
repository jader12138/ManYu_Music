import AppKit

@MainActor
final class DockArtworkController {
    static let shared = DockArtworkController()

    static let showsArtworkKey = "ManyuMusic.dockArtwork"

    private var renderedArtwork: NSImage?
    private var renderedPlayingState: Bool?
    private var renderedForSetting = false

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

        let icon = makeDockIcon(artwork: artwork, isPlaying: isPlaying)
        NSApplication.shared.applicationIconImage = icon
        NSApplication.shared.dockTile.display()
    }

    func refreshSetting() {
        renderedForSetting = false
        renderedArtwork = nil
        renderedPlayingState = nil
    }

    private func restoreDefaultIcon() {
        AppIconStyleManager.apply()
        renderedArtwork = nil
        renderedPlayingState = nil
        renderedForSetting = false
    }

    private func makeDockIcon(artwork: NSImage, isPlaying: Bool) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let icon = NSImage(size: size)
        icon.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high

        let canvas = NSRect(origin: .zero, size: size)
        let contentRect = canvas.insetBy(dx: 30, dy: 30)
        let clip = NSBezierPath(roundedRect: contentRect, xRadius: 102, yRadius: 102)
        clip.addClip()

        let targetAspect = contentRect.width / contentRect.height
        let sourceRect = aspectFillRect(for: artwork.size, targetAspect: targetAspect)
        artwork.draw(
            in: contentRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1
        )

        let badgeSize: CGFloat = 94
        let badgeRect = NSRect(
            x: contentRect.maxX - badgeSize - 14,
            y: contentRect.minY + 14,
            width: badgeSize,
            height: badgeSize
        )
        let badgePath = NSBezierPath(ovalIn: badgeRect)

        let palette = ArtworkPaletteExtractor.palette(from: artwork)
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

    private func aspectFillRect(for sourceSize: NSSize, targetAspect: CGFloat) -> NSRect {
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
