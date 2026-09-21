import AppKit
import Combine
import ObjectiveC

// MARK: - Swizzle 状态（文件级，避免函数内 static 编译错误）

private var swizzledClasses: Set<String> = []
private typealias SetBGIMP = @convention(c) (CALayer, Selector, CGColor?) -> Void
private var calayerSetBG_Original: SetBGIMP? = nil

/// 一次性 swizzle 两层防护，彻底消除 NSStatusItem 宿主窗口的黑底：
///
/// **根因层 — swizzle CALayer.setBackgroundColor:**
/// macOS 系统在创建 NSStatusItem 后，会异步给宿主容器 NSNextStepFrame /
/// NSStatusBarContentView 的 layer.backgroundColor 设一个约 0.129 gray
/// 的深灰色（我们称"黑底"）。之前只 swizzle 了 NSView 的 drawRect: /
/// drawLayer:inContext: / isOpaque —— 但 CALayer.backgroundColor 是
/// CoreAnimation 内部直接光栅化的，完全不经过 AppKit 绘图路径。
/// 现在我们 swizzle CALayer.setBackgroundColor:，在 IMP 里检查 layer 的
/// delegate 链，如果属于 NSNextStepFrame 或 NSStatusBarContentView，
/// 强制用原 IMP 设成 clear，阻止系统设黑底。
///
/// **视图层 — swizzle NSNextStepFrame / NSStatusBarContentView 的绘制方法**
/// isOpaque → false, drawRect: → 空, drawLayer:inContext: → 空
/// 作为双重保险。
///
/// 必须在创建任何 NSStatusItem 之前调用一次。
private func swizzleBlackBgClasses() {
    // MARK: 根因层 — CALayer.setBackgroundColor: 拦截
    
    if !swizzledClasses.contains("CALayer.setBackgroundColor") {
        swizzledClasses.insert("CALayer.setBackgroundColor")
        let sel = Selector("setBackgroundColor:")
        guard let method = class_getInstanceMethod(CALayer.self, sel) else {
            writeLog("swizzle CALayer.setBackgroundColor: FAIL: method not found"); return
        }
        let origIMP = method_getImplementation(method)
        calayerSetBG_Original = unsafeBitCast(origIMP, to: SetBGIMP.self)
        
        let newIMP: SetBGIMP = { layer, _cmd, requestedColor in
            // 判断这个 CALayer 是否属于系统状态栏宿主容器
            var shouldBlock = false
            if let owner = layer.delegate as? NSView {
                var v: NSView? = owner
                while let view = v {
                    let clsName = String(describing: type(of: view))
                    if clsName == "NSNextStepFrame" || clsName == "NSStatusBarContentView" {
                        shouldBlock = true
                        break
                    }
                    v = view.superview
                }
            }
            
            if shouldBlock {
                // 强制 clear —— 用原 IMP 调，避免触发 swizzle 递归
                calayerSetBG_Original?(layer, _cmd, CGColor.clear)
            } else {
                // 正常传递给原实现
                calayerSetBG_Original?(layer, _cmd, requestedColor)
            }
        }
        
        method_setImplementation(method, unsafeBitCast(newIMP, to: IMP.self))
        writeLog("✅ swizzle CALayer.setBackgroundColor: OK (根因层)")
    }
    
    // MARK: 视图层 — 双重保险
    
    for clsName in ["NSNextStepFrame", "NSStatusBarContentView"] {
        guard let cls = NSClassFromString(clsName) else {
            writeLog("swizzle \(clsName) FAIL: not found"); continue
        }
        if swizzledClasses.contains(clsName) { continue }
        swizzledClasses.insert(clsName)
        writeLog("swizzle \(clsName) START")

        func swizzle(_ selName: String, _ impl: IMP) {
            let sel = Selector(selName)
            if class_getInstanceMethod(cls, sel) == nil {
                let ok = class_addMethod(cls, sel, impl, "")
                writeLog("  addmethod \(selName) = \(ok ? "OK" : "FAIL")")
            } else if let m = class_getInstanceMethod(cls, sel) {
                method_setImplementation(m, impl)
                writeLog("  swizzle \(selName) = OK")
            }
        }

        typealias IsOpaqueIMP = @convention(c) (Any, Selector) -> Bool
        swizzle("isOpaque", unsafeBitCast({ (_: Any, _: Selector) -> Bool in false } as IsOpaqueIMP, to: IMP.self))

        typealias DrawRectIMP = @convention(c) (Any, Selector, NSRect) -> Void
        swizzle("drawRect:", unsafeBitCast({ (_: Any, _: Selector, _: NSRect) -> Void in } as DrawRectIMP, to: IMP.self))

        typealias DrawLayerIMP = @convention(c) (Any, Selector, CALayer, CGContext) -> Void
        swizzle("drawLayer:inContext:", unsafeBitCast({ (_: Any, _: Selector, _: CALayer, _: CGContext) -> Void in } as DrawLayerIMP, to: IMP.self))

        writeLog("swizzle \(clsName) DONE")
    }
}

private func writeLog(_ msg: String) {
    let path = "/tmp/mb-patch.log"
    let line = msg + "\n"
    if let data = line.data(using: .utf8) {
        let handle = FileHandle(forWritingAtPath: path)
        if let handle {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

/// 透明状态栏视图基类：drawRect 空实现 + isOpaque = false + 不启用 CALayer，
/// 完全不画任何底色，彻底绕开系统给 NSStatusItem.button 包的 NSNextStepFrame 黑底容器。
class BarTransparentView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ dirtyRect: NSRect) { /* intentionally empty */ }
    override var isOpaque: Bool { false }
}

/// 歌词状态项：用自定义 NSTextField，完全透明、固定白色、横向+垂直居中
final class LyricBarView: BarTransparentView {
    let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(label)
        label.font = MenuBarPlayerController.lyricFont
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.drawsBackground = false
        label.isBezeled = false
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        // 单独给 label 开 layer，用于 CATransition 歌词过渡动画
        label.wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        // 垂直居中：NSTextField(labelWithString:) 默认贴顶，手动算 y 偏移
        let font = MenuBarPlayerController.lyricFont
        let textHeight = ceil(font.ascender - font.descender + font.leading)
        let y = floor((bounds.height - textHeight) / 2)
        label.frame = NSRect(x: 0, y: y, width: bounds.width, height: textHeight)
    }

    func setText(_ text: String) {
        label.stringValue = text
    }
}

/// 图标状态项：点击弹 popover 迷你播放器
final class IconBarView: BarTransparentView {
    var onClick: (() -> Void)?

    private let imageView: NSImageView = {
        let v = NSImageView()
        v.image = MenuBarLogo.makeIcon()
        return v
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        // 重写 mouseDown: 比 NSClickGestureRecognizer 在状态栏里更可靠
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let sz = MenuBarPlayerController.iconSize
        let y = (bounds.height - sz) / 2
        let x = (bounds.width - sz) / 2
        imageView.frame = NSRect(x: x, y: y, width: sz, height: sz)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

// MARK: - DraggableProgressView（带 thumb 的可拖动进度条）

final class DraggableProgressView: NSView {
    /// 0~1 的进度值
    var value: Double = 0 {
        didSet { layoutThumbAndFill() }
    }
    /// 用户拖动时回调（用于 seek）
    var onSeek: ((Double) -> Void)?

    fileprivate var isDragging = false

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true  // 必须 true 才能用 CALayer
        setupSublayers()
    }
    required init?(coder: NSCoder) { nil }

    private func setupSublayers() {
        // 颜色
        let blue = NSColor.systemBlue.cgColor
        let gray = NSColor(calibratedWhite: 0.78, alpha: 1).cgColor

        // track layer（灰色轨道）
        let track = CALayer()
        track.name = "track"
        track.cornerRadius = trackHeight / 2
        track.backgroundColor = gray
        layer?.addSublayer(track)

        // fill layer（蓝色进度）
        let fill = CALayer()
        fill.name = "fill"
        fill.cornerRadius = trackHeight / 2
        fill.backgroundColor = blue
        layer?.addSublayer(fill)

        // thumb layer（实心蓝色圆 + 柔和阴影）
        let thumb = CALayer()
        thumb.name = "thumb"
        thumb.cornerRadius = thumbSize / 2
        thumb.backgroundColor = blue
        thumb.shadowColor = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        thumb.shadowOpacity = 0.6
        thumb.shadowOffset = CGSize(width: 0, height: 0)
        thumb.shadowRadius = 3
        layer?.addSublayer(thumb)
    }

    override func layout() {
        super.layout()
        layoutSublayers()
        layoutThumbAndFill()
    }

    private func layoutSublayers() {
        guard let sublayers = layer?.sublayers else { return }
        let trackY = (bounds.height - trackHeight) / 2
        for sub in sublayers {
            switch sub.name {
            case "track":
                sub.frame = NSRect(x: 0, y: trackY, width: bounds.width, height: trackHeight)
            case "fill":
                break // layoutThumbAndFill 处理
            case "thumb":
                break
            default:
                break
            }
        }
    }

    private func layoutThumbAndFill() {
        guard let sublayers = layer?.sublayers else { return }
        let w = bounds.width
        let trackY = (bounds.height - trackHeight) / 2
        let progressW = w * CGFloat(min(max(value, 0), 1))

        // 拖动时禁用隐式动画，保证 thumb 严格跟手；
        // 非拖动（播放自动推进 / seek 完成）时加短动画，进度条丝滑过渡。
        let animated = !isDragging
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        }

        if let fill = sublayers.first(where: { $0.name == "fill" }) {
            fill.frame = NSRect(x: 0, y: trackY, width: progressW, height: trackHeight)
        }
        if let thumb = sublayers.first(where: { $0.name == "thumb" }) {
            let thumbX = progressW - thumbSize / 2
            let thumbY = (bounds.height - thumbSize) / 2
            thumb.frame = NSRect(x: thumbX, y: thumbY, width: thumbSize, height: thumbSize)
            thumb.isHidden = progressW <= 0 || w <= 0
        }

        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateValueFromEvent(event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        updateValueFromEvent(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        onSeek?(value)
    }

    private func updateValueFromEvent(_ event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let rawX = localPoint.x
        let v = Double(min(max(rawX / max(bounds.width, 1), 0), 1))
        value = v
        // 拖动过程中只更新 UI 不实时 seek，避免频繁跳转音频造成卡顿；
        // 真正的 seek 放在 mouseUp 时执行。
    }
}

// MARK: - MiniPlayerView

/// Popover 迷你播放器面板
final class MiniPlayerView: NSView {

    // MARK: - 回调
    var onPlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((Double) -> Void)?

    // MARK: - UI
    private let artworkView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "未在播放")
    private let artistLabel = NSTextField(labelWithString: "")
    private let progressView = DraggableProgressView()
    private var playPauseBtn: NSButton!
    private var nextBtn: NSButton!
    private var prevBtn: NSButton!

    private let artworkSize: CGFloat = 140
    private let panelWidth: CGFloat = 220
    private let panelHeight: CGFloat = 290

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        setupArtwork()
        setupLabels()
        setupProgress()
        setupControls()
    }
    required init?(coder: NSCoder) { nil }

    private func setupArtwork() {
        addSubview(artworkView)
        artworkView.wantsLayer = true
        artworkView.layer?.cornerRadius = 12
        artworkView.layer?.masksToBounds = true
        artworkView.imageScaling = .scaleAxesIndependently
        artworkView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        artworkView.frame = NSRect(
            x: (panelWidth - artworkSize) / 2,
            y: panelHeight - artworkSize - 16,
            width: artworkSize,
            height: artworkSize
        )
    }

    private func setupLabels() {
        addSubview(titleLabel)
        addSubview(artistLabel)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 16, y: panelHeight - artworkSize - 16 - 28, width: panelWidth - 32, height: 18)

        artistLabel.font = .systemFont(ofSize: 12)
        artistLabel.textColor = .secondaryLabelColor
        artistLabel.alignment = .center
        artistLabel.lineBreakMode = .byTruncatingTail
        artistLabel.frame = NSRect(x: 16, y: panelHeight - artworkSize - 16 - 46, width: panelWidth - 32, height: 16)
    }

    private func setupProgress() {
        addSubview(progressView)
        progressView.frame = NSRect(x: 20, y: panelHeight - artworkSize - 16 - 76, width: panelWidth - 40, height: 16)
        progressView.onSeek = { [weak self] ratio in
            self?.onSeek?(ratio)
        }
    }

    private func setupControls() {
        let btnSize: CGFloat = 32
        let spacing: CGFloat = 16
        let totalW = btnSize * 3 + spacing * 2
        let startX = (panelWidth - totalW) / 2
        let btnY: CGFloat = panelHeight - artworkSize - 16 - 76 - 44

        func makeBtn(_ symbol: String, _ ptSize: CGFloat = 14, _ weight: NSFont.Weight = .medium) -> NSButton {
            let b = NSButton(frame: NSRect(x: 0, y: 0, width: btnSize, height: btnSize))
            b.bezelStyle = .regularSquare
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.contentTintColor = NSColor.labelColor
            let cfg = NSImage.SymbolConfiguration(pointSize: ptSize, weight: weight)
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)
            return b
        }

        prevBtn = makeBtn("backward.end.fill")
        prevBtn.frame.origin = NSPoint(x: startX, y: btnY)
        prevBtn.target = self
        prevBtn.action = #selector(prevTapped)
        addSubview(prevBtn)

        playPauseBtn = makeBtn("play.fill", 16, .semibold)
        playPauseBtn.frame = NSRect(x: startX + btnSize + spacing, y: btnY - 2, width: btnSize + 4, height: btnSize + 4)
        playPauseBtn.target = self
        playPauseBtn.action = #selector(playPauseTapped)
        addSubview(playPauseBtn)

        nextBtn = makeBtn("forward.end.fill")
        nextBtn.frame.origin = NSPoint(x: startX + (btnSize + spacing) * 2, y: btnY)
        nextBtn.target = self
        nextBtn.action = #selector(nextTapped)
        addSubview(nextBtn)
    }

    // MARK: - Actions

    @objc private func playPauseTapped() { onPlayPause?() }
    @objc private func prevTapped() { onPrevious?() }
    @objc private func nextTapped() { onNext?() }

    // MARK: - Public 更新方法

    func update(track: Track?, artwork: NSImage?, isPlaying: Bool, currentTime: Double, duration: Double) {
        artworkView.image = artwork
        titleLabel.stringValue = track?.displayTitle ?? "未在播放"
        artistLabel.stringValue = track?.artist ?? ""

        let symbol = isPlaying ? "pause.fill" : "play.fill"
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        playPauseBtn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)

        let progress = duration > 0 ? currentTime / duration : 0
        // 拖动中不覆盖 thumb 位置
        if !progressView.isDragging {
            progressView.value = progress
        }
    }
}

/// 菜单栏播放控制：两个相邻状态项——左侧固定宽度区域实时显示当前歌词
/// （固定白色、横向居中、切换有过渡动画），右侧为播放图标（主人设计的
/// SVG 主体），左键/右键点击图标弹出「播放 / 暂停」菜单。
@MainActor
final class MenuBarPlayerController: NSObject {
    static let shared = MenuBarPlayerController()

    static let enabledKey = "ManyuMusic.menuBarPlayer"
    static let lyricTransitionKey = "ManyuMusic.lyricTransition"

    fileprivate static let lyricFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    fileprivate static let lyricColor = NSColor.white
    fileprivate static let lyricMinWidth: CGFloat = 60
    fileprivate static let lyricMaxWidth: CGFloat = 280
    fileprivate static let iconSize: CGFloat = 18

    // MARK: 歌词过渡效果

    enum LyricTransition: String, CaseIterable, Identifiable {
        case none = "none"
        case fade = "fade"
        case revealLeft = "revealLeft"
        case revealRight = "revealRight"
        case pushLeft = "pushLeft"
        case pushRight = "pushRight"
        case dissolve = "dissolve"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: return "无"
            case .fade: return "渐隐渐显"
            case .revealLeft: return "从左揭开"
            case .revealRight: return "从右揭开"
            case .pushLeft: return "从左推入"
            case .pushRight: return "从右推入"
            case .dissolve: return "像素溶解"
            }
        }

        static func load() -> LyricTransition {
            guard let raw = UserDefaults.standard.string(forKey: lyricTransitionKey),
                  let v = LyricTransition(rawValue: raw) else {
                return .none
            }
            return v
        }
        static func save(_ v: LyricTransition) {
            UserDefaults.standard.set(v.rawValue, forKey: lyricTransitionKey)
        }
    }

    static var lyricTransition: LyricTransition {
        get { LyricTransition.load() }
        set { LyricTransition.save(newValue) }
    }

    // MARK: 实例变量

    private var lyricItem: NSStatusItem?
    private var iconItem: NSStatusItem?
    private var popover: NSPopover?
    private var miniPlayerView: MiniPlayerView?
    private var cancellables: Set<AnyCancellable> = []
    private var lastLyricText = ""
    private var lyricView: LyricBarView?
    private var iconView: IconBarView?

    private struct LyricState: Equatable {
        let hasLyrics: Bool
        let text: String
    }

    private override init() {
        super.init()
    }

    func syncWithSetting() {
        writeLog("🟢 syncWithSetting 被调用, isEnabled=\(isEnabled)")
        swizzleBlackBgClasses()
        if isEnabled {
            install()
        } else {
            remove()
        }
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    // MARK: - 状态项装卸

    private func install() {
        guard iconItem == nil else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.iconItem == nil else { return }

            // 歌词项
            let lyricItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let lyricView = LyricBarView(frame: NSRect(x: 0, y: 0, width: Self.lyricMinWidth, height: NSStatusBar.system.thickness))
            lyricItem.view = lyricView
            self.lyricItem = lyricItem
            self.lyricView = lyricView

            // 图标项：带点击回调，弹 popover 迷你播放器
            let iconItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let iconView = IconBarView(frame: NSRect(x: 0, y: 0, width: NSStatusItem.squareLength, height: NSStatusBar.system.thickness))
            iconView.onClick = { [weak self] in self?.togglePopover() }
            iconItem.view = iconView
            self.iconItem = iconItem
            self.iconView = iconView

            // popover 迷你播放器
            let mini = MiniPlayerView()
            mini.onPlayPause = { AudioPlayer.shared.isPlaying ? AudioPlayer.shared.pause() : AudioPlayer.shared.resume() }
            mini.onNext = { AudioPlayer.shared.next() }
            mini.onPrevious = { AudioPlayer.shared.previous() }
            mini.onSeek = { ratio in
                let duration = AudioPlayer.shared.clock.duration
                if duration > 0 {
                    AudioPlayer.shared.seek(to: ratio * duration)
                }
            }
            self.miniPlayerView = mini

            let popover = NSPopover()
            popover.contentViewController = NSViewController()
            popover.contentViewController?.view = mini
            popover.behavior = .transient
            popover.animates = true
            self.popover = popover

            self.observeLyrics()
            self.observePlayer()
            // 初始刷新一次
            self.refreshMiniPlayer()

            // 稀疏 Timer：每 0.2s 清一次 layer 背景（覆盖系统重绘时机）
            var remaining = 20
            Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] t in
                remaining -= 1
                self?.stripOnce()
                if remaining <= 0 { t.invalidate() }
            }
        }
    }

    private func stripOnce() {
        for item in [lyricItem, iconItem] {
            var sv: NSView? = item?.view
            while let view = sv {
                // 清任何有 layer 背景的层
                if view.layer?.backgroundColor != nil {
                    view.layer?.backgroundColor = NSColor.clear.cgColor
                }
                sv = view.superview
            }
        }
    }

    private func remove() {
        cancellables.removeAll()
        lastLyricText = ""
        lyricView = nil
        iconView = nil
        popover?.close()
        popover = nil
        miniPlayerView = nil
        if let lyricItem {
            NSStatusBar.system.removeStatusItem(lyricItem)
            self.lyricItem = nil
        }
        if let iconItem {
            NSStatusBar.system.removeStatusItem(iconItem)
            self.iconItem = nil
        }
    }

    // MARK: - Popover 控制

    private func togglePopover() {
        guard let popover, let iconView else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // 确保在下一轮 runloop 弹出，避免事件冒泡冲突
            DispatchQueue.main.async {
                self.refreshMiniPlayer()
                popover.show(relativeTo: iconView.bounds, of: iconView, preferredEdge: .minY)
            }
        }
    }

    // MARK: - 播放器状态订阅（迷你播放器 UI 实时刷新）

    private func observePlayer() {
        let player = AudioPlayer.shared
        Publishers.CombineLatest4(
            player.$currentTrack,
            player.$artwork,
            player.$isPlaying,
            player.clock.$currentTime
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            Task { @MainActor in self?.refreshMiniPlayer() }
        }
        .store(in: &cancellables)

        // 时钟 duration 变化也要刷新
        player.clock.$duration
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refreshMiniPlayer() }
            }
            .store(in: &cancellables)
    }

    private func refreshMiniPlayer() {
        guard let mini = miniPlayerView else { return }
        let p = AudioPlayer.shared
        mini.update(
            track: p.currentTrack,
            artwork: p.artwork,
            isPlaying: p.isPlaying,
            currentTime: p.clock.currentTime,
            duration: p.clock.duration
        )
    }

    // MARK: - 歌词实时刷新

    private func observeLyrics() {
        let player = AudioPlayer.shared
        Publishers.CombineLatest3(
            player.$currentTrack,
            player.$lyricLines,
            player.clock.$currentTime
        )
        .map { (track, lines, _) -> LyricState in
            LyricState(hasLyrics: track != nil && !lines.isEmpty, text: player.currentLyricText ?? "")
        }
        .removeDuplicates()
        .sink { [weak self] state in
            Task { @MainActor in
                self?.handleLyricChange(hasLyrics: state.hasLyrics, text: state.text)
            }
        }
        .store(in: &cancellables)
    }

    private func handleLyricChange(hasLyrics: Bool, text: String) {
        if !hasLyrics {
            lastLyricText = ""
        } else if !text.isEmpty {
            lastLyricText = text
        }
        guard let lyricItem, let lyricView else { return }
        if !lastLyricText.isEmpty {
            let w = Self.lyricWidth(for: lastLyricText)
            lyricItem.length = w
            lyricView.setLyricWithTransition(lastLyricText)
            lyricItem.isVisible = true
        } else {
            lyricView.setLyricWithTransition("")
            lyricItem.isVisible = false
        }
    }

    fileprivate static func lyricWidth(for text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: lyricFont]
        let size = (text as NSString).boundingRect(
            with: CGSize(width: lyricMaxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        ).width
        let w = ceil(size) + 10
        return min(max(w, lyricMinWidth), lyricMaxWidth)
    }
}

// MARK: - 歌词过渡动画

extension LyricBarView {
    func setLyricWithTransition(_ newText: String) {
        label.stringValue = newText

        let t = MenuBarPlayerController.lyricTransition
        guard t != .none, let layer = label.layer else { return }

        let trans = CATransition()
        trans.duration = 0.45
        trans.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        trans.isRemovedOnCompletion = true
        switch t {
        case .fade:        trans.type = .fade
        case .revealLeft:  trans.type = .reveal;  trans.subtype = .fromLeft
        case .revealRight: trans.type = .reveal;  trans.subtype = .fromRight
        case .pushLeft:    trans.type = .push;    trans.subtype = .fromLeft
        case .pushRight:   trans.type = .push;    trans.subtype = .fromRight
        case .dissolve:    trans.type = .fade
        case .none:        break
        }
        layer.add(trans, forKey: "lyricTransition")
    }
}
