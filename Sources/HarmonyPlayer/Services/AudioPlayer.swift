import AppKit
import AVFoundation
import Combine
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
        player.replaceCurrentItem(with: item)
        player.volume = Float(volume)
        player.play()

        observeStatus(of: item)
        refreshDuration(for: track)
        loadArtwork(for: track)
        loadLyrics(for: track)
        persistPlaybackState(force: true)
        updateNowPlaying()
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
        Task {
            let asset = AVURLAsset(url: track.url)
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
            self.artworkPalette = image.map(ArtworkPaletteExtractor.palette(from:))
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


private enum PlaybackStateKeys {
    static let trackID = "ManyuMusic.playback.trackID"
    static let queueIDs = "ManyuMusic.playback.queueIDs"
    static let currentIndex = "ManyuMusic.playback.currentIndex"
    static let currentTime = "ManyuMusic.playback.currentTime"
}
}
