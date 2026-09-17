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
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var sleepTimerEnd: Date?
    @Published var volume: Double = 0.78 {
        didSet {
            player.volume = Float(volume)
            saveVolume()
        }
    }
    @Published var isShuffle = false
    @Published var repeatMode: RepeatMode = .off
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

    private let player = AVPlayer()
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

    init() {
        let savedVolume = UserDefaults.standard.object(forKey: volumeKey) as? Double
        volume = savedVolume ?? 0.78
        player.volume = Float(volume)
        player.automaticallyWaitsToMinimizeStalling = false
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
        didAttemptPlaybackRestore = true

        guard rememberPlaybackState, currentTrack == nil else { return }

        let defaults = UserDefaults.standard
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

        let savedTime = defaults.double(forKey: PlaybackStateKeys.currentTime)
        currentTime = max(0, min(savedTime, track.duration > 0 ? track.duration : savedTime))

        let item = AVPlayerItem(url: track.url)
        player.replaceCurrentItem(with: item)
        player.volume = Float(volume)
        player.seek(
            to: CMTime(seconds: currentTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )

        observeStatus(of: item)
        refreshDuration(for: track)
        loadArtwork(for: track)
        loadLyrics(for: track)
        updateNowPlaying()
    }

    func clearRememberedPlaybackState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: PlaybackStateKeys.trackID)
        defaults.removeObject(forKey: PlaybackStateKeys.queueIDs)
        defaults.removeObject(forKey: PlaybackStateKeys.currentIndex)
        defaults.removeObject(forKey: PlaybackStateKeys.currentTime)
        lastPersistedSecond = -1
    }

    func play(_ track: Track, in tracks: [Track]) {
        let playableQueue = tracks.isEmpty ? [track] : tracks
        queue = playableQueue
        currentIndex = playableQueue.firstIndex(where: { $0.id == track.id }) ?? 0

        if currentTrack?.id == track.id, player.currentItem != nil {
            resume()
            return
        }

        load(track)
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

    /// 进行中的 seek。AVPlayer 落位前，0.25s 观察器仍会回调旧位置；
    /// 若放行，时钟会在目标值与旧位置之间乒乓（歌词行来回跳、进度条
    /// 锚点反复重同步）。seek 期间屏蔽观察器写钟，落位后由完成回调
    /// 写入一次真实位置。
    private var seekInFlight = false

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
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
        load(queue[index])
    }

    func playNext(_ track: Track) {
        let insertionIndex = min((currentIndex ?? -1) + 1, queue.count)
        queue.insert(track, at: insertionIndex)
        if let currentIndex, insertionIndex <= currentIndex {
            self.currentIndex = currentIndex + 1
        }
        persistPlaybackState(force: true)
    }

    func addToQueue(_ track: Track) {
        queue.append(track)
        if currentIndex == nil {
            currentIndex = queue.indices.last
        }
        persistPlaybackState(force: true)
    }

    func removeFromQueue(at offsets: IndexSet) {
        guard !queue.isEmpty else { return }
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

    private func load(_ track: Track) {
        guard FileManager.default.fileExists(atPath: track.url.path) else {
            playbackError = "找不到文件：\(track.url.lastPathComponent)"
            pause()
            return
        }

        currentTrack = track
        currentTime = 0
        duration = track.duration
        lyricLines = []

        // Keep the previous artwork and Dock icon visible until the next
        // track's artwork has loaded. This removes the one-frame Dock flicker.
        let item = AVPlayerItem(url: track.url)
        // 本地文件按需读取，无需长前向缓冲：限制解码缓冲上限，
        // 避免播放器为每首曲目驻留过多解码数据。
        item.preferredForwardBufferDuration = 45
        player.replaceCurrentItem(with: item)
        player.volume = Float(volume)
        player.play()

        observeStatus(of: item)
        refreshDuration(for: track)
        loadArtwork(for: track)
        loadLyrics(for: track)
        persistPlaybackState(force: true)
        updateNowPlaying()
        scheduleMemoryRelease()
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
        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isPlaying = status == .playing
                self.refreshDockIcon()
                self.updateNowPlaying()
            }
            .store(in: &cancellables)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                // seek 落位前观察器回报的仍是旧位置，直接丢弃。
                if self.seekInFlight { return }
                self.currentTime = seconds
                self.persistPlaybackState(force: false)

                // 可播流比元数据时长长（下载源 FLAC 常见的头部少写总采样数）：
                // 越过声明终点后用真实播放位置实时撑长总时长，进度条与听感
                // 保持重合，直到 AVPlayer 在真实流末尾发出结束通知再切歌。
                if self.duration > 0, self.player.rate > 0, seconds > self.duration {
                    self.duration = seconds
                }

                if self.duration <= 0,
                   let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite,
                   itemDuration > 0 {
                    self.duration = itemDuration
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self else { return }
                guard notification.object as? AVPlayerItem === self.player.currentItem else { return }
                self.handleTrackFinished()
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
        let defaults = UserDefaults.standard
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
        let defaults = UserDefaults.standard
        defaults.set(currentTime, forKey: PlaybackStateKeys.currentTime)

        guard force else { return }

        defaults.set(currentTrack.id.uuidString, forKey: PlaybackStateKeys.trackID)
        defaults.set(queue.map { $0.id.uuidString }, forKey: PlaybackStateKeys.queueIDs)
        defaults.set(currentIndex ?? 0, forKey: PlaybackStateKeys.currentIndex)
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

    private func loadLyrics(for track: Track) {
        restoreLyricOffset(for: track)
        Task {
            let lyrics = await AudioMetadataLoader.lyrics(for: track)
            guard self.currentTrack?.id == track.id else { return }
            self.lyricLines = LyricsParser.parse(lyrics)
        }
    }

    // MARK: - 歌词进度偏移

    /// 歌词偏移按歌曲存放在 UserDefaults，键为 track UUID；不改动 library.json 格式。
    private static let lyricOffsetsKey = "HarmonyPlayer.lyricOffsets"
    /// 偏移上下限：±10 秒足够覆盖常见的歌词整体错位。
    private static let lyricOffsetLimit: Double = 10

    private var lyricOffsetsStore: [String: Double] {
        get {
            UserDefaults.standard.dictionary(forKey: Self.lyricOffsetsKey) as? [String: Double] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.lyricOffsetsKey)
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
            load(queue[target])
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
        load(queue[target])
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
        UserDefaults.standard.set(volume, forKey: volumeKey)
    }
}

private enum PlaybackStateKeys {
    static let trackID = "ManyuMusic.playback.trackID"
    static let queueIDs = "ManyuMusic.playback.queueIDs"
    static let currentIndex = "ManyuMusic.playback.currentIndex"
    static let currentTime = "ManyuMusic.playback.currentTime"
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
