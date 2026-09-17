import AppKit
import SwiftUI

/// 「回到顶部」悬浮按钮的状态与滚动监听。
///
/// 监听窗口内所有 NSScrollView 的 bounds 变化通知（SwiftUI 的 ScrollView/List
/// 底层都是 NSScrollView），按滚动方向决定按钮显隐：仅当内容距顶部较远且正在
/// 向上滚动时出现；向下滚动或接近顶部时消失。点击后把最近滚动的视图平滑滚回顶部。
@MainActor
final class BackToTopController: ObservableObject {
    /// 距顶部超过该值才允许出现按钮（太近时回顶没有意义）。
    private static let appearOffsetThreshold: CGFloat = 300
    /// 距顶部低于该值直接隐藏。
    private static let hideOffsetThreshold: CGFloat = 80
    /// 主内容区滚动视图的窗口横坐标范围：排除左侧栏（贴近左缘 0）与右侧队列面板。
    private static let contentMinXRange: ClosedRange<CGFloat> = 24...320

    @Published private(set) var showButton = false

    private var lastYByKey = [ObjectIdentifier: CGFloat]()
    private weak var activeScrollView: NSScrollView?
    private var started = false
    private var boundsObserver: NSObjectProtocol?
    private var windowObserver: NSObjectProtocol?
    private var scanTimer: Timer?
    private var isAutoScrolling = false

    // 回顶动画状态：逐帧插值（NSScrollView 隐式动画在 SwiftUI 滚动视图上不生效）。
    private var autoScrollTimer: Timer?
    private weak var autoScrollView: NSScrollView?
    private var autoScrollKey: ObjectIdentifier?
    private var autoStartY: CGFloat = 0
    private var autoStartTime: CFTimeInterval = 0
    private var autoDuration: CFTimeInterval = 0.4
    private var lastAutoY: CGFloat = 0

    func start() {
        guard !started else { return }
        started = true

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let clipView = note.object as? NSClipView else { return }
            Task { @MainActor [weak self] in
                self?.handleBoundsChange(of: clipView)
            }
        }

        // SwiftUI 切页时会懒创建新的 NSScrollView，窗口变化与低频扫描兜底。
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scanForScrollViews()
            }
        }

        scanForScrollViews()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scanForScrollViews()
            }
        }
    }

    func scrollToTop() {
        guard let scrollView = activeScrollView else { return }
        let startY = scrollView.contentView.bounds.origin.y
        guard startY > 1 else {
            showButton = false
            return
        }

        autoScrollView = scrollView
        autoScrollKey = ObjectIdentifier(scrollView)
        autoStartY = startY
        autoStartTime = CACurrentMediaTime()
        // 距离越远动画越长：0.4s 起步，长列表最多 0.9s。
        autoDuration = min(0.9, max(0.4, 0.35 + startY / 2500))
        lastAutoY = startY
        isAutoScrolling = true
        showButton = false

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stepAutoScroll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoScrollTimer = timer
        stepAutoScroll()
    }

    /// easeInOutCubic 逐帧推进，到顶后收尾。
    private func stepAutoScroll() {
        guard let scrollView = autoScrollView, let key = autoScrollKey else {
            stopAutoScroll()
            return
        }
        let t = min(1, (CACurrentMediaTime() - autoStartTime) / autoDuration)
        let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        let y = autoStartY * (1 - eased)
        lastAutoY = y
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(clipView)
        if t >= 1 {
            stopAutoScroll()
            lastYByKey[key] = clipView.bounds.origin.y
        }
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        autoScrollView = nil
        autoScrollKey = nil
        isAutoScrolling = false
    }

    /// 给所有可见窗口里的滚动视图打开 bounds 通知。
    private func scanForScrollViews() {
        for window in NSApp.windows where window.isVisible {
            enableBoundsNotifications(in: window.contentView)
        }
    }

    private func enableBoundsNotifications(in view: NSView?) {
        guard let view else { return }
        if let scrollView = view as? NSScrollView {
            scrollView.contentView.postsBoundsChangedNotifications = true
        }
        for subview in view.subviews {
            enableBoundsNotifications(in: subview)
        }
    }

    private func handleBoundsChange(of clipView: NSClipView) {
        guard let scrollView = clipView.enclosingScrollView else { return }

        // 只响应主内容区的垂直滚动；侧栏与队列面板的滚动不触发按钮。
        let frameInWindow = scrollView.convert(scrollView.bounds, to: nil)
        guard Self.contentMinXRange.contains(frameInWindow.minX) else { return }

        let newY = clipView.bounds.origin.y
        let key = ObjectIdentifier(scrollView)
        defer { lastYByKey[key] = newY }

        // 回顶动画期间：来自动画自身的回调直接忽略；
        // 与上一帧设置值偏差明显的说明用户手动滚动了——打断动画，继续正常判定。
        if isAutoScrolling {
            if key == autoScrollKey, abs(newY - lastAutoY) <= 2 {
                return
            }
            stopAutoScroll()
        }

        guard let previousY = lastYByKey[key] else { return }
        let dy = newY - previousY
        guard abs(dy) > 0.5 else { return }

        let shouldShow: Bool
        if newY <= Self.hideOffsetThreshold {
            shouldShow = false
        } else if newY >= Self.appearOffsetThreshold {
            // 正在向上滚（origin.y 减小）才出现。
            shouldShow = dy < 0
        } else {
            // 中间地带：已显示时保持，向下滚仍会隐藏。
            shouldShow = showButton && dy < 0
        }

        if shouldShow {
            activeScrollView = scrollView
        }
        setShowButton(shouldShow)
    }

    private func setShowButton(_ visible: Bool) {
        guard showButton != visible else { return }
        withAnimation(.easeOut(duration: 0.16)) {
            showButton = visible
        }
    }
}
