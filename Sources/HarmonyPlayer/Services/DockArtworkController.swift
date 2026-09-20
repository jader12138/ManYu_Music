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
            let raw = Self.makeDockIcon(artwork: source, isPlaying: isPlaying)
            // 与静态图标（白色/黑色版，内容占画布 80.5%、四周约 10% 透明边）对齐：
            // 旧封面图标的底板占 512 画布的 93.75%，在 Dock 里明显比其他 App 大一圈。
            // 整体等比缩到 440/512（0.8594）并居中，底板边缘变为距画布约 50px——
            // 三种 Dock 状态（白色/黑色/专辑封面）视觉尺寸完全一致，与系统其他图标同档。
            let icon = Self.composeStandardSizedIcon(raw)
            DispatchQueue.main.async {
                guard generation == self.renderGeneration else { return }
                NSApplication.shared.applicationIconImage = icon
                NSApplication.shared.dockTile.display()
                NotificationCenter.default.post(name: .appIconDidChange, object: nil)
            }
        }
    }

    /// 把已渲染的 512×512 图标等比缩小居中到 macOS 标准图标网格占比（内容 80.5%）。
    private static func composeStandardSizedIcon(_ raw: NSImage) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let scaled = CGFloat(440)
        let margin = (512 - scaled) / 2
        let out = NSImage(size: size)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        raw.draw(in: NSRect(x: margin, y: margin, width: scaled, height: scaled),
                 from: NSRect(origin: .zero, size: size),
                 operation: .sourceOver, fraction: 1)
        out.unlockFocus()
        out.isTemplate = false
        return out
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

        // 右下角大号播放状态徽标：纯蓝圆底 + 白色描边 + 白色暂停/播放符号。
        // 位置整体往左上内收（右边距 16→34、底边距 6→24）：徽标连同白色描边
        // 完全退入亚克力底板内部，不再骑/压底板边缘。
        let badgeSize: CGFloat = 140
        let badgeRect = NSRect(
            x: plateRect.maxX - badgeSize - 34,
            y: plateRect.minY + 24,
            width: badgeSize,
            height: badgeSize
        )
        let badgePath = NSBezierPath(ovalIn: badgeRect)

        NSGraphicsContext.saveGraphicsState()
        let badgeShadow = NSShadow()
        badgeShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        badgeShadow.shadowBlurRadius = 16
        badgeShadow.shadowOffset = NSSize(width: 0, height: -4)
        badgeShadow.set()
        let badgeBlueTop = NSColor(srgbRed: 0.22, green: 0.52, blue: 0.97, alpha: 1)
        let badgeBlueBottom = NSColor(srgbRed: 0.14, green: 0.43, blue: 0.92, alpha: 1)
        NSGradient(colors: [badgeBlueTop, badgeBlueBottom])?.draw(in: badgePath, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // 白色圆描边
        let badgeRingWidth: CGFloat = 10
        let badgeRing = NSBezierPath(
            ovalIn: badgeRect.insetBy(dx: badgeRingWidth / 2, dy: badgeRingWidth / 2)
        )
        badgeRing.lineWidth = badgeRingWidth
        NSColor.white.setStroke()
        badgeRing.stroke()

        NSColor.white.setFill()
        if isPlaying {
            let barWidth = badgeSize * 0.135
            let barHeight = badgeSize * 0.40
            let spacing = badgeSize * 0.12
            let totalWidth = barWidth * 2 + spacing
            let leftX = badgeRect.midX - totalWidth / 2
            let barY = badgeRect.midY - barHeight / 2
            NSBezierPath(
                roundedRect: NSRect(x: leftX, y: barY, width: barWidth, height: barHeight),
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            ).fill()
            NSBezierPath(
                roundedRect: NSRect(x: leftX + barWidth + spacing, y: barY, width: barWidth, height: barHeight),
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            ).fill()
        } else {
            let scale = badgeSize / 94
            let path = NSBezierPath()
            path.move(to: NSPoint(x: badgeRect.midX - 12 * scale, y: badgeRect.midY - 19 * scale))
            path.line(to: NSPoint(x: badgeRect.midX + 21 * scale, y: badgeRect.midY))
            path.line(to: NSPoint(x: badgeRect.midX - 12 * scale, y: badgeRect.midY + 19 * scale))
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
