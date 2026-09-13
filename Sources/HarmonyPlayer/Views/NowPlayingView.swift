import AppKit
import SwiftUI

struct NowPlayingView: View {
    let transitionNamespace: Namespace.ID

    @EnvironmentObject private var player: AudioPlayer
    @State private var scrubTime: Double?
    @State private var showingLyricsStyle = false
    @AppStorage("ManyuMusic.lyricsFontSize") private var lyricsFontSize = 18.0
    @AppStorage("ManyuMusic.lyricsFontDesign") private var lyricsFontDesignRaw = "rounded"
    @AppStorage("ManyuMusic.lyricsColor") private var lyricsColorRaw = "auto"
    @AppStorage("ManyuMusic.lyricsLineSpacing") private var lyricsLineSpacing = 0.9
    @AppStorage("ManyuMusic.lyricsVisibleLines") private var lyricsVisibleLines = 9.0

    var body: some View {
        ZStack {
            NowPlayingBackdrop()

            GeometryReader { geometry in
                let artworkSize = min(
                    400,
                    max(190, min(geometry.size.height * 0.52, geometry.size.width * 0.30))
                )
                let lyricsHeight = min(640, max(260, geometry.size.height - 70))
                let horizontalPadding = max(24, min(52, geometry.size.width * 0.045))

                VStack(spacing: 0) {
                    Spacer(minLength: 78)

                    HStack(alignment: .center, spacing: max(24, horizontalPadding * 0.85)) {
                        albumPanel(artworkSize: artworkSize)
                            .frame(maxWidth: .infinity)

                        lyricsPanel
                            .frame(maxWidth: .infinity)
                            .frame(height: lyricsHeight)
                    }
                    .padding(.horizontal, horizontalPadding)

                    Spacer(minLength: 0)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    private func albumPanel(artworkSize: CGFloat) -> some View {
        VStack(spacing: 15) {
            ArtworkView(image: player.artwork, size: artworkSize, cornerRadius: 22)
                .matchedGeometryEffect(id: "nowPlayingArtwork", in: transitionNamespace)

            VStack(spacing: 8) {
                Text(player.currentTrack?.displayTitle ?? "还未播放")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.hpTextPrimary.opacity(0.92),
                                Color.hpAccentSecondary.opacity(0.88)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)

                Text(player.currentTrack?.displayArtist ?? "选择一首歌曲开始")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.68))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if let album = player.currentTrack?.displayAlbum {
                    Text(album)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.34))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 380)

            compactPlaybackControls
                .frame(maxWidth: min(400, artworkSize + 84))
        }
    }

    private var compactPlaybackControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(Track.formatTime(scrubTime ?? player.currentTime))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                    .frame(width: 40, alignment: .trailing)

                Slider(
                    value: playbackBinding,
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { isEditing in
                        guard !isEditing, let scrubTime else { return }
                        player.seek(to: scrubTime)
                        self.scrubTime = nil
                    }
                )
                .controlSize(.small)
                .tint(Color.hpAccent)
                .disabled(player.currentTrack == nil)

                Text(player.duration > 0 ? Track.formatTime(player.duration) : "--:--")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.38))
                    .frame(width: 40, alignment: .leading)
            }

            HStack(spacing: 16) {
                IconButton(
                    systemName: "shuffle",
                    isActive: player.isShuffle,
                    help: player.isShuffle ? "关闭随机播放" : "随机播放",
                    size: 14
                ) {
                    player.isShuffle.toggle()
                }

                IconButton(systemName: "backward.fill", help: "上一首", size: 14) {
                    player.previous()
                }
                .disabled(player.queue.isEmpty)

                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(LinearGradient.hpAccentFill, in: Circle())
                        .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(player.currentTrack == nil)

                IconButton(systemName: "forward.fill", help: "下一首", size: 14) {
                    player.next()
                }
                .disabled(player.queue.isEmpty)

                IconButton(
                    systemName: player.repeatMode.systemImage,
                    isActive: player.repeatMode.isActive,
                    help: repeatHelp,
                    size: 14
                ) {
                    player.repeatMode.advance()
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private var lyricsFontDesign: Font.Design {
        switch lyricsFontDesignRaw {
        case "default": .default
        case "serif": .serif
        case "monospaced": .monospaced
        default: .rounded
        }
    }

    private var lyricsTextColor: Color {
        if lyricsColorRaw == "auto" {
            return Color.hpTextPrimary
        }
        return Color(hex: lyricsColorRaw) ?? Color.hpTextPrimary
    }

    private var repeatHelp: String {
        switch player.repeatMode {
        case .off: "开启列表循环"
        case .all: "切换为单曲循环"
        case .one: "关闭循环"
        }
    }

    private var lyricsStylePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("歌词样式")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button("重置") {
                    lyricsFontSize = 18
                    lyricsFontDesignRaw = "rounded"
                    lyricsColorRaw = "auto"
                    lyricsLineSpacing = 0.9
                    lyricsVisibleLines = 9
                }
                .buttonStyle(.link)
            }

            HStack(spacing: 12) {
                Text("字号")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)

                Button {
                    lyricsFontSize = max(13, lyricsFontSize - 1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)

                Text("\(Int(lyricsFontSize))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(width: 28)

                Button {
                    lyricsFontSize = min(30, lyricsFontSize + 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 12) {
                Text("行距")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)

                Button {
                    lyricsLineSpacing = max(0.7, lyricsLineSpacing - 0.05)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)

                Text(String(format: "%.2f", lyricsLineSpacing))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(width: 42)

                Button {
                    lyricsLineSpacing = min(1.4, lyricsLineSpacing + 0.05)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 12) {
                Text("行数")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .leading)

                Button {
                    lyricsVisibleLines = max(5, lyricsVisibleLines - 1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)

                Text("\(Int(lyricsVisibleLines))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(width: 42)

                Button {
                    lyricsVisibleLines = min(13, lyricsVisibleLines + 1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("字体")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("字体", selection: $lyricsFontDesignRaw) {
                    Text("圆体").tag("rounded")
                    Text("默认").tag("default")
                    Text("衬线").tag("serif")
                    Text("等宽").tag("monospaced")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("颜色")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(lyricColorOptions, id: \.id) { option in
                        Button {
                            lyricsColorRaw = option.id
                        } label: {
                            Circle()
                                .fill(option.color)
                                .overlay {
                                    Circle()
                                        .stroke(
                                            lyricsColorRaw == option.id ? Color.hpAccent : Color.primary.opacity(0.14),
                                            lineWidth: lyricsColorRaw == option.id ? 2.5 : 1
                                        )
                                }
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 300)
    }

    private var lyricColorOptions: [(id: String, title: String, color: Color)] {
        [
            ("auto", "跟随主题", Color.hpTextPrimary),
            ("ffffff", "白色", .white),
            ("111827", "深色", Color(red: 0.07, green: 0.09, blue: 0.15)),
            ("5fb8ff", "天蓝", Color.hpAccent),
            ("ff5f96", "粉色", Color.hpPink),
            ("f2b84b", "金色", Color.hpGold)
        ]
    }

    private var playbackBinding: Binding<Double> {
        Binding(
            get: {
                let time = scrubTime ?? player.currentTime
                return min(time, max(player.duration, time))
            },
            set: { scrubTime = $0 }
        )
    }

    private var lyricsPanel: some View {
        VStack(spacing: 8) {
            if player.lyricLines.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("暂无可显示的歌词")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.64))
                    Text("正在等待歌曲的内嵌歌词或同名 LRC 文件。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                        .lineSpacing(5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                LyricTimelineView(
                    lines: player.lyricLines,
                    currentTime: player.currentTime,
                    seek: player.seek,
                    baseFontSize: CGFloat(lyricsFontSize),
                    fontDesign: lyricsFontDesign,
                    textColor: lyricsTextColor,
                    lineSpacingScale: CGFloat(lyricsLineSpacing),
                    visibleLineCount: Int(lyricsVisibleLines)
                )
            }

            HStack(spacing: 8) {
                Spacer()
                Text("点击歌词可跳转")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.24))

                Button {
                    showingLyricsStyle.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "textformat.size")
                        Text("Aa")
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.58))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Color.hpTextPrimary.opacity(0.055), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("歌词样式")
                .popover(isPresented: $showingLyricsStyle, arrowEdge: .trailing) {
                    lyricsStylePanel
                }
            }
            .padding(.top, 2)
            .padding(.trailing, 8)
        }
        .frame(maxWidth: 500, alignment: .topLeading)
    }
}

struct NowPlayingBackdrop: View {
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = player.artworkPalette ?? .fallback
        let primary = Color(nsColor: palette.primary)
        let secondary = Color(nsColor: palette.secondary)

        ZStack {
            if let artwork = player.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: 72)
                    .scaleEffect(1.16)
                    .opacity(colorScheme == .dark ? 0.48 : 0.30)
            }

            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        primary.opacity(0.58),
                        secondary.opacity(0.34),
                        Color.hpNavyDeep.opacity(0.97)
                    ]
                    : [
                        primary.opacity(0.27),
                        Color.white.opacity(0.78),
                        secondary.opacity(0.18)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(primary.opacity(colorScheme == .dark ? 0.28 : 0.18))
                .frame(width: 620, height: 620)
                .blur(radius: 160)
                .offset(x: 420, y: -340)

            Circle()
                .fill(secondary.opacity(colorScheme == .dark ? 0.18 : 0.13))
                .frame(width: 460, height: 460)
                .blur(radius: 150)
                .offset(x: -430, y: 320)
        }
        .animation(.easeInOut(duration: 0.65), value: player.currentTrack?.id)
    }
}

struct NowPlayingHeaderControls: View {
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: close) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.34))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .help("返回资料库")

            VStack(alignment: .leading, spacing: 1) {
                Text("正在播放")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.88))
                Text("漫域音乐")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.36))
            }
        }
    }
}
