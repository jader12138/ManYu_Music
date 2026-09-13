import SwiftUI

struct SidebarView: View {
    @Binding var destination: LibraryDestination

    @EnvironmentObject private var library: LibraryStore

    @State private var showingCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var playlistToRename: Playlist?
    @State private var renameText = ""

    private let discoverySections: [LibrarySection] = [.home]
    private let librarySections: [LibrarySection] = [.all, .albums, .artists, .folders]
    private let personalSections: [LibrarySection] = [.recent, .history, .favorites]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 18)
                .padding(.top, 19)
                .padding(.bottom, 18)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle("发现")
                    VStack(spacing: 3) {
                        ForEach(discoverySections) { section in
                            sidebarButton(for: section)
                        }
                    }

                    sectionTitle("资料库")
                        .padding(.top, 20)
                    VStack(spacing: 3) {
                        ForEach(librarySections) { section in
                            sidebarButton(for: section)
                        }
                    }

                    sectionTitle("我的音乐")
                        .padding(.top, 20)
                    VStack(spacing: 3) {
                        ForEach(personalSections) { section in
                            sidebarButton(for: section)
                        }
                        folderButton
                    }

                    HStack {
                        sectionTitle("我的歌单")
                        Spacer()
                        Button {
                            newPlaylistName = ""
                            showingCreatePlaylist = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.hpTextPrimary.opacity(0.52))
                                .frame(width: 22, height: 22)
                                .background(Color.hpTextPrimary.opacity(0.06), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("新建歌单")
                        .padding(.trailing, 12)
                    }
                    .padding(.top, 20)

                    VStack(spacing: 3) {
                        ForEach(library.playlists) { playlist in
                            playlistButton(playlist)
                        }

                        if library.playlists.isEmpty {
                            Text("还没有歌单")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.hpTextPrimary.opacity(0.30))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.bottom, 14)
                }
            }

            importCard
                .padding(14)
        }
        .frame(width: 238)
        .background {
            ZStack {
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)

                LinearGradient(
                    colors: [
                        Color.hpNavyDeep.opacity(0.96),
                        Color.hpNavy.opacity(0.90),
                        Color.hpAccentSecondary.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.hpTextPrimary.opacity(0.07))
                .frame(width: 1)
        }
        .sheet(isPresented: $showingCreatePlaylist) {
            PlaylistNameEditor(
                title: "新建歌单",
                placeholder: "歌单名称",
                initialName: ""
            ) { name in
                let playlist = library.createPlaylist(named: name)
                destination = .playlist(playlist.id)
            }
        }
        .sheet(item: $playlistToRename) { playlist in
            PlaylistNameEditor(
                title: "重命名歌单",
                placeholder: "歌单名称",
                initialName: playlist.name
            ) { name in
                library.renamePlaylist(playlist, to: name)
            }
        }
    }

    private var brand: some View {
        HStack(spacing: 12) {
            BrandMark()
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("漫域音乐")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                Text("MANYU MUSIC")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                    .tracking(1.25)
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.48))
                    .frame(width: 28, height: 28)
                    .background(Color.hpTextPrimary.opacity(0.055), in: Circle())
            }
            .buttonStyle(.plain)
            .help("设置")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.hpTextPrimary.opacity(0.34))
            .tracking(0.7)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    private var folderButton: some View {
        Button {
            library.presentImportPanel()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.hpGold)
                    .frame(width: 20)
                Text("导入文件夹")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.36))
            }
            .foregroundStyle(Color.hpTextPrimary.opacity(0.82))
            .padding(.horizontal, 12)
            .frame(height: 39)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    private func sidebarButton(for section: LibrarySection) -> some View {
        let selected = destination == .section(section)
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                destination = .section(section)
            }
        } label: {
            sidebarLabel(
                title: section.title,
                systemImage: section.systemImage,
                iconColor: iconColor(for: section),
                count: count(for: section),
                selected: selected
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    private func playlistButton(_ playlist: Playlist) -> some View {
        let selected = destination == .playlist(playlist.id)
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                destination = .playlist(playlist.id)
            }
        } label: {
            sidebarLabel(
                title: playlist.name,
                systemImage: "music.note.list",
                iconColor: .hpAccent,
                count: playlist.trackIDs.count,
                selected: selected
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .contextMenu {
            Button {
                renameText = playlist.name
                playlistToRename = playlist
            } label: {
                Label("重命名", systemImage: "pencil")
            }

            Button(role: .destructive) {
                if destination == .playlist(playlist.id) {
                    destination = .section(.home)
                }
                library.deletePlaylist(playlist)
            } label: {
                Label("删除歌单", systemImage: "trash")
            }
        }
    }

    private func sidebarLabel(
        title: String,
        systemImage: String,
        iconColor: Color,
        count: Int?,
        selected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Color.hpAccent : iconColor)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.hpTextPrimary : Color.hpTextPrimary.opacity(0.78))
                .lineLimit(1)

            Spacer()

            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? Color.hpAccent : Color.hpTextPrimary.opacity(0.36))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 39)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? LinearGradient.hpSelectedRow : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
        }
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.hpAccent)
                    .frame(width: 3, height: 19)
                    .offset(x: -1)
            }
        }
        .contentShape(Rectangle())
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(library.tracks.count)")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                Text("首音乐")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.46))
                Spacer()
                Button {
                    library.rescanLibrary()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.hpAccent)
                        .frame(width: 26, height: 26)
                        .background(Color.hpAccent.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .help("重新扫描资料库")
                .disabled(library.isImporting)
            }

            Button {
                library.presentImportPanel()
            } label: {
                HStack(spacing: 7) {
                    if library.isImporting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text(library.isImporting ? "正在导入" : "添加音乐")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .foregroundStyle(.white)
                .background(LinearGradient.hpAccentFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(library.isImporting)
        }
        .padding(14)
        .background(Color.hpTextPrimary.opacity(0.045), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.hpTextPrimary.opacity(0.075), lineWidth: 1)
        }
    }

    private func iconColor(for section: LibrarySection) -> Color {
        switch section {
        case .home: .hpAccent
        case .all: .hpAccent
        case .albums: .hpPink
        case .artists: .hpMint
        case .folders: .hpGold
        case .recent: .hpGold
        case .history: .hpViolet
        case .favorites: .hpPink
        }
    }

    private func count(for section: LibrarySection) -> Int? {
        switch section {
        case .home:
            return nil
        case .all:
            return library.tracks.count
        case .albums:
            return Set(library.tracks.map(\.displayAlbum)).count
        case .artists:
            return Set(library.tracks.map(\.displayArtist)).count
        case .folders:
            return Set(library.tracks.map { $0.url.deletingLastPathComponent().path }).count
        case .recent:
            return nil
        case .history:
            return library.history.count
        case .favorites:
            return library.favoriteIDs.count
        }
    }
}

struct PlaylistNameEditor: View {
    let title: String
    let placeholder: String
    let initialName: String
    let save: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(
        title: String,
        placeholder: String,
        initialName: String,
        save: @escaping (String) -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.initialName = initialName
        self.save = save
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))

            TextField(placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 340)
    }

    private func submit() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        save(value)
        dismiss()
    }
}

struct BrandMark: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppIconStyle.storageKey) private var appIconStyleRaw = AppIconStyle.automatic.rawValue

    var body: some View {
        Group {
            if let icon = appIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                fallbackMark
            }
        }
        .frame(width: 40, height: 40)
    }

    private var appIconImage: NSImage? {
        let style = AppIconStyle(rawValue: appIconStyleRaw) ?? .automatic
        return AppIconStyleManager.image(for: style, colorScheme: colorScheme)
    }

    private var fallbackMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.008, green: 0.18, blue: 0.62),
                            Color(red: 0.28, green: 0.08, blue: 0.72),
                            Color(red: 0.82, green: 0.18, blue: 0.90)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Path { path in
                path.move(to: CGPoint(x: 7, y: 27))
                path.addCurve(
                    to: CGPoint(x: 31, y: 8),
                    control1: CGPoint(x: 10, y: 14),
                    control2: CGPoint(x: 22, y: 5)
                )
            }
            .stroke(
                LinearGradient(
                    colors: [Color.hpAccent, .white],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 3.4, lineCap: .round)
            )

            Path { path in
                path.move(to: CGPoint(x: 13, y: 32))
                path.addCurve(
                    to: CGPoint(x: 33, y: 22),
                    control1: CGPoint(x: 18, y: 35),
                    control2: CGPoint(x: 28, y: 31)
                )
            }
            .stroke(
                LinearGradient(
                    colors: [.white, Color(red: 0.98, green: 0.28, blue: 0.92)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 3.0, lineCap: .round)
            )

            Path { path in
                path.move(to: CGPoint(x: 17, y: 14))
                path.addLine(to: CGPoint(x: 27, y: 20))
                path.addLine(to: CGPoint(x: 17, y: 27))
                path.closeSubpath()
            }
            .fill(.white.opacity(0.94))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: Color(red: 0.28, green: 0.10, blue: 0.70).opacity(0.28), radius: 8, y: 4)
    }
}
