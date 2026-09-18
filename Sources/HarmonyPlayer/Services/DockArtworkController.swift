import AppKit

/// 播放中把 Dock 图标替换为大号蓝白播放状态图标（蓝色圆底 + 白色描边 +
/// 白色暂停双竖条/播放三角），停止播放或关闭开关时恢复默认应用图标。
@MainActor
final class DockArtworkController {
    static let shared = DockArtworkController()

    static let showsArtworkKey = "ManyuMusic.dockArtwork"

    private var renderedPlayingState: Bool?
    private var renderedForSetting = false

    private init() {}

    /// - Parameters:
    ///   - artwork: 当前曲目封面。新图标不再使用封面，仅用于判断是否处于播放会话
    ///     （没有载入歌曲时恢复默认应用图标）。
    ///   - isPlaying: true 显示暂停双竖条，false 显示播放三角。
    func update(artwork: NSImage?, isPlaying: Bool) {
        let enabled: Bool
        if UserDefaults.standard.object(forKey: Self.showsArtworkKey) == nil {
            enabled = true
        } else {
            enabled = UserDefaults.standard.bool(forKey: Self.showsArtworkKey)
        }

        guard enabled, artwork != nil else {
            restoreDefaultIcon()
            return
        }

        guard renderedPlayingState != isPlaying || !renderedForSetting else {
            return
        }

        renderedPlayingState = isPlaying
        renderedForSetting = true

        let icon = Self.makeDockIcon(isPlaying: isPlaying)
        NSApplication.shared.applicationIconImage = icon
        NSApplication.shared.dockTile.display()
    }

    func refreshSetting() {
        renderedPlayingState = nil
        renderedForSetting = false
    }

    private func restoreDefaultIcon() {
        AppIconStyleManager.apply()
        renderedPlayingState = nil
        renderedForSetting = false
    }

    private static func makeDockIcon(isPlaying: Bool) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let icon = NSImage(size: size)
        icon.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high

        let canvas = NSRect(origin: .zero, size: size)
        // 圆底占满绝大部分画布，只留一圈投影空间。
        let circleRect = canvas.insetBy(dx: 40, dy: 40)
        let circlePath = NSBezierPath(ovalIn: circleRect)

        // 投影
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 20
        shadow.shadowOffset = NSSize(width: 0, height: -7)
        shadow.set()
        NSColor.black.withAlphaComponent(0.001).setFill()
        circlePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // 蓝色圆底（接近实色、带极轻微的竖向深浅过渡）
        let blueTop = NSColor(srgbRed: 0.20, green: 0.52, blue: 0.96, alpha: 1)
        let blueBottom = NSColor(srgbRed: 0.12, green: 0.41, blue: 0.90, alpha: 1)
        NSGradient(colors: [blueTop, blueBottom])?.draw(in: circlePath, angle: -90)

        // 顶部微弱高光，增加一点立体感
        NSGraphicsContext.saveGraphicsState()
        circlePath.addClip()
        let sheenRect = NSRect(
            x: circleRect.minX + circleRect.width * 0.12,
            y: circleRect.midY,
            width: circleRect.width * 0.76,
            height: circleRect.height * 0.46
        )
        let sheen = NSBezierPath(ovalIn: sheenRect)
        NSColor.white.withAlphaComponent(0.06).setFill()
        sheen.fill()
        NSGraphicsContext.restoreGraphicsState()

        // 白色圆描边（位于圆底外缘内侧）
        let ringWidth: CGFloat = 13
        let ringPath = NSBezierPath(
            ovalIn: circleRect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2)
        )
        ringPath.lineWidth = ringWidth
        NSColor.white.setStroke()
        ringPath.stroke()

        // 白色播放状态符号
        NSColor.white.setFill()
        if isPlaying {
            let diameter = circleRect.width
            let barWidth = diameter * 0.130
            let barHeight = diameter * 0.385
            let spacing = diameter * 0.125
            let totalWidth = barWidth * 2 + spacing
            let leftX = circleRect.midX - totalWidth / 2
            let barY = circleRect.midY - barHeight / 2
            NSBezierPath(
                roundedRect: NSRect(x: leftX, y: barY, width: barWidth, height: barHeight),
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            ).fill()
            NSBezierPath(
                roundedRect: NSRect(
                    x: leftX + barWidth + spacing,
                    y: barY,
                    width: barWidth,
                    height: barHeight
                ),
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            ).fill()
        } else {
            // 播放三角：左缘留视觉补偿，整体略向右移。
            let scale = circleRect.width / 94
            let path = NSBezierPath()
            path.move(to: NSPoint(
                x: circleRect.midX - 12 * scale,
                y: circleRect.midY - 19 * scale
            ))
            path.line(to: NSPoint(
                x: circleRect.midX + 21 * scale,
                y: circleRect.midY
            ))
            path.line(to: NSPoint(
                x: circleRect.midX - 12 * scale,
                y: circleRect.midY + 19 * scale
            ))
            path.close()
            path.fill()
        }

        icon.unlockFocus()
        icon.isTemplate = false
        return icon
    }
}
