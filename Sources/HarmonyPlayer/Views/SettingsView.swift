import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore

    @AppStorage(AppIconStyle.storageKey) private var appIconStyleRaw = AppIconStyle.albumArtwork.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TabView {
            appearanceSettings
                .tabItem {
                    Label("外观", systemImage: "paintpalette")
                }

            playbackSettings
                .tabItem {
                    Label("播放", systemImage: "play.circle")
                }

            librarySettings
                .tabItem {
                    Label("资料库", systemImage: "music.note.list")
                }
        }
        .padding(22)
        .frame(width: 540, height: 360)
    }

    private var appearanceSettings: some View {
        Form {
            Section("主题") {
                Picker("应用外观", selection: $theme.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Label(appearance.title, systemImage: appearance.systemImage)
                            .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)

                Text("白天使用冰蓝白色调，夜间使用深海军蓝。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("应用图标") {
                HStack(spacing: 18) {
                    ForEach(AppIconStyle.allCases) { style in
                        Button {
                            appIconStyleRaw = style.rawValue
                            DockArtworkController.shared.refreshSetting()
                            player.refreshDockIcon()
                            AppIconStyleManager.apply()
                        } label: {
                            VStack(spacing: 7) {
                                if style == .albumArtwork, let artwork = player.artwork {
                                    Image(nsImage: artwork)
                                        .resizable()
                                        .interpolation(.high)
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 58, height: 58)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                } else if let image = AppIconStyleManager.image(
                                    for: style,
                                    colorScheme: colorScheme
                                ) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .interpolation(.high)
                                        .frame(width: 58, height: 58)
                                }

                                Text(style.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(
                                        appIconStyleRaw == style.rawValue
                                            ? Color.hpAccent
                                            : Color.primary.opacity(0.62)
                                    )
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(
                                appIconStyleRaw == style.rawValue
                                    ? Color.hpAccent.opacity(0.10)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)

                Text("自动模式跟随白天/夜间主题；专辑图模式会在播放时使用当前封面，没有封面时回退到自动图标。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var playbackSettings: some View {
        Form {
            Section("播放器") {
                LabeledContent("当前输出") {
                    Text(player.isPlaying ? "正在播放" : "已暂停")
                        .foregroundStyle(player.isPlaying ? Color.hpAccent : .secondary)
                }

                LabeledContent("睡眠定时") {
                    if let remaining = player.sleepTimerRemaining {
                        Text("剩余 \(Int(ceil(remaining / 60))) 分钟")
                    } else {
                        Text("未开启")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var librarySettings: some View {
        Form {
            Section("本地资料库") {
                LabeledContent("歌曲数量", value: "\(library.tracks.count)")
                LabeledContent("专辑数量", value: "\(Set(library.tracks.map(\.displayAlbum)).count)")
                LabeledContent("艺术家数量", value: "\(Set(library.tracks.map(\.displayArtist)).count)")

                Button {
                    library.rescanLibrary()
                } label: {
                    Label("重新扫描资料库", systemImage: "arrow.clockwise")
                }
                .disabled(library.isImporting)
            }
        }
        .formStyle(.grouped)
    }
}
