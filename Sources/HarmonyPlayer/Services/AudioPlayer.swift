import AppKit
import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkPalette: ArtworkPalette?
    @Published private(set) var lyricLines: [LyricLine] = []
    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var sleepTimerEnd: Date?
    @Published private(set) var sleepTimerRemaining: TimeInterval?
    @Published var volume: Double = 0.78 {
        didSet {
            player.volume = Float(volume)
            saveVolume()
        }
    }
    @Published var isShuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var playbackError: String?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var itemStatusObservation: NSKeyValueObservation?
    private var sleepTimerTask: Task<Void, Never>?
    private let volumeKey = "HarmonyPlayer.playbackVolume"

    init() {
        let savedVolume = UserDefaults.standard.object(forKey: volumeKey) as? Double
        volume = savedVolume ?? 0.78
        player.volume = Float(volume)
        player.automaticallyWaitsToMinimizeStalling = false
        configurePlayerObservation()
        configureRemoteCommands()
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

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        let upperBound = duration > 0 ? duration : max(0, seconds)
        let target = min(max(0, seconds), upperBound)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = target
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
    }

    func addToQueue(_ track: Track) {
        queue.append(track)
        if currentIndex == nil {
            currentIndex = queue.indices.last
        }
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
    }

    func clearQueue() {
        guard let currentTrack else {
            queue.removeAll()
            currentIndex = nil
            return
        }
        queue = [currentTrack]
        currentIndex = 0
    }

    func moveQueue(from offsets: IndexSet, to destination: Int) {
        guard let currentID = currentTrack?.id else { return }
        queue.move(fromOffsets: offsets, toOffset: destination)
        currentIndex = queue.firstIndex(where: { $0.id == currentID })
    }

    func setSleepTimer(minutes: Int?) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil

        guard let minutes else {
            sleepTimerEnd = nil
            sleepTimerRemaining = nil
            return
        }

        let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerEnd = endDate
        sleepTimerRemaining = endDate.timeIntervalSinceNow

        sleepTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let end = self.sleepTimerEnd else { return }
                let remaining = end.timeIntervalSinceNow

                if remaining <= 0 {
                    self.pause()
                    self.sleepTimerEnd = nil
                    self.sleepTimerRemaining = nil
                    self.sleepTimerTask = nil
                    return
                }

                self.sleepTimerRemaining = remaining
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
                self.currentTime = seconds

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
        Task {
            let lyrics = await AudioMetadataLoader.lyrics(for: track)
            guard self.currentTrack?.id == track.id else { return }
            self.lyricLines = LyricsParser.parse(lyrics)
        }
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
