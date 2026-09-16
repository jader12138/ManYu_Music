import SwiftUI

struct HomeView: View {
    let tracks: [Track]
    let albums: [AlbumGroup]
    let recentTracks: [Track]
    let favoriteTracks: [Track]
    let openAlbum: (AlbumGroup) -> Void
    let openNowPlaying: () -> Void

    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @State private var loadedFeaturedLyrics: [String] = []
    @State private var displayedRecentTracks: [Track] = []
    @State private var refreshRecentTracksOnAppear = true
    @State private var featuredPalette: ArtworkPalette?
    @State private var launchRecommendationID: UUID?
    @AppStorage(RecommendationSettings.frequencyKey)
    private var recommendationFrequencyRaw = RecommendationFrequency.daily.rawValue
    @AppStorage(RecommendationSettings.independentKey)
    private var recommendationIsIndependent = true
    @AppStorage(RecommendationSettings.trackIDKey)
    private var recommendationTrackID = ""
    @AppStorage(RecommendationSettings.dayKey)
    private var recommendationDay = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                hero
                quickActions

                if !displayedRecentTracks.isEmpty {
                    mediaSection(title: "最近播放", subtitle: "继续上次的音乐旅程") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(displayedRecentTracks.prefix(10)) { track in
                                    HomeTrackCard(track: track) {
                                        play(track, in: displayedRecentTracks)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if !albums.isEmpty {
                    mediaSection(title: "最近添加", subtitle: "资料库里的新声音") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 18) {
                                ForEach(albums.prefix(10)) { album in
                                    HomeAlbumCard(album: album) {
                                        openAlbum(album)
                                    } play: {
                                        guard let first = album.tracks.first else { return }
                                        play(first, in: album.tracks)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if !favoriteTracks.isEmpty {
                    mediaSection(title: "我喜欢的音乐", subtitle: "\(favoriteTracks.count) 首收藏") {
                        VStack(spacing: 2) {
                            ForEach(favoriteTracks.prefix(6)) { track in
                                TrackRow(
                                    track: track,
                                    isCurrent: player.currentTrack?.id == track.id,
                                    isPlaying: player.isPlaying,
                                    isFavorite: true,
                                    play: { play(track, in: favoriteTracks) },
                                    toggleFavorite: { library.toggleFavorite(track) },
                                    reveal: { library.reveal(track) },
                                    remove: { library.remove(track) }
                                )
                            }
                        }
                    }
                }

                if tracks.isEmpty {
                    EmptyLibraryView(
                        isSearching: false,
                        isDropTargeted: false
                    )
                    .frame(minHeight: 280)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .onAppear {
            if refreshRecentTracksOnAppear {
                displayedRecentTracks = recentTracks
                refreshRecentTracksOnAppear = false
            } else if displayedRecentTracks.isEmpty {
                displayedRecentTracks = recentTracks
            }
        }
        .onDisappear {
            refreshRecentTracksOnAppear = true
        }
        .onChange(of: recentTracks.map(\.id)) { _, newIDs in
            if displayedRecentTracks.isEmpty {
                displayedRecentTracks = newIDs.compactMap { id in
                    recentTracks.first(where: { $0.id == id })
                }
            }
        }
        .task(id: recommendationTaskKey) {
            ensureRecommendation()
        }
        .onChange(of: recommendationFrequencyRaw) { _, _ in
            launchRecommendationID = nil
            recommendationDay = ""
            ensureRecommendation()
        }
        .onChange(of: recommendationIsIndependent) { _, _ in
            ensureRecommendation()
        }
        .task(id: featuredTrack?.id) {
            guard let track = featuredTrack else {
                loadedFeaturedLyrics = []
                featuredPalette = nil
                return
            }

            if player.currentTrack?.id == track.id, !player.lyricLines.isEmpty {
                loadedFeaturedLyrics = []
                return
            }

            let rawLyrics = await AudioMetadataLoader.lyrics(for: track)
            guard !Task.isCancelled else { return }
            loadedFeaturedLyrics = LyricsParser.parse(rawLyrics).map(\.text)

            // The player already averaged the cover for the current track: reuse its
            // palette instead of decoding and extracting the same artwork again.
            if player.currentTrack?.id == track.id, let palette = player.artworkPalette {
                featuredPalette = palette
                return
            }

            let palette = await Task.detached(priority: .utility) { () -> ArtworkPalette? in
                guard let artwork = await AudioMetadataLoader.artwork(for: track) else { return nil }
                return ArtworkPaletteExtractor.palette(from: artwork)
            }.value

            // A superseded task must never publish a palette for an old track.
            guard !Task.isCancelled else { return }
            featuredPalette = palette
        }
    }

    private var hero: some View {
        HStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text(greeting)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)

                Text(heroSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.58))

                lyricExcerpt
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let track = featuredTrack {
                ZStack {
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 27, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 27, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.45), .white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .frame(width: 206, height: 206)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)

                    ZStack(alignment: .bottomTrailing) {
                        Button {
                            openFeaturedPlayer(track)
                        } label: {
                            LazyArtworkView(track: track, size: 184, cornerRadius: 20)
                        }
                        .buttonStyle(.plain)
                        .help("进入播放界面")

                        Button {
                            toggleFeaturedPlayback(track)
                        } label: {
                            PlaybackStateBadge(
                                isPlaying: player.isPlaying && player.currentTrack?.id == track.id,
                                size: 32,
                                palette: featuredPalette
                            )
                            .padding(8)
                        }
                        .buttonStyle(.plain)
                        .help(player.isPlaying && player.currentTrack?.id == track.id ? "暂停" : "播放")
                    }
                    .frame(width: 184, height: 184)
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: 206, height: 206)
                    ArtworkView(image: nil, size: 184, cornerRadius: 20)
                }
            }
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color.hpSurface.opacity(0.86), Color.hpAccent.opacity(0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.hpTextPrimary.opacity(0.07), lineWidth: 1)
        }
    }

    private var lyricExcerpt: some View {
        Text(lyricPassageText)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.hpTextPrimary.opacity(0.78))
            .lineSpacing(6)
            .lineLimit(3...4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 15)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient.hpAccentFill)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: 430, alignment: .leading)
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                if let first = tracks.first {
                    play(first, in: tracks)
                }
            } label: {
                Label("播放全部", systemImage: "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 17)
                    .frame(height: 38)
                    .foregroundStyle(.white)
                    .background(LinearGradient.hpAccentFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(tracks.isEmpty)

            Button {
                player.isShuffle = true
                if let random = tracks.randomElement() {
                    play(random, in: tracks)
                }
            } label: {
                Label("随机播放", systemImage: "shuffle")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.78))
                    .background(Color.hpTextPrimary.opacity(0.065), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(tracks.isEmpty)

            Spacer()

            Label("\(tracks.count) 首歌曲", systemImage: "music.note")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
        }
    }

    private func mediaSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                Spacer()
            }

            content()
        }
    }

    private func ensureRecommendation() {
        guard recommendationIsIndependent, !tracks.isEmpty else { return }

        let frequency = RecommendationFrequency(rawValue: recommendationFrequencyRaw) ?? .daily
        let today = Self.dayString(for: .now)
        let candidates: [Track]
        if tracks.count > 1, let currentID = player.currentTrack?.id {
            candidates = tracks.filter { $0.id != currentID }
        } else {
            candidates = tracks
        }

        switch frequency {
        case .daily:
            if !recommendationTrackID.isEmpty,
               recommendationDay == today,
               let id = UUID(uuidString: recommendationTrackID),
               tracks.contains(where: { $0.id == id }) {
                return
            }
            selectRecommendation(from: candidates, frequency: frequency, day: today)

        case .everyLaunch:
            if let launchRecommendationID,
               tracks.contains(where: { $0.id == launchRecommendationID }) {
                return
            }
            selectRecommendation(from: candidates, frequency: frequency, day: today)
        }
    }

    private func selectRecommendation(
        from candidates: [Track],
        frequency: RecommendationFrequency,
        day: String
    ) {
        guard let selected = candidates.randomElement() else { return }

        switch frequency {
        case .daily:
            recommendationTrackID = selected.id.uuidString
            recommendationDay = day
            launchRecommendationID = nil
        case .everyLaunch:
            launchRecommendationID = selected.id
        }
    }

    private static func dayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func toggleFeaturedPlayback(_ track: Track) {
        if player.currentTrack?.id == track.id {
            player.togglePlayback()
        } else {
            player.play(track, in: tracks.isEmpty ? [track] : tracks)
        }
    }

    private func openFeaturedPlayer(_ track: Track) {
        if player.currentTrack?.id != track.id {
            player.play(track, in: tracks.isEmpty ? [track] : tracks)
        }
        openNowPlaying()
    }

    private func play(_ track: Track, in list: [Track]) {
        if player.currentTrack?.id == track.id {
            player.togglePlayback()
        } else {
            player.play(track, in: list)
        }
    }

    private var featuredTrack: Track? {
        if !recommendationIsIndependent, let current = player.currentTrack {
            return current
        }

        if let launchRecommendationID,
           let track = tracks.first(where: { $0.id == launchRecommendationID }) {
            return track
        }

        if let id = UUID(uuidString: recommendationTrackID),
           let track = tracks.first(where: { $0.id == id }) {
            return track
        }

        return tracks.first
    }

    private var recommendationTaskKey: String {
        let firstID = tracks.first?.id.uuidString ?? "none"
        let lastID = tracks.last?.id.uuidString ?? "none"
        return [
            recommendationFrequencyRaw,
            recommendationIsIndependent ? "independent" : "synced",
            "\(tracks.count)",
            firstID,
            lastID
        ].joined(separator: "-")
    }

    private var lyricPassage: [String] {
        let source: [String]
        if featuredTrack?.id == player.currentTrack?.id, !player.lyricLines.isEmpty {
            source = player.lyricLines.map(\.text)
        } else if !loadedFeaturedLyrics.isEmpty {
            source = loadedFeaturedLyrics
        } else if let track = featuredTrack {
            return ["正在播放：\(track.displayTitle)"]
        } else {
            return ["让每一次播放都留在自己的音乐宇宙里"]
        }

        return curatedLyrics(from: source)
    }

    private var lyricPassageText: String {
        lyricPassage.joined(separator: "\n")
    }

    private func curatedLyrics(from source: [String]) -> [String] {
        let cleaned = source
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isCreditLine($0) }

        guard !cleaned.isEmpty else { return [] }

        let desiredCount = 4
        guard cleaned.count > desiredCount else { return Array(cleaned.prefix(4)) }

        let midpoint = cleaned.count / 2
        let start = max(0, min(midpoint - desiredCount / 2, cleaned.count - desiredCount))
        return Array(cleaned[start..<(start + desiredCount)])
    }

    private func isCreditLine(_ line: String) -> Bool {
        let value = line.lowercased()
        let creditKeywords = [
            "作词", "作曲", "编曲", "制作", "监制", "出品", "录音", "混音", "母带",
            "吉他", "贝斯", "鼓", "键盘", "钢琴", "和声", "合声", "口琴", "midi",
            "op:", "sp:", "词：", "曲：", "producer", "composer", "lyricist", "arranger"
        ]
        return creditKeywords.contains { value.contains($0) }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        let messages: [String]

        switch hour {
        case 5..<12:
            messages = [
                "早安，听一段清风",
                "晨光正好，适合戴上耳机",
                "清晨有光，音乐有风",
                "Good morning. Let the music wake gently.",
                "新的一天，从一首喜欢的歌开始"
            ]
        case 12..<18:
            messages = [
                "午后好，给世界一点留白",
                "把喧闹调低，把音乐调近",
                "阳光正好，适合听一首慢歌",
                "Good afternoon. Take a breath and press play.",
                "且听风吟，且行且歌"
            ]
        case 18..<23:
            messages = [
                "晚上好，让音乐替今天收尾",
                "夜色渐深，适合一首温柔的歌",
                "灯亮起时，让音乐陪你",
                "Good evening. Let the melody stay a little longer.",
                "今晚，把时间交给旋律"
            ]
        default:
            messages = [
                "夜深了，听点安静的吧",
                "星河入夜，音乐入心",
                "今晚的最后一首歌，选你喜欢的",
                "Good night. End the day with a gentle song.",
                "把一天的喧闹，留在最后一首旋律里"
            ]
        }

        return messages[(day + hour) % messages.count]
    }

    private var heroSubtitle: String {
        if tracks.isEmpty {
            return "先导入一些音乐，开始打造属于你的漫域"
        }
        return "你的音乐宇宙里有 \(tracks.count) 首歌曲"
    }
}

private struct HomeTrackCard: View {
    let track: Track
    let play: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: play) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    LazyArtworkView(track: track, size: 136, cornerRadius: 14)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.black.opacity(0.28))
                        .opacity(isHovering ? 1 : 0)
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(LinearGradient.hpAccentFill, in: Circle())
                        .opacity(isHovering ? 1 : 0)
                }

                Text(track.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.92))
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                    .lineLimit(1)
            }
            .frame(width: 136, alignment: .leading)
            .offset(y: isHovering && !reduceMotion ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        // Card-local only: no other card or the surrounding list is re-laid out.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
    }
}

private struct HomeAlbumCard: View {
    let album: AlbumGroup
    let open: () -> Void
    let play: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                if let track = album.artworkTrack {
                    LazyArtworkView(track: track, size: 146, cornerRadius: 14)
                } else {
                    ArtworkView(image: nil, size: 146, cornerRadius: 14)
                }

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.black.opacity(0.27))
                    .opacity(isHovering ? 1 : 0)

                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(LinearGradient.hpAccentFill, in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
            }
            .frame(width: 146, height: 146)
            .onTapGesture(perform: open)

            Text(album.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.92))
                .lineLimit(1)
            Text(album.artist)
                .font(.system(size: 9))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                .lineLimit(1)
        }
        .frame(width: 146, alignment: .leading)
        .offset(y: isHovering && !reduceMotion ? -2 : 0)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
    }
}
