import SwiftUI

/// 首页"最近添加"区块的显示方式：封面网格或横向文件名列表。
enum HomeRecentDisplayMode: String {
    case covers
    case list

    static let storageKey = "ManyuMusic.homeRecentDisplayMode"
}

struct HomeView: View {
    let tracks: [Track]
    let favoriteTracks: [Track]
    let transitionNamespace: Namespace.ID
    let openNowPlaying: () -> Void

    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore
    @State private var loadedFeaturedLyrics: [String] = []
    @State private var featuredPalette: ArtworkPalette?
    @AppStorage(HomeRecentDisplayMode.storageKey)
    private var recentDisplayRaw = HomeRecentDisplayMode.covers.rawValue
    @AppStorage(RecommendationSettings.frequencyKey)
    private var recommendationFrequencyRaw = RecommendationFrequency.daily.rawValue
    @AppStorage(RecommendationSettings.independentKey)
    private var recommendationIsIndependent = true
    @AppStorage(RecommendationSettings.trackIDKey)
    private var recommendationTrackID = ""
    @AppStorage(RecommendationSettings.dayKey)
    private var recommendationDay = ""

    private var recentDisplayMode: HomeRecentDisplayMode {
        get { HomeRecentDisplayMode(rawValue: recentDisplayRaw) ?? .covers }
        nonmutating set { recentDisplayRaw = newValue.rawValue }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                hero
                // 空库时快捷操作全部是禁用态，藏起来避免首次打开看到一堆无响应按钮；
                // 空库引导卡片本身已提供"添加音乐文件夹"入口。
                if !tracks.isEmpty {
                    quickActions
                }

                if !tracks.isEmpty {
                    mediaSection(
                        title: "最近添加",
                        subtitle: "资料库里的新声音",
                        trailing: { recentDisplayPicker }
                    ) {
                        switch recentDisplayMode {
                        case .covers:
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 116), spacing: 16)],
                                spacing: 20
                            ) {
                                ForEach(tracks) { track in
                                    HomeRecentCard(track: track) {
                                        play(track, in: tracks)
                                    }
                                }
                            }
                        case .list:
                            LazyVStack(spacing: 2) {
                                ForEach(tracks) { track in
                                    HomeRecentRow(track: track) {
                                        play(track, in: tracks)
                                    }
                                }
                            }
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
        .task(id: recommendationTaskKey) {
            ensureRecommendation()
        }
        .onChange(of: recommendationFrequencyRaw) { _, _ in
            library.sessionRecommendationTrackID = nil
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

            // 复用启动预热/播放共用的歌词缓存，同一首歌不重复读盘。
            let lines = await LyricsCache.shared.load(track: track).value
            guard !Task.isCancelled else { return }
            loadedFeaturedLyrics = (lines ?? []).map(\.text)

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
                                .matchedGeometryEffect(id: "nowPlayingArtwork.homeHero", in: transitionNamespace, isSource: true)
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
            quickActionButton("继续播放", systemImage: "play.circle") {
                player.resume()
            }
            .disabled(player.currentTrack == nil)

            quickActionButton("播放全部", systemImage: "play.fill") {
                if let first = tracks.first {
                    play(first, in: tracks)
                }
            }
            .disabled(tracks.isEmpty)

            quickActionButton("随机播放", systemImage: "shuffle") {
                player.setPlaybackMode(.shuffle)
                if let random = tracks.randomElement() {
                    play(random, in: tracks)
                }
            }
            .disabled(tracks.isEmpty)

            Spacer()

            Label("\(tracks.count) 首歌曲", systemImage: "music.note")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
        }
    }

    /// 首页快捷操作按钮：默认与底色融合，悬停渐显主题色高亮。
    private func quickActionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 17)
                .frame(height: 38)
                .foregroundStyle(Color.hpTextPrimary.opacity(0.88))
        }
        .buttonStyle(HoverHighlightButtonStyle(cornerRadius: 10))
    }

    private func mediaSection<Content: View, Trailing: View>(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.hpTextPrimary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                }
                Spacer()
                trailing()
            }

            content()
        }
    }

    /// "最近添加"右上角的显示方式切换：封面网格 / 文件名列表。
    private var recentDisplayPicker: some View {
        HStack(spacing: 4) {
            displayPickerButton("square.grid.2x2", mode: .covers)
            displayPickerButton("list.bullet", mode: .list)
        }
    }

    private func displayPickerButton(
        _ systemImage: String,
        mode: HomeRecentDisplayMode
    ) -> some View {
        let isSelected = recentDisplayMode == mode
        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                recentDisplayMode = mode
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color.hpTextPrimary.opacity(0.55))
                .frame(width: 26, height: 22)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(LinearGradient.hpAccentFill)
                    }
                }
        }
        .buttonStyle(HoverHighlightButtonStyle(cornerRadius: 7, hoverOpacity: 0.12))
        .accessibilityLabel(mode == .covers ? "封面显示" : "列表显示")
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
            if let sessionID = library.sessionRecommendationTrackID,
               tracks.contains(where: { $0.id == sessionID }) {
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
            library.sessionRecommendationTrackID = nil
        case .everyLaunch:
            library.sessionRecommendationTrackID = selected.id
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

        if let sessionID = library.sessionRecommendationTrackID,
           let track = tracks.first(where: { $0.id == sessionID }) {
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

/// "最近添加"封面网格的歌曲卡片：小方形封面 + 歌名 + 紧凑演唱者行。
private struct HomeRecentCard: View {
    let track: Track
    let play: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                GeometryReader { geo in
                    // 封面随网格列宽伸缩，保持方形；像素档位会自动归一化。
                    let side = max(84, geo.size.width)
                    ZStack {
                        LazyArtworkView(track: track, size: side, cornerRadius: 12)

                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.black.opacity(0.27))
                            .opacity(isHovering ? 1 : 0)

                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(LinearGradient.hpAccentFill, in: Circle())
                            .opacity(isHovering ? 1 : 0)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .onTapGesture(perform: play)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.92))
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: isHovering && !reduceMotion ? -2 : 0)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
    }
}

/// "最近添加"列表模式：横向一行的歌曲条目。
private struct HomeRecentRow: View {
    let track: Track
    let play: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                LazyArtworkView(track: track, size: 38, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.92))
                        .lineLimit(1)
                    Text(track.displayArtist)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer()

                Text(track.formattedDuration)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.hpTextPrimary.opacity(isHovering ? 0.07 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
