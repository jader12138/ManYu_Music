import AppKit

@MainActor
final class DockArtworkController {
    static let shared = DockArtworkController()

    static let showsArtworkKey = "ManyuMusic.dockArtwork"

    private var defaultIcon: NSImage?
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
        if !UserDefaults.standard.bool(forKey: Self.showsArtworkKey) {
            restoreDefaultIcon()
            return
        }

        renderedForSetting = false
        renderedArtwork = nil
        renderedPlayingState = nil
    }

    private func restoreDefaultIcon() {
        guard renderedForSetting || renderedArtwork != nil else { return }

        if defaultIcon == nil {
            defaultIcon = NSApplication.shared.applicationIconImage
                ?? NSImage(named: NSImage.applicationIconName)
        }

        if let defaultIcon {
            NSApplication.shared.applicationIconImage = defaultIcon
            NSApplication.shared.dockTile.display()
        }

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

        let badgeSize: CGFloat = 78
        let badgeRect = NSRect(
            x: contentRect.maxX - badgeSize - 18,
            y: contentRect.minY + 18,
            width: badgeSize,
            height: badgeSize
        )
        let badgePath = NSBezierPath(ovalIn: badgeRect)
        NSColor.black.withAlphaComponent(0.82).setFill()
        badgePath.fill()

        NSColor.white.withAlphaComponent(0.78).setStroke()
        badgePath.lineWidth = 3
        badgePath.stroke()

        NSColor.white.setFill()
        if isPlaying {
            let barWidth: CGFloat = 9
            let barHeight: CGFloat = 30
            let spacing: CGFloat = 11
            let totalWidth = barWidth * 2 + spacing
            let leftX = badgeRect.midX - totalWidth / 2
            let barY = badgeRect.midY - barHeight / 2
            NSBezierPath(
                roundedRect: NSRect(x: leftX, y: barY, width: barWidth, height: barHeight),
                xRadius: 4,
                yRadius: 4
            ).fill()
            NSBezierPath(
                roundedRect: NSRect(x: leftX + barWidth + spacing, y: barY, width: barWidth, height: barHeight),
                xRadius: 4,
                yRadius: 4
            ).fill()
        } else {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: badgeRect.midX - 9, y: badgeRect.midY - 16))
            path.line(to: NSPoint(x: badgeRect.midX + 18, y: badgeRect.midY))
            path.line(to: NSPoint(x: badgeRect.midX - 9, y: badgeRect.midY + 16))
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
