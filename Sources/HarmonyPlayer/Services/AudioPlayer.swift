import Accelerate
import AppKit
import AVFoundation
import Combine
import CoreImage
import MediaPlayer

/// High-frequency playback progress, kept apart from `AudioPlayer` so the
/// 0.25s tick and the 1s sleep-timer countdown only invalidate the small
/// views that actually render them, instead of the whole view hierarchy.
@MainActor
final class PlaybackClock: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var sleepTimerRemaining: TimeInterval?
}

@MainActor
final class AudioPlayer: ObservableObject {
    static let rememberPlaybackKey = "ManyuMusic.rememberPlaybackState"
    /// 无缝播放（gapless）：自然连播时提前预载下一首，结尾处近无间隙接管。
    static let gaplessPlaybackKey = "ManyuMusic.gaplessPlayback"
    /// 淡入淡出（crossfade）：切歌时旧曲渐弱、新曲渐强，重叠过渡。
    static let crossfadeEnabledKey = "ManyuMusic.crossfadeEnabled"
    /// crossfade 重叠时长（秒），设置里 3~12 可调，默认 6。
    static let crossfadeDurationKey = "ManyuMusic.crossfadeDuration"
    static let defaultCrossfadeDuration: TimeInterval = 6
    static let crossfadeDurationRange: ClosedRange<Double> = 3...12
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkPalette: ArtworkPalette?
    /// 预渲染好的模糊封面背景：播放页转场直接贴图，
    /// 不再挂全屏实时 blur 层（转场首帧的光栅化大头）。
    @Published private(set) var backdropImage: NSImage?
    /// 预烘焙的背景光斑（主色/次色）：播放页进出时 GPU 不再现算大半径模糊层。
    @Published private(set) var orbPrimaryImage: NSImage?
    @Published private(set) var orbSecondaryImage: NSImage?
    @Published private(set) var lyricLines: [LyricLine] = []
    /// 当前歌曲的歌词读取是否已落定（有歌词或确认无歌词）。
    /// 未落定时播放页显示“正在等待歌词”，落定且为空才显示“暂无歌词”。
    @Published private(set) var lyricsResolved = false
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var sleepTimerEnd: Date?
    @Published var volume: Double = 0.78 {
        didSet {
            // crossfade 期间两个引擎可能同时出声，音量变化要同时作用于
            // 当前引擎与备用引擎（各自乘上当前淡变增益）。
            applyVolume(to: engineA)
            applyVolume(to: engineB)
            saveVolume()
        }
    }
    @Published var isShuffle = false
    @Published var repeatMode: RepeatMode = .off
    /// 三态合一的播放模式（顺序 → 单曲循环 → 随机）。点击循环钮时切换，
    /// 底层仍同步设置 isShuffle / repeatMode 驱动实际播放推进。
    @Published private(set) var playbackMode: PlaybackMode = .sequential
    @Published var playbackError: String?
    /// 当前歌曲的歌词时间轴偏移（秒）。正 = 歌词延后显示，负 = 提前显示。
    @Published private(set) var lyricOffset: Double = 0

    /// Progress state shared with the minimal views that need it. Views must
    /// receive `player.clock` explicitly; `clock.objectWillChange` is never
    /// forwarded into `AudioPlayer`, so ticking the clock does not invalidate
    /// every observer of the player.
    let clock = PlaybackClock()

    /// Read/write proxies onto `clock`, so every seek, restore and duration
    /// update keeps the player, the lyrics and the progress UI in sync.
    private(set) var currentTime: Double {
        get { clock.currentTime }
        set { clock.currentTime = newValue }
    }

    private(set) var duration: Double {
        get { clock.duration }
        set { clock.duration = newValue }
    }

    /// Convenience read for existing call sites. The countdown value lives on
    /// `clock`; views that must update every second should observe
    /// `player.clock` instead of the player.
    var sleepTimerRemaining: TimeInterval? { clock.sleepTimerRemaining }

    // MARK: - 双引擎乒乓（crossfade / gapless）

    /// 两个固定 AVPlayer 实例：正常播放时 activeEngine 出声；切歌走
    /// crossfade/gapless 时，新曲在 standbyEngine 起播，完成后身份对调。
    /// 普通切换（功能关、暂停点歌、快切、首播）仍在 activeEngine 上
    /// replaceCurrentItem，行为与历史一致。
    private let engineA = AVPlayer()
    private let engineB = AVPlayer()
    /// 当前出声引擎，在 init 里指向 engineA；不能用属性默认值引用另一属性。
    private var activeEngine: AVPlayer!
    private var standbyEngine: AVPlayer { activeEngine === engineA ? engineB : engineA }
    /// 所有既有内部代码使用的便捷入口，始终指向当前出声的引擎（显式非可选）。
    private var player: AVPlayer { activeEngine }

    /// 每个引擎的淡变增益（0...1）。实际音量 = 用户音量 × gain。
    /// 非过渡时两者恒为 1；crossfade 时旧引擎 1→0、新引擎 0→1。
    private var engineGain: [ObjectIdentifier: Double] = [:]
    private func gain(of engine: AVPlayer) -> Double {
        engineGain[ObjectIdentifier(engine)] ?? 1
    }
    private func applyVolume(to engine: AVPlayer) {
        engine.volume = Float(volume * gain(of: engine))
    }
    private func setGain(_ engine: AVPlayer, _ value: Double) {
        engineGain[ObjectIdentifier(engine)] = value
        applyVolume(to: engine)
    }

    /// 进行中的 crossfade 代数号：每次新开淡变 +1，旧 ramp 轮询发现
    /// 代数不符立即退出（不做收尾清理），避免快切时多个淡变互相打架。
    private var fadeGeneration = 0
    /// crossfade 进行中为 true：屏蔽非 active 引擎与短暂 waiting 造成的
    /// isPlaying 抖动（过渡期间播放态恒为真）。
    private var isCrossfading = false

    /// gapless 预载状态：非 nil 表示已在 standbyEngine 装好下一首并
    /// preroll，等待 boundary 精确接管；接管或撤销时复位为 nil。
    private var armedGaplessIndex: Int?
    private var gaplessBoundary: Any?
    /// boundary observer 必须在添加它的同一个引擎上移除，单独记录。
    private weak var gaplessBoundaryEngine: AVPlayer?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var itemStatusObservation: NSKeyValueObservation?
    private var sleepTimerTask: Task<Void, Never>?
    private var willTerminateObserver: NSObjectProtocol?
    private var keyEventMonitor: Any?
    private var lastPersistedSecond = -1
    private var didAttemptPlaybackRestore = false
    private let volumeKey = "HarmonyPlayer.playbackVolume"

    private let defaults: UserDefaults

    // MARK: - 播放增强开关（设置里可切换，切歌/连播时读取最新值）

    var gaplessEnabled: Bool {
        defaults.object(forKey: Self.gaplessPlaybackKey) as? Bool ?? false
    }
    var crossfadeEnabled: Bool {
        defaults.object(forKey: Self.crossfadeEnabledKey) as? Bool ?? false
    }
    var crossfadeDuration: TimeInterval {
        let stored = defaults.object(forKey: Self.crossfadeDurationKey) as? Double
        guard let stored else { return Self.defaultCrossfadeDuration }
        // 存量值钳制在滑块区间内，外部写入的垃圾值不会产生 0 秒或超长淡变。
        let range = Self.crossfadeDurationRange
        return min(max(stored, range.lowerBound), range.upperBound)
    }

    /// 十段图形均衡器：参数共享给音频 tap，预设与自定义曲线也由它持久化。
    let equalizer = Equalizer()

    /// 均衡器开关（设置里切换）：对当前两个引擎上的 item 实时挂/摘 tap。
    func setEQEnabled(_ enabled: Bool) {
        equalizer.isEnabled = enabled
        if enabled {
            if let item = activeEngine.currentItem {
                EQTap.attach(to: item, equalizer: equalizer)
            }
            if let item = standbyEngine.currentItem {
                EQTap.attach(to: item, equalizer: equalizer)
            }
        } else {
            EQTap.detach(from: activeEngine.currentItem)
            EQTap.detach(from: standbyEngine.currentItem)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.activeEngine = engineA
        let savedVolume = defaults.object(forKey: volumeKey) as? Double
        volume = savedVolume ?? 0.78
        for engine in [engineA, engineB] {
            engine.automaticallyWaitsToMinimizeStalling = false
            setGain(engine, 1)
        }
        configurePlayerObservation()
        configureRemoteCommands()

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSTextView) else {
                return event
            }

            Task { @MainActor in
                self?.togglePlayback()
            }
            return nil
        }

        willTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.persistPlaybackState(force: true)
            }
        }
    }

    func restorePlaybackState(from availableTracks: [Track]) {
        guard !didAttemptPlaybackRestore else { return }
        // 歌库尚未加载完成（tracks 为空）时提前返回，不消耗恢复机会；
        // 调用方会在 isLoading 变 false 后再次调用。
        guard !availableTracks.isEmpty else { return }
        didAttemptPlaybackRestore = true

        guard rememberPlaybackState, currentTrack == nil else { return }

        let defaults = self.defaults
        guard let trackIDString = defaults.string(forKey: PlaybackStateKeys.trackID),
              let trackID = UUID(uuidString: trackIDString),
              let track = availableTracks.first(where: { $0.id == trackID }),
              FileManager.default.fileExists(atPath: track.url.path) else {
            return
        }

        let tracksByID = Dictionary(uniqueKeysWithValues: availableTracks.map { ($0.id, $0) })
        let savedQueue = (defaults.array(forKey: PlaybackStateKeys.queueIDs) as? [String] ?? [])
            .compactMap(UUID.init(uuidString:))
            .compactMap { tracksByID[$0] }
        let restoredQueue = savedQueue.isEmpty ? [track] : savedQueue

        queue = restoredQueue
        currentIndex = restoredQueue.firstIndex(where: { $0.id == track.id }) ?? 0
        currentTrack = track
        duration = track.duration

        // 恢复播放模式（三态合一）。
        if let savedModeRaw = defaults.string(forKey: PlaybackStateKeys.playbackMode),
           let savedMode = PlaybackMode(rawValue: savedModeRaw) {
            setPlaybackMode(savedMode)
        }

        let savedTime = defaults.double(forKey: PlaybackStateKeys.currentTime)
        currentTime = max(0, min(savedTime, track.duration > 0 ? track.duration : savedTime))

        let item = Self.makePlaybackItem(url: track.url)
        // 均衡器开启时为恢复的条目挂 tap。
        EQTap.attachIfEnabled(to: item, equalizer: equalizer)
        player.replaceCurrentItem(with: item)
        applyVolume(to: player)
        player.seek(
            to: CMTime(seconds: currentTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )

        observeStatus(of: item)
        refreshDuration(for: track)
        loadArtwork(for: track)
        lyricLines = []
        lyricsResolved = false
        prepareLyrics(for: track)
        updateNowPlaying()
    }

    func clearRememberedPlaybackState() {
        let defaults = self.defaults
        defaults.removeObject(forKey: PlaybackStateKeys.trackID)
        defaults.removeObject(forKey: PlaybackStateKeys.queueIDs)
        defaults.removeObject(forKey: PlaybackStateKeys.currentIndex)
        defaults.removeObject(forKey: PlaybackStateKeys.currentTime)
        lastPersistedSecond = -1
    }

    func play(_ track: Track, in tracks: [Track]) {
        // 队列即将被整体替换：已预载的 gapless 下一首索引指向旧队列，
        // 不撤销会在接管时取出错的歌曲。先撤，之后 tick 会按新队列重新预排。
        disarmGapless()
        let playableQueue = tracks.isEmpty ? [track] : tracks
        queue = playableQueue
        currentIndex = playableQueue.firstIndex(where: { $0.id == track.id }) ?? 0

        if currentTrack?.id == track.id, player.currentItem != nil {
            resume()
            return
        }

        routeSwitch(to: track)
    }

    func togglePlayback() {
        guard currentTrack != nil else {
            if let index = queue.indices.first {
                currentIndex = index
                load(queue[index])
            }
            return
        }

        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func resume() {
        guard currentTrack != nil, player.currentItem != nil else { return }
        player.play()
        updateNowPlaying()
    }

    func pause() {
        // 暂停要立刻安静：撤掉待接管的 gapless 预载，打断 crossfade 让
        // 正在淡出的旧引擎立即静音，只保留当前引擎。
        disarmGapless()
        abortInFlightFade()
        player.pause()
        persistPlaybackState(force: true)
        updateNowPlaying()
    }

    func next() {
        move(by: 1, manual: true)
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        move(by: -1, manual: true)
    }

    /// 三态播放模式循环：顺序播放 → 单曲循环 → 随机播放 → 顺序播放。
    func cyclePlaybackMode() {
        setPlaybackMode(playbackMode.next)
    }

    /// 直接设置播放模式（首页「随机播放」、菜单栏等入口使用）。
    func setPlaybackMode(_ mode: PlaybackMode) {
        // 切模式会改变连播候选（尤其进/出随机），已预载的 gapless 下一首
        // 可能不再正确，撤销预载；正在进行的 crossfade 让它自然走完。
        disarmGapless()
        playbackMode = mode
        switch mode {
        case .sequential:
            isShuffle = false
            repeatMode = .off
        case .singleRepeat:
            isShuffle = false
            repeatMode = .one
        case .shuffle:
            isShuffle = true
            repeatMode = .off
            // 进入随机模式时打乱剩余曲目（保留当前播放的不动）。
            shuffleRemainingQueue()
        }
    }

    /// 打乱当前 queue 中 currentIndex 之后的曲目；前面已播过的保持原序。
    /// 每次随机切到下一首后调用，让下一批候选重新洗牌。
    private func shuffleRemainingQueue() {
        guard queue.count > 1 else { return }
        let base = (currentIndex ?? 0) + 1
        guard base < queue.count else { return }
        let remaining = Array(queue[base...]).shuffled()
        queue.replaceSubrange(base..., with: remaining)
    }

    /// 进行中的 seek。AVPlayer 落位前，0.25s 观察器仍会回调旧位置；
    /// 若放行，时钟会在目标值与旧位置之间乒乓（歌词行来回跳、进度条
    /// 锚点反复重同步）。seek 期间屏蔽观察器写钟，落位后由完成回调
    /// 写入一次真实位置。
    private var seekInFlight = false

    /// 快速连切检测：相邻两次 load 间隔小于该窗口即判定为连续快切。
    /// 慢速点歌（通常间隔 1 秒以上）不受影响，仍然立即播放。
    private static let rapidSwitchWindow: TimeInterval = 0.7
    /// 快切停止后静默该时长，确认不再有新切换，才开始播放最新曲目。
    private static let rapidSwitchSettleDelay: TimeInterval = 0.4
    private var lastLoadAt = Date.distantPast
    /// 快切期间为 true：播放器保持暂停、周期时间观察器忽略旧曲目回报。
    /// 暴露给进度行：墙钟插值在此期间必须冻结，否则播放条会把切歌
    /// 占用的墙钟时间误记为播放进度。
    @Published private(set) var isRapidSwitching = false
    /// 每次 load 自增的代数号：只有最后一次切换的延迟恢复任务会生效。
    private var switchGeneration = 0

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        // 拖动进度后，旧曲淡出/下一首预载都失去意义，立即收敛到单一引擎。
        disarmGapless()
        abortInFlightFade()
        let upperBound = duration > 0 ? duration : max(0, seconds)
        let target = min(max(0, seconds), upperBound)
        seekInFlight = true
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let landed = self.player.currentTime().seconds
                self.currentTime = landed.isFinite && landed > 0 ? landed : target
                self.seekInFlight = false
                self.persistPlaybackState(force: true)
                self.updateNowPlaying()
            }
        }
        currentTime = target
        persistPlaybackState(force: true)
        updateNowPlaying()
    }

    func playFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        routeSwitch(to: queue[index])
    }

    func playNext(_ track: Track) {
        disarmGapless()
        let insertionIndex = min((currentIndex ?? -1) + 1, queue.count)
        queue.insert(track, at: insertionIndex)
        if let currentIndex, insertionIndex <= currentIndex {
            self.currentIndex = currentIndex + 1
        }
        persistPlaybackState(force: true)
    }

    func addToQueue(_ track: Track) {
        disarmGapless()
        queue.append(track)
        if currentIndex == nil {
            currentIndex = queue.indices.last
        }
        persistPlaybackState(force: true)
    }

    func removeFromQueue(at offsets: IndexSet) {
        guard !queue.isEmpty else { return }
        disarmGapless()
        let currentID = currentTrack?.id
        queue = queue.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
        if let currentID {
            currentIndex = queue.firstIndex(where: { $0.id == currentID })
        } else {
            currentIndex = queue.isEmpty ? nil : 0
        }
        persistPlaybackState(force: true)
    }

    func clearQueue() {
        disarmGapless()
        guard let currentTrack else {
            queue.removeAll()
            currentIndex = nil
            return
        }
        queue = [currentTrack]
        currentIndex = 0
        persistPlaybackState(force: true)
    }

    func moveQueue(from offsets: IndexSet, to destination: Int) {
        disarmGapless()
        guard let currentID = currentTrack?.id else { return }
        queue.move(fromOffsets: offsets, toOffset: destination)
        currentIndex = queue.firstIndex(where: { $0.id == currentID })
        persistPlaybackState(force: true)
    }

    func setSleepTimer(minutes: Int?) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil

        guard let minutes else {
            sleepTimerEnd = nil
            clock.sleepTimerRemaining = nil
            return
        }

        let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerEnd = endDate
        clock.sleepTimerRemaining = endDate.timeIntervalSinceNow

        sleepTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let end = self.sleepTimerEnd else { return }
                let remaining = end.timeIntervalSinceNow

                if remaining <= 0 {
                    self.pause()
                    self.sleepTimerEnd = nil
                    self.clock.sleepTimerRemaining = nil
                    self.sleepTimerTask = nil
                    return
                }

                // Only the clock republishes once per second here; the player
                // itself stays quiet.
                self.clock.sleepTimerRemaining = remaining
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func toggleFavoriteState(in library: LibraryStore) {
        guard let track = currentTrack else { return }
        library.toggleFavorite(track)
    }

    /// 切换到新曲目时，所有与具体播放引擎无关的 UI/状态更新集中在此：
    /// 当前曲目、进度归零、时长、歌词、封面与背景、状态持久化。
    /// cut（load）、crossfade、gapless 三条路径共用，保证表现一致。
    private func present(_ track: Track) {
        currentTrack = track
        currentTime = 0
        duration = track.duration
        lyricLines = []
        lyricsResolved = false
        prepareLyrics(for: track)
        refreshDuration(for: track)
        loadArtwork(for: track)
        persistPlaybackState(force: true)
        updateNowPlaying()
        scheduleMemoryRelease()
    }

    /// cut 路径（普通切换）：在当前引擎上直接替换条目。功能全关、暂停时
    /// 点歌、连续快切、首播与播放恢复都走这里，行为与历史完全一致。
    private func load(_ track: Track) {
        guard FileManager.default.fileExists(atPath: track.url.path) else {
            playbackError = "找不到文件：\(track.url.lastPathComponent)"
            pause()
            return
        }

        // 直接替换：撤销待执行的 gapless 预载与未完成 crossfade，
        // 保证当前只有 activeEngine 出声，备用引擎干净静默。
        disarmGapless()
        abortInFlightFade()

        let now = Date()
        let rapid = now.timeIntervalSince(lastLoadAt) < Self.rapidSwitchWindow
        lastLoadAt = now
        switchGeneration += 1
        let generation = switchGeneration

        present(track)

        // Keep the previous artwork and Dock icon visible until the next
        // track's artwork has loaded. This removes the one-frame Dock flicker.
        let item = Self.makePlaybackItem(url: track.url)
        // 本地文件按需读取，无需长前向缓冲：限制解码缓冲上限，
        // 避免播放器为每首曲目驻留过多解码数据。
        item.preferredForwardBufferDuration = 45
        // 均衡器开启时为新条目挂音频处理 tap（cut / crossfade 新曲路径）。
        EQTap.attachIfEnabled(to: item, equalizer: equalizer)
        player.replaceCurrentItem(with: item)
        setGain(player, 1)

        if rapid || isRapidSwitching {
            // 连续快切：replaceCurrentItem 是异步的，新条目就绪前旧曲目仍会
            // 继续播放——不暂停就会出现“封面/名字/歌词已换、声音和进度条
            // 还停在前两首”的错位。立即暂停，等切歌停顿 0.4s 后只播最新一首。
            isRapidSwitching = true
            player.pause()
            scheduleRapidSwitchResume(generation: generation, trackID: track.id)
        } else {
            player.play()
        }

        observeStatus(of: item)
    }

    /// 切换分流：正在播放且开启 crossfade 时走淡入淡出；否则走普通 cut。
    /// 首播（当前无曲目）、暂停时点歌、连续快切期间一律 cut。
    private func routeSwitch(to track: Track) {
        let canCrossfade = crossfadeEnabled
            && currentTrack != nil
            && isPlaying
            && !isRapidSwitching
        if canCrossfade {
            beginCrossfade(to: track)
        } else {
            load(track)
        }
    }

    // MARK: - Crossfade（淡入淡出）

    /// 旧引擎保持出声并淡出，新曲在备用引擎从静音淡入；UI 立即切到新曲，
    /// clock 立即重绑新引擎（进度条从 0 走新曲）。ramp 结束后清理旧引擎。
    private func beginCrossfade(to track: Track) {
        guard FileManager.default.fileExists(atPath: track.url.path) else {
            playbackError = "找不到文件：\(track.url.lastPathComponent)"
            return
        }

        // 若上一个淡变尚未结束（6 秒内又切歌）：先作废其 ramp（不清理，
        // 由本次接管），并以各引擎当前瞬时增益作为新 ramp 的起点。
        let wasFading = isCrossfading
        fadeGeneration += 1
        let token = fadeGeneration

        let oldEngine = player
        let newEngine = standbyEngine

        disarmGapless()

        let item = Self.makePlaybackItem(url: track.url)
        item.preferredForwardBufferDuration = 45
        // 备用引擎上可能还留着上一轮旧曲（ramp 中途再切），直接覆盖。
        newEngine.replaceCurrentItem(with: item)
        let newFrom = wasFading ? gain(of: newEngine) : 0
        let oldFrom = gain(of: oldEngine)
        setGain(newEngine, newFrom)
        observeStatus(of: item)

        present(track)

        activeEngine = newEngine
        bindTimeObserver(to: newEngine)
        newEngine.play()
        isPlaying = true
        isCrossfading = true

        let seconds = max(0.5, crossfadeDuration)
        rampFade(
            token: token,
            from: (old: oldEngine, new: newEngine),
            startGain: (old: oldFrom, new: newFrom),
            duration: seconds
        )
    }

    private func rampFade(
        token: Int,
        from engines: (old: AVPlayer, new: AVPlayer),
        startGain: (old: Double, new: Double),
        duration: TimeInterval
    ) {
        Task { @MainActor [weak self] in
            let start = Date()
            while true {
                guard let self else { return }
                // 已被更新的淡变取代：立即退出，不做任何收尾（新 fade 接管）。
                guard token == self.fadeGeneration else { return }
                let t = min(1, Date().timeIntervalSince(start) / duration)
                // smoothstep：起收略缓，听感比线性更自然。
                let k = t * t * (3 - 2 * t)
                self.setGain(engines.new, startGain.new + (1 - startGain.new) * k)
                self.setGain(engines.old, startGain.old * (1 - k))
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(33))
            }
            guard let self else { return }
            self.finishFade(token: token, oldEngine: engines.old)
        }
    }

    private func finishFade(token: Int, oldEngine: AVPlayer) {
        guard token == fadeGeneration else { return }
        isCrossfading = false
        oldEngine.pause()
        oldEngine.replaceCurrentItem(with: nil)
        // 备用引擎增益复位为 1，供下一轮使用。
        setGain(oldEngine, 1)
        setGain(activeEngine, 1)
        isPlaying = activeEngine.timeControlStatus == .playing
        refreshDockIcon()
        updateNowPlaying()
    }

    /// 运输控制（暂停/seek/cut）打断淡变时调用：作废 ramp，把旧引擎立即
    /// 静音释放，让当前 activeEngine 成为唯一出声源。
    private func abortInFlightFade() {
        guard isCrossfading else { return }
        fadeGeneration += 1
        isCrossfading = false
        // activeEngine 是新曲所在引擎；另一个（正在淡出的旧引擎）静音清理。
        let other: AVPlayer = activeEngine === engineA ? engineB : engineA
        other.pause()
        other.replaceCurrentItem(with: nil)
        setGain(other, 1)
        setGain(activeEngine, 1)
    }

    // MARK: - Gapless（无缝）

    /// gapless 提前预载的时间窗口：在此剩余时间内装好下一首并 preroll。
    private let gaplessArmAhead: TimeInterval = 2.0
    /// boundary 距结尾的提前量：在此触发接管，preroll 过的新引擎起播，
    /// 与旧引擎最后一小段几乎零间隙衔接（本地文件通常不可闻）。
    private let gaplessTakeoverEpsilon: TimeInterval = 0.06

    /// 自然连播调度：周期 tick 中按开关在结尾前预排 crossfade 或 gapless。
    private func maybeArmNextTransition(currentTime: TimeInterval) {
        guard isPlaying,
              !isRapidSwitching,
              !isCrossfading,
              currentTrack != nil,
              duration > 0,
              repeatMode != .one   // 单曲循环：结尾重播同一首，绝不预载下一首
        else { return }
        if !crossfadeEnabled && !gaplessEnabled { return }

        let remaining = duration - currentTime
        guard remaining >= 0 else { return }
        // 曲目刚起播的前 0.5 秒不预排：避免比淡变窗口还短的曲目在
        // 起播瞬间就开始淡出（听众几乎听不到这首歌独立的部分）。
        guard currentTime >= 0.5 else { return }

        if crossfadeEnabled {
            // 自动连播也走 crossfade（主人选定：crossfade 优先于 gapless）。
            // beginCrossfade 内部会撤销已存在的 gapless 预载。
            guard remaining <= crossfadeDuration else { return }
            guard let idx = nextAutoPlaybackIndex() else { return }
            let track = queue[idx]
            currentIndex = idx
            beginCrossfade(to: track)
            if isShuffle { shuffleRemainingQueue() }
        } else {
            guard armedGaplessIndex == nil else { return }
            guard remaining <= gaplessArmAhead else { return }
            guard let idx = nextAutoPlaybackIndex() else { return }
            armGapless(to: idx)
        }
    }

    /// 计算自然连播（非手动）的下一首索引；列表结束且循环模式为关时返回
    /// nil（表示应停止，不预载，交由原结束通知处理）。
    private func nextAutoPlaybackIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        if isShuffle, queue.count > 1 {
            let alternatives = queue.indices.filter { $0 != currentIndex }
            return alternatives.randomElement()
        }
        var target = (currentIndex ?? 0) + 1
        if target >= queue.count {
            if repeatMode == .off { return nil }
            target = 0
        }
        return target
    }

    private func armGapless(to index: Int) {
        let track = queue[index]
        guard FileManager.default.fileExists(atPath: track.url.path) else { return }
        let next = standbyEngine
        let item = Self.makePlaybackItem(url: track.url)
        item.preferredForwardBufferDuration = 45
        // 均衡器开启时为预载条目挂 tap，接管后 EQ 无缝延续。
        EQTap.attachIfEnabled(to: item, equalizer: equalizer)
        next.replaceCurrentItem(with: item)
        setGain(next, 1)
        observeStatus(of: item)
        next.preroll(atRate: 1.0) { _ in }

        // 在当前曲结尾前 epsilon 处精确触发接管。
        let triggerTime = max(0, duration - gaplessTakeoverEpsilon)
        let boundaryTime = CMTime(seconds: triggerTime, preferredTimescale: 600)
        gaplessBoundary = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: boundaryTime)],
            queue: .main
        ) { [weak self] in
            Task { @MainActor in
                self?.takeoverGapless(to: index)
            }
        }
        gaplessBoundaryEngine = player
        armedGaplessIndex = index
    }

    private func takeoverGapless(to index: Int) {
        guard armedGaplessIndex == index else { return }
        let track = queue[index]
        let oldEngine = player
        let newEngine = standbyEngine
        // boundary 已触发，先在它所属的旧引擎上移除（一次性语义，避免重复触发）。
        if let boundary = gaplessBoundary {
            (gaplessBoundaryEngine ?? oldEngine).removeTimeObserver(boundary)
        }
        gaplessBoundary = nil
        gaplessBoundaryEngine = nil
        guard newEngine.currentItem != nil else {
            // 预载未就绪：放弃无缝，回退到普通自动连播。
            armedGaplessIndex = nil
            currentIndex = index
            load(track)
            return
        }

        currentIndex = index
        present(track)

        activeEngine = newEngine
        bindTimeObserver(to: newEngine)
        newEngine.play()
        isPlaying = true

        armedGaplessIndex = nil

        if isShuffle { shuffleRemainingQueue() }

        // 旧引擎还在播最后约 60ms，让它自然走完后静音释放（0.5s 足够）。
        let engineToClean = oldEngine
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, engineToClean !== self.activeEngine else { return }
            engineToClean.pause()
            engineToClean.replaceCurrentItem(with: nil)
        }
    }

    /// 撤销尚未接管的 gapless 预载（seek/暂停/手动切歌/队列变更时调用）。
    private func disarmGapless() {
        if let boundary = gaplessBoundary {
            (gaplessBoundaryEngine ?? player).removeTimeObserver(boundary)
        }
        gaplessBoundary = nil
        gaplessBoundaryEngine = nil
        if armedGaplessIndex != nil {
            // 仅清理备用引擎上的预载（绝不动 activeEngine）。
            let standby = standbyEngine
            standby.pause()
            standby.replaceCurrentItem(with: nil)
        }
        armedGaplessIndex = nil
    }

    /// 快切停顿后的恢复：代数号保证只有最后一次切换的任务会执行，
    /// 中间的恢复任务全部作废，连续暂停/恢复不会互相打架。
    private func scheduleRapidSwitchResume(generation: Int, trackID: UUID) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.rapidSwitchSettleDelay))
            guard let self, generation == self.switchGeneration else { return }
            self.isRapidSwitching = false
            guard self.currentTrack?.id == trackID else { return }
            self.player.play()
            self.updateNowPlaying()
        }
    }

    /// 切歌的封面解码、调色、背景模糊会产生大量一次性中间内存，任务结束后
    /// 内存虽已释放但 malloc 不立即把空闲页归还系统——报告占用停留在峰值。
    /// 延迟几秒等在途任务落地后做一次 malloc 归还，长会话报告占用保持平稳。
    private func scheduleMemoryRelease() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4) {
            malloc_zone_pressure_relief(malloc_default_zone(), 0)
        }
    }

    private func configurePlayerObservation() {
        // 播放态订阅两个引擎各一次：只采纳当前 activeEngine 的状态。
        // crossfade 期间屏蔽非播放态抖动（过渡在音乐上始终连续）。
        for engine in [engineA, engineB] {
            engine.publisher(for: \.timeControlStatus)
                .receive(on: RunLoop.main)
                .sink { [weak self, weak engine] status in
                    guard let self, let engine, engine === self.activeEngine else { return }
                    if self.isCrossfading, status != .playing { return }
                    self.isPlaying = status == .playing
                    self.refreshDockIcon()
                    self.updateNowPlaying()
                }
                .store(in: &cancellables)
        }

        bindTimeObserver(to: engineA)

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                // crossfade/gapless 接管后，旧引擎的结束通知其 item 已不属于
                // activeEngine，自然被忽略；只有当前曲自然播完才推进。
                guard notification.object as? AVPlayerItem === self.player.currentItem else { return }
                self.handleTrackFinished()
            }
        }
    }

    /// 把 0.25s 周期观察器绑到指定引擎。crossfade/gapless 翻转 activeEngine
    /// 后调用：旧 token 移除、新 token 绑定，clock 立即跟随新曲目从 0 走。
    /// 周期观察器当前绑定的引擎：removeTimeObserver 必须在添加它的同一个
    /// player 上调用，对错误的 player 调用会抛 NSInvalidArgumentException。
    private weak var timeObserverEngine: AVPlayer?

    private func bindTimeObserver(to engine: AVPlayer) {
        if let token = timeObserver, let owner = timeObserverEngine {
            owner.removeTimeObserver(token)
        }
        timeObserverEngine = engine
        timeObserver = engine.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self, weak engine] time in
            Task { @MainActor in
                guard let self, let engine, engine === self.activeEngine else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                // seek 落位前观察器回报的仍是旧位置，直接丢弃。
                if self.seekInFlight { return }
                // 快切期间观察器可能回报前两曲的位置，丢弃：进度条
                // 停在 0（present 已重置），等恢复播放后再走最新曲目的时间。
                if self.isRapidSwitching { return }
                self.currentTime = seconds
                self.persistPlaybackState(force: false)

                if self.duration <= 0,
                   let itemDuration = engine.currentItem?.duration.seconds,
                   itemDuration.isFinite,
                   itemDuration > 0 {
                    self.duration = itemDuration
                }

                // 自然连播：按开关在结尾前预排 crossfade / gapless。
                self.maybeArmNextTransition(currentTime: seconds)
            }
        }
    }

    private func observeStatus(of item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                self?.playbackError = item.error?.localizedDescription ?? "这首歌暂时无法播放。"
                self?.pause()
            }
        }
    }

    /// 播放条目统一走精确解析：AVPlayer 对 FLAC 的估算时序有已知偏差
    /// （收尾位置可超出元数据时长十几秒，Apple 论坛确认开启
    /// AVURLAssetPreferPreciseDurationAndTimingKey 是正确解法）。
    private static func makePlaybackItem(url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        )
        return AVPlayerItem(asset: asset)
    }

    private func refreshDuration(for track: Track) {
        // 曲库扫描已写入真实时长的曲目直接用，不再为每首歌建 AVURLAsset——
        // AVFoundation 内部会按 URL 缓存资产（解析结果/索引），逐首累积可观测。
        guard track.duration <= 0 else { return }
        Task {
            // 与资料库扫描一致：开启精确解析选项读取时长。
            let asset = AVURLAsset(
                url: track.url,
                options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
            )
            guard let loadedDuration = try? await asset.load(.duration) else { return }
            guard self.currentTrack?.id == track.id else { return }
            let seconds = loadedDuration.seconds
            guard seconds.isFinite, seconds > 0 else { return }
            self.duration = seconds
            self.updateNowPlaying()
        }
    }

    private func loadArtwork(for track: Track) {
        Task {
            let image = await AudioMetadataLoader.artwork(for: track)
            guard self.currentTrack?.id == track.id else { return }
            self.artwork = image
            // 主色提取与背景模糊渲染并行，都在后台：切歌瞬间不再与转场动画抢占主线程。
            async let palette = Task.detached(priority: .userInitiated) {
                image.map(ArtworkPaletteExtractor.palette(from:))
            }.value
            async let backdrop = Task.detached(priority: .userInitiated) {
                image.flatMap(BlurredBackdropRenderer.image(from:))
            }.value
            guard self.currentTrack?.id == track.id else { return }
            self.artworkPalette = await palette
            self.backdropImage = await backdrop
            // 光斑烘焙依赖调色板颜色，拿到主色后立刻在后台烘焙（毫秒级）。
            let orbColors = self.artworkPalette ?? .fallback
            async let orbA = Task.detached(priority: .utility) {
                BlurredBackdropRenderer.blurredOrb(color: orbColors.primary, diameter: 620, blurRadius: 160)
            }.value
            async let orbB = Task.detached(priority: .utility) {
                BlurredBackdropRenderer.blurredOrb(color: orbColors.secondary, diameter: 460, blurRadius: 150)
            }.value
            self.orbPrimaryImage = await orbA?.image
            self.orbSecondaryImage = await orbB?.image
            self.refreshDockIcon()
            self.updateNowPlaying()
        }
    }

    func refreshDockIcon() {
        DockArtworkController.shared.update(artwork: artwork, isPlaying: isPlaying)
    }

    private var rememberPlaybackState: Bool {
        if defaults.object(forKey: Self.rememberPlaybackKey) == nil {
            return true
        }
        return defaults.bool(forKey: Self.rememberPlaybackKey)
    }

    /// `force` writes the full record (track, queue IDs, index, time) and is
    /// reserved for real state changes: track load, seek, pause, queue edits.
    /// The periodic 5s tick only refreshes the elapsed time, so it never walks
    /// the queue to rebuild the ID list.
    private func persistPlaybackState(force: Bool) {
        guard rememberPlaybackState, let currentTrack else { return }

        let wholeSecond = Int(currentTime)
        if !force {
            guard wholeSecond >= 5, wholeSecond - lastPersistedSecond >= 5 else { return }
        }

        lastPersistedSecond = wholeSecond
        defaults.set(currentTime, forKey: PlaybackStateKeys.currentTime)

        guard force else { return }

        defaults.set(currentTrack.id.uuidString, forKey: PlaybackStateKeys.trackID)
        defaults.set(queue.map { $0.id.uuidString }, forKey: PlaybackStateKeys.queueIDs)
        defaults.set(currentIndex ?? 0, forKey: PlaybackStateKeys.currentIndex)
        defaults.set(playbackMode.rawValue, forKey: PlaybackStateKeys.playbackMode)
    }

    var currentLyricText: String? {
        lyricPassage(maxLines: 1).first
    }

    func lyricPassage(maxLines: Int = 4) -> [String] {
        guard !lyricLines.isEmpty, maxLines > 0 else { return [] }

        var index = 0
        for (lineIndex, line) in lyricLines.enumerated() {
            guard let time = line.time else { continue }
            if time <= currentTime + 0.12 {
                index = lineIndex
            } else {
                break
            }
        }

        let start = min(index, max(0, lyricLines.count - maxLines))
        return lyricLines[start..<min(lyricLines.count, start + maxLines)]
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 歌词在切歌的同一轮状态更新中尽量同步落位（启动预热/上一首时已提前
    /// 解析进缓存），未命中才异步读取——避免先闪“正在等待歌词”再换正文。
    private func prepareLyrics(for track: Track) {
        restoreLyricOffset(for: track)

        if let immediate = LyricsCache.shared.immediateResult(for: track.id) {
            lyricLines = immediate.lines
            lyricsResolved = true
        } else {
            let loading = LyricsCache.shared.load(track: track)
            Task { @MainActor [weak self] in
                let lines = await loading.value
                guard let self, self.currentTrack?.id == track.id else { return }
                self.lyricLines = lines ?? []
                self.lyricsResolved = true
            }
        }

        prefetchUpcomingLyrics()
    }

    /// 顺序播放时队列接下来的两首最可能被切到，提前发起读取；
    /// 随机模式的下一首不可预测，由启动时的全库预热兜底。
    private func prefetchUpcomingLyrics() {
        guard let currentIndex, !queue.isEmpty else { return }
        let picks = (1...2).compactMap { step -> Track? in
            let index = currentIndex + step
            return queue.indices.contains(index) ? queue[index] : nil
        }
        if !picks.isEmpty {
            LyricsCache.shared.preloadNext(picks)
        }
    }

    // MARK: - 歌词进度偏移

    /// 歌词偏移按歌曲存放在 UserDefaults，键为 track UUID；不改动 library.json 格式。
    private static let lyricOffsetsKey = "HarmonyPlayer.lyricOffsets"
    /// 偏移上下限：±10 秒足够覆盖常见的歌词整体错位。
    private static let lyricOffsetLimit: Double = 10

    private var lyricOffsetsStore: [String: Double] {
        get {
            defaults.dictionary(forKey: Self.lyricOffsetsKey) as? [String: Double] ?? [:]
        }
        set {
            defaults.set(newValue, forKey: Self.lyricOffsetsKey)
        }
    }

    /// 以 0.5 秒步进微调歌词时间轴：正数把歌词往后挪（延后显示）。
    func adjustLyricOffset(_ delta: Double) {
        setLyricOffset(lyricOffset + delta)
    }

    /// 清除当前歌曲的歌词偏移。
    func resetLyricOffset() {
        setLyricOffset(0)
    }

    private func setLyricOffset(_ value: Double) {
        let clamped = min(max(value, -Self.lyricOffsetLimit), Self.lyricOffsetLimit)
        lyricOffset = clamped
        guard let id = currentTrack?.id else { return }
        var store = lyricOffsetsStore
        if abs(clamped) < 0.001 {
            store.removeValue(forKey: id.uuidString)
        } else {
            store[id.uuidString] = clamped
        }
        lyricOffsetsStore = store
    }

    private func restoreLyricOffset(for track: Track) {
        lyricOffset = lyricOffsetsStore[track.id.uuidString] ?? 0
    }

    private func move(by offset: Int, manual: Bool) {
        guard !queue.isEmpty else { return }

        if isShuffle, queue.count > 1 {
            let alternatives = queue.indices.filter { $0 != currentIndex }
            guard let target = alternatives.randomElement() else { return }
            currentIndex = target
            routeSwitch(to: queue[target])
            // 随机切到一首后，把剩余未播放的重新洗牌，保证列表里顺序会变。
            shuffleRemainingQueue()
            return
        }

        let current = currentIndex ?? 0
        var target = current + offset

        if target >= queue.count {
            target = 0
        } else if target < 0 {
            target = queue.count - 1
        }

        if !manual, repeatMode == .off, offset > 0, target == 0 {
            player.seek(to: .zero)
            currentTime = 0
            pause()
            return
        }

        currentIndex = target
        // 手动切歌（点上一首/下一首）且正在播放、crossfade 开时走淡入淡出；
        // 自动连播兜底进入这里时旧曲已停（isPlaying=false），routeSwitch 自动退化为 cut。
        routeSwitch(to: queue[target])
    }

    private func handleTrackFinished() {
        switch repeatMode {
        case .one:
            seek(to: 0)
            resume()
        case .all:
            move(by: 1, manual: false)
        case .off:
            move(by: 1, manual: false)
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayback() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayTitle,
            MPMediaItemPropertyArtist: track.displayArtist,
            MPMediaItemPropertyAlbumTitle: track.displayAlbum,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private func saveVolume() {
        defaults.set(volume, forKey: volumeKey)
    }
}

private enum PlaybackStateKeys {
    static let trackID = "ManyuMusic.playback.trackID"
    static let queueIDs = "ManyuMusic.playback.queueIDs"
    static let currentIndex = "ManyuMusic.playback.currentIndex"
    static let currentTime = "ManyuMusic.playback.currentTime"
    static let playbackMode = "ManyuMusic.playback.mode"
}

/// 预渲染播放页背景的模糊封面：换歌时在后台算一次，
/// 转场首帧直接贴图，避免全屏实时 .blur 层的光栅化开销（进出播放页各一次）。
/// 全部走 CPU（vImage / CGContext）：CoreImage 存在进程级 IOSurface 表面池，
/// 实测每首歌渲染后滞留约 1-3MB 纹理且 clearCaches/一次性 context 均无法
/// 释放，50 首歌即 120MB+ 不归还；CPU 路径零驻留（探针实测 30 轮还回内存）。
enum BlurredBackdropRenderer {
    static func image(from artwork: NSImage) -> NSImage? {
        guard let cgSource = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        // 先降采样到最长边 640px：模糊结果与分辨率无关，控制 CPU 耗时在几毫秒。
        let maxDimension: CGFloat = 640
        let longest = max(cgSource.width, cgSource.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / CGFloat(longest))
        let w = max(1, Int(CGFloat(cgSource.width) * scale))
        let h = max(1, Int(CGFloat(cgSource.height) * scale))
        guard let downCtx = Self.makeContext(width: w, height: h) else { return nil }
        downCtx.interpolationQuality = .high
        downCtx.draw(cgSource, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let downImage = downCtx.makeImage() else { return nil }

        // 成品图会被拉伸铺满全屏（按 1600pt 宽估算）：SwiftUI 里 72pt 的模糊
        // 折算到源图上约为 72 ÷ 放大倍数，clamp 防止极端比例下过锐或过糊。
        let upscale = max(1, 1600 / max(CGFloat(w), 1))
        let sigma = min(64, max(8, 72 / upscale))
        // 三通盒式模糊 ≈ 高斯模糊，盒半径 ≈ σ × 1.1。
        guard let blurred = Self.cpuBlur(downImage, radius: Int((sigma * 1.1).rounded())) else {
            return nil
        }
        return NSImage(cgImage: blurred, size: NSSize(width: w, height: h))
    }

    /// 预烘焙光斑：把「纯色圆 + 大半径实时模糊」渲染成一张图。
    /// 高斯模糊后的圆盘就是径向 alpha 衰减——直接用 CG 径向渐变绘制，
    /// 观感与原来的 Circle().blur 一致，且不经过任何模糊计算。
    /// - Parameters:
    ///   - color: 光斑颜色
    ///   - diameter: 光斑显示直径（pt）
    ///   - blurRadius: 原实时模糊半径（pt）
    /// - Returns: 图片及其显示尺寸（含模糊外溢余量）
    static func blurredOrb(color: NSColor, diameter: CGFloat, blurRadius: CGFloat) -> (image: NSImage, displaySize: CGFloat)? {
        let reach = blurRadius * 1.25
        let displaySize = diameter + reach * 2
        // 1/4 分辨率烘焙：光斑本就是模糊团，低分辨率放大后无视觉差。
        let quarterScale: CGFloat = 0.25
        let canvas = displaySize * quarterScale
        let coreFraction = (diameter * quarterScale / 2) / (canvas / 2)
        let image = NSImage(size: NSSize(width: canvas, height: canvas))
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext,
              let rgb = color.usingColorSpace(.deviceRGB)
        else { return nil }
        let core = coreFraction
        let spread = 1 - core
        let components: [CGFloat] = [
            rgb.redComponent, rgb.greenComponent, rgb.blueComponent, 1,
            rgb.redComponent, rgb.greenComponent, rgb.blueComponent, 1,
            rgb.redComponent, rgb.greenComponent, rgb.blueComponent, 0.55,
            rgb.redComponent, rgb.greenComponent, rgb.blueComponent, 0.18,
            rgb.redComponent, rgb.greenComponent, rgb.blueComponent, 0,
        ]
        let locations: [CGFloat] = [0, core, core + spread * 0.45, core + spread * 0.78, 1]
        guard let gradient = CGGradient(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            colorComponents: components,
            locations: locations,
            count: locations.count
        ) else { return nil }
        ctx.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: canvas / 2, y: canvas / 2), startRadius: 0,
            endCenter: CGPoint(x: canvas / 2, y: canvas / 2), endRadius: canvas / 2,
            options: []
        )
        return (image, displaySize)
    }

    // MARK: - CPU 渲染工具

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// 三通盒式模糊（Accelerate/vImage），结果为 malloc 支持的 CGImage，
    /// 中间缓冲全部立即释放、不涉及任何 GPU 表面池。
    private static func cpuBlur(_ source: CGImage, radius: Int) -> CGImage? {
        let width = source.width, height = source.height
        let bytesPerRow = width * 4
        guard let srcCtx = makeContext(width: width, height: height) else { return nil }
        srcCtx.interpolationQuality = .none
        srcCtx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let baseData = srcCtx.data else { return nil }

        let tmpData = malloc(bytesPerRow * height)!
        defer { free(tmpData) }
        var a = vImage_Buffer(data: baseData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
        var b = vImage_Buffer(data: tmpData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
        let kernel = UInt32(max(3, radius) | 1)
        for _ in 0..<3 {
            vImageBoxConvolve_ARGB8888(&a, &b, nil, 0, 0, kernel, kernel, nil, vImage_Flags(kvImageEdgeExtend))
            let t = a; a = b; b = t
        }
        // 奇数次交换后结果在 b（tmpData）里——拷回 ctx 缓冲出图。
        guard let outCtx = makeContext(width: width, height: height), let outData = outCtx.data else { return nil }
        if a.data != baseData {
            memcpy(outData, tmpData, bytesPerRow * height)
        } else {
            memcpy(outData, baseData, bytesPerRow * height)
        }
        return outCtx.makeImage()
    }
}
