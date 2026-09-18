import SwiftUI
import AppKit

/// 固定列宽用 width，nil 时退化为占满剩余空间（专辑/艺术家详情页的弹性布局）。
private struct ColumnFrame: ViewModifier {
    let width: CGFloat?

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width, alignment: .leading)
        } else {
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TrackListView: View {
    let tracks: [Track]
    var showsHeader = true
    /// 当前列排序依据；nil 表示未点过列头，保持原始顺序。
    /// 排序本身由宿主页完成（保证展示顺序与播放队列一致），这里只负责指示与回调。
    var sortColumn: TrackSortOrder?
    var sortAscending = true
    /// 点击列头回调（升/降序切换逻辑由宿主页处理）。
    var onSortTap: ((TrackSortOrder) -> Void)?
    /// 自定义行移除动作（队列选歌页用于"从队列移除"）；nil 时走资料库移除。
    var onRemoveTrack: ((Track) -> Void)?
    /// 移除菜单项文案（随 onRemoveTrack 场景变化）。
    var removeTrackLabel = "从资料库移除"
    let onPlay: (Track) -> Void

    // 多选模式（内部管理）
    @State private var isSelectionMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingCreatePlaylist = false

    // 可拖拽列宽（持久化，跨页面共享）
    @AppStorage("hp.column.titleWidth") private var titleWidthValue: Double = 260
    @AppStorage("hp.column.albumWidth") private var albumWidthValue: Double = 180
    /// 当前悬停/拖拽的分隔线：1=标题|专辑，2=专辑|时长
    @State private var activeDivider: Int?
    @State private var draggingDivider: Int?
    @State private var dragStartWidth: CGFloat = 0

    private static let titleColumnMin: CGFloat = 160
    private static let albumColumnMin: CGFloat = 120
    private static let durationColumnWidth: CGFloat = 48
    private static let actionColumnWidth: CGFloat = 72

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var titleWidth: CGFloat { CGFloat(titleWidthValue) }
    private var albumWidth: CGFloat { CGFloat(albumWidthValue) }

    private let headerHeight: CGFloat = 28
    private let headerDividerHeight: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if showsHeader {
                    header(containerWidth: geometry.size.width)
                        .frame(height: headerHeight)
                    Divider().opacity(0.18)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tracks) { track in
                            TrackRow(
                                track: track,
                                isCurrent: player.currentTrack?.id == track.id,
                                isPlaying: player.isPlaying,
                                isFavorite: library.isFavorite(track),
                                play: { onPlay(track) },
                                toggleFavorite: { library.toggleFavorite(track) },
                                reveal: { library.reveal(track) },
                                remove: { removeTrack(track) },
                                removeLabel: removeTrackLabel,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedIDs.contains(track.id),
                                selectedCount: selectedIDs.count,
                                titleWidth: titleWidth,
                                albumWidth: albumWidth,
                                onToggleSelection: {
                                    if selectedIDs.contains(track.id) {
                                        selectedIDs.remove(track.id)
                                    } else {
                                        selectedIDs.insert(track.id)
                                    }
                                },
                                onBatchAddToPlaylist: { playlistID in
                                    addSelection(to: playlistID)
                                }
                            )
                            .padding(.vertical, 1)
                            .padding(.horizontal, 10)
                        }
                    }
                }
                .frame(
                    width: geometry.size.width,
                    height: max(0, geometry.size.height - (showsHeader ? headerHeight + headerDividerHeight : 0))
                )
                .scrollContentBackground(.hidden)
                .defaultScrollAnchor(.top)
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .sheet(isPresented: $showingCreatePlaylist) {
            PlaylistNameEditor(
                title: "新建歌单",
                placeholder: "歌单名称",
                initialName: ""
            ) { name in
                let playlist = library.createPlaylist(named: name)
                addSelection(to: playlist.id)
            }
        }
    }

    private func removeTrack(_ track: Track) {
        if let onRemoveTrack {
            onRemoveTrack(track)
        } else {
            library.remove(track)
        }
    }

    /// 把当前全部选中歌曲批量加入指定歌单（库内已自动去重）。
    private func addSelection(to playlistID: UUID) {
        let toAdd = tracks.filter { selectedIDs.contains($0.id) }
        for track in toAdd {
            library.add(track, to: playlistID)
        }
    }

    /// 可点击的列头：点击列名排序；列名之间的分隔线可拖拽调整列宽。
    private func header(containerWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // 多选时行首出现 28pt 勾选框把行内容向右推，列头占位同步变为
            // 28(勾选框)+12(间距)+44(封面)=84，保证列头文字与行内容同向同幅右移并对齐。
            Color.clear.frame(width: isSelectionMode ? 84 : 44)
            Color.clear.frame(width: 12)
            sortHeaderButton("标题", column: .title, width: titleWidth)
            columnDivider(index: 1, containerWidth: containerWidth)
            sortHeaderButton("专辑", column: .album, width: albumWidth)
            columnDivider(index: 2, containerWidth: containerWidth)
            sortHeaderButton("时长", column: .duration, width: Self.durationColumnWidth, alignment: .trailing)

            // 专辑/时长固定列宽靠左，剩余空间让到右侧操作区之前
            Spacer(minLength: 12)

            // 编辑入口 / 批量操作区：与行尾「爱心+更多」区同宽（72），
            // 入口图标中心对齐下方行内爱心（区内偏移 21）；
            // 进入多选后，全选/删除/取消作为子菜单从图标右侧滑出，不挤压列宽。
            ZStack(alignment: .leading) {
                // 编辑入口（位置固定，选中态高亮；点击可退出多选）
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isSelectionMode.toggle()
                        if !isSelectionMode {
                            selectedIDs.removeAll()
                        }
                    }
                } label: {
                    Image(systemName: isSelectionMode ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(isSelectionMode ? Color.hpAccent : Color.hpTextPrimary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .frame(width: 22)
                .offset(x: 10)
                .help(isSelectionMode ? "完成" : "编辑")

                // 子菜单：向右滑出
                if isSelectionMode {
                    HStack(spacing: 0) {
                        // 全选 / 取消全选
                        Button {
                            let allIDs = Set(tracks.map(\.id))
                            if selectedIDs == allIDs && !tracks.isEmpty {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = allIDs
                            }
                        } label: {
                            Image(systemName: selectedIDs.count == tracks.count && !tracks.isEmpty ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(Color.hpAccent)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 15)
                        .help(selectedIDs.count == tracks.count && !tracks.isEmpty ? "取消全选" : "全选")

                        // 批量添加到歌单
                        Menu {
                            ForEach(library.playlists) { playlist in
                                Button(playlist.name) {
                                    addSelection(to: playlist.id)
                                }
                            }
                            Divider()
                            Button("新建歌单…") {
                                showingCreatePlaylist = true
                            }
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(selectedIDs.isEmpty ? Color.hpTextPrimary.opacity(0.25) : Color.hpTextPrimary.opacity(0.55))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 15)
                        .disabled(selectedIDs.isEmpty)
                        .help("添加所选到歌单")

                        // 批量删除
                        Button(role: .destructive) {
                            let toRemove = tracks.filter { selectedIDs.contains($0.id) }
                            for track in toRemove {
                                removeTrack(track)
                            }
                            selectedIDs.removeAll()
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isSelectionMode = false
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(selectedIDs.isEmpty ? Color.hpTextPrimary.opacity(0.25) : Color.red.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .frame(width: 15)
                        .disabled(selectedIDs.isEmpty)
                        .help("删除所选")

                        // 取消编辑
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isSelectionMode = false
                                selectedIDs.removeAll()
                            }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(Color.hpTextPrimary.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .frame(width: 15)
                        .help("取消")
                    }
                    .offset(x: 28)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(width: 72, alignment: .leading)
            // 多选时整体左移，给右侧滑出的批量操作按钮让出空间
            .offset(x: isSelectionMode ? -16 : 0)
        }
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.45)
        .padding(.horizontal, 22)
        .padding(.vertical, 7)
    }

    private func sortHeaderButton(
        _ title: String,
        column: TrackSortOrder,
        width: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        alignment: Alignment = .leading
    ) -> some View {
        let isActive = sortColumn == column
        // 固定 8pt 指示位 + 一个字宽的间距：尖角显隐不挤动列头文字。
        let label = HStack(spacing: 10) {
            Text(title)
            ZStack {
                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.62))
                    .transition(reduceMotion ? .opacity : .opacity)
            }
            .frame(width: 8)
            .opacity(isActive ? 1 : 0)
        }
        .foregroundStyle(Color.hpTextPrimary.opacity(0.36))
        return Group {
            if let width {
                label.frame(width: width, alignment: alignment)
            } else {
                label.frame(maxWidth: maxWidth, alignment: alignment)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSortTap?(column) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: sortColumn)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: sortAscending)
        .accessibilityLabel("\(title)排序")
        .accessibilityAddTraits(.isButton)
    }

    /// 列与列之间 12pt 间隙里的短灰线 + 拖拽热区；竖线只出现在列头高度内。
    private func columnDivider(index: Int, containerWidth: CGFloat) -> some View {
        Color.clear
            .frame(width: 12, height: headerHeight)
            .overlay {
                Rectangle()
                    .fill(Color.hpTextPrimary.opacity(draggingDivider == index ? 0.55 : (activeDivider == index ? 0.38 : 0.16)))
                    .frame(width: 1, height: 13)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    activeDivider = index
                    NSCursor.resizeLeftRight.push()
                } else {
                    if activeDivider == index && draggingDivider == nil {
                        activeDivider = nil
                    }
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if draggingDivider != index {
                            draggingDivider = index
                            activeDivider = index
                            dragStartWidth = index == 1 ? titleWidth : albumWidth
                        }
                        let minWidth = index == 1 ? Self.titleColumnMin : Self.albumColumnMin
                        let clamped = max(minWidth, min(maxColumnWidth(index, containerWidth: containerWidth),
                                                        dragStartWidth + value.translation.width))
                        if index == 1 {
                            titleWidthValue = Double(clamped)
                        } else {
                            albumWidthValue = Double(clamped)
                        }
                    }
                    .onEnded { _ in
                        draggingDivider = nil
                    }
            )
    }

    /// 拖拽列宽上限：保证另一列最小宽、时长列与右侧操作区不被挤出窗口。
    private func maxColumnWidth(_ index: Int, containerWidth width: CGFloat) -> CGFloat {
        let fixed: CGFloat = 44 /*左右内边距*/ + 12 * 4 /*间隙*/ + Self.durationColumnWidth + Self.actionColumnWidth
        if index == 1 {
            return max(Self.titleColumnMin, width - fixed - Self.albumColumnMin)
        }
        return max(Self.albumColumnMin, width - fixed - Self.titleColumnMin)
    }
}

struct TrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let isFavorite: Bool
    let play: () -> Void
    let toggleFavorite: () -> Void
    let reveal: () -> Void
    let remove: () -> Void
    var removeLabel = "从资料库移除"

    // 多选模式
    var isSelectionMode = false
    var isSelected = false
    var selectedCount = 0
    /// 固定列宽（由 TrackListView 列头拖拽控制）；nil 时保持弹性布局（专辑/艺术家详情页）。
    var titleWidth: CGFloat? = nil
    var albumWidth: CGFloat? = nil
    var onToggleSelection: (() -> Void)? = nil
    /// 多选时把全部选中歌曲批量加入歌单。
    var onBatchAddToPlaylist: ((UUID) -> Void)? = nil

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var playerStore: AudioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 12) {
            // 多选勾选框
            if isSelectionMode {
                Button {
                    onToggleSelection?()
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(isSelected ? Color.hpAccent : Color.hpTextPrimary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 44)
            }

            ZStack(alignment: .bottomTrailing) {
                LazyArtworkView(track: track, size: 44, cornerRadius: 9)

                if isCurrent || isHovering {
                    PlaybackStateBadge(
                        isPlaying: isCurrent && isPlaying,
                        size: 22
                    )
                    .padding(2)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(track.displayTitle)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? Color.hpAccent : Color.hpTextPrimary.opacity(0.94))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(track.url.pathExtension.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.hpAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.hpAccent.opacity(0.13), in: RoundedRectangle(cornerRadius: 3))
                    Text(track.displayArtist)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.48))
                        .lineLimit(1)
                }
            }
            .modifier(ColumnFrame(width: titleWidth))

            Text(track.displayAlbum)
                .font(.system(size: 11))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.48))
                .lineLimit(1)
                .modifier(ColumnFrame(width: albumWidth))

            Text(track.formattedDuration)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.48))
                .frame(width: 48, alignment: .trailing)

            // 固定列宽时剩余空间让到右侧；弹性列宽（详情页）时由标题列自行吸收
            if titleWidth != nil {
                Spacer(minLength: 12)
            }

            HStack(spacing: 2) {
                Button(action: toggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isFavorite ? Color.hpPink : Color.hpTextPrimary.opacity(0.38))
                        .frame(width: 28, height: 28)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isFavorite)
                }
                .buttonStyle(.plain)

                Menu {
                    rowActions
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28)
            }
            .frame(width: 72)
            // 多选时与列头选择图标一起左移，为批量操作展开按钮让位置
            .offset(x: isSelectionMode ? -16 : 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 61)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackground)
                // Only the fill fades: no row-level layout or frame animation.
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
        }
        .overlay(alignment: .leading) {
            if isCurrent {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.hpAccent)
                    .frame(width: 3, height: 28)
                    .offset(x: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection?()
            } else {
                play()
            }
        }
        .onHover { isHovering = $0 }
        .sheet(isPresented: $showingInfo) {
            TrackInfoView(track: track)
                .environmentObject(libraryStore)
        }
        .contextMenu {
            rowActions
        }
    }

    /// 行操作菜单（「⋯」菜单与右键菜单共用）：多选时「添加到歌单」作用于全部选中歌曲。
    @ViewBuilder
    private var rowActions: some View {
        if isSelectionMode {
            if libraryStore.playlists.isEmpty {
                Button("暂无歌单") { }.disabled(true)
            } else {
                Menu("添加到歌单（已选 \(selectedCount) 首）") {
                    ForEach(libraryStore.playlists) { playlist in
                        Button(playlist.name) {
                            onBatchAddToPlaylist?(playlist.id)
                        }
                    }
                }
            }
        } else {
            Button("播放", action: play)
            Button(isFavorite ? "取消收藏" : "收藏", action: toggleFavorite)
            Button("下一首播放") {
                playerStore.playNext(track)
            }
            Button("添加到播放队列") {
                playerStore.addToQueue(track)
            }

            if !libraryStore.playlists.isEmpty {
                Menu("添加到歌单") {
                    ForEach(libraryStore.playlists) { playlist in
                        Button(playlist.name) {
                            libraryStore.add(track, to: playlist.id)
                        }
                    }
                }
            }

            Button("显示歌曲信息") {
                showingInfo = true
            }

            Button("在访达中显示", action: reveal)
            Divider()
            Button(role: .destructive, action: remove) {
                Label(removeLabel, systemImage: "trash")
            }
        }
    }

    private var rowBackground: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.hpAccent.opacity(0.12))
        }
        if isCurrent {
            return AnyShapeStyle(LinearGradient.hpSelectedRow)
        }
        if isHovering {
            return AnyShapeStyle(Color.hpTextPrimary.opacity(0.045))
        }
        return AnyShapeStyle(Color.clear)
    }
}

struct AlbumGridView: View {
    let albums: [AlbumGroup]
    let onOpen: (AlbumGroup) -> Void
    let onPlay: (AlbumGroup) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 156, maximum: 178), spacing: 22, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(albums) { album in
                    AlbumCard(
                        album: album,
                        open: { onOpen(album) },
                        play: { onPlay(album) }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
    }
}

private struct AlbumCard: View {
    let album: AlbumGroup
    let open: () -> Void
    let play: () -> Void

    @EnvironmentObject private var player: AudioPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let track = album.artworkTrack {
                    LazyArtworkView(track: track, size: 156, cornerRadius: 13)
                } else {
                    ArtworkView(image: nil, size: 156, cornerRadius: 13)
                }

                if isHovering {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(.black.opacity(0.30))
                }

                if isHovering {
                    Button(action: play) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.hpNavyDeep)
                            .frame(width: 46, height: 46)
                            .background(.white, in: Circle())
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                }

                if let track = album.artworkTrack,
                   player.currentTrack?.displayAlbum == track.displayAlbum {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.hpAccent)
                                .frame(width: 8, height: 8)
                                .padding(12)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 156, height: 156)
            .scaleEffect(isHovering && !reduceMotion ? 1.018 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
            .onTapGesture(perform: open)

            Text(album.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.92))
                .lineLimit(1)

            Text(album.artist)
                .font(.system(size: 10))
                .foregroundStyle(Color.hpTextPrimary.opacity(0.45))
                .lineLimit(1)
        }
        .frame(width: 156, alignment: .leading)
        .onHover { isHovering = $0 }
    }
}

struct AlbumDetailView: View {
    let album: AlbumGroup
    let back: () -> Void
    let onPlay: (Track, [Track]) -> Void

    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                Divider().opacity(0.18)

                LazyVStack(spacing: 2) {
                    ForEach(album.tracks) { track in
                        TrackRow(
                            track: track,
                            isCurrent: player.currentTrack?.id == track.id,
                            isPlaying: player.isPlaying,
                            isFavorite: library.isFavorite(track),
                            play: { onPlay(track, album.tracks) },
                            toggleFavorite: { library.toggleFavorite(track) },
                            reveal: { library.reveal(track) },
                            remove: { library.remove(track) }
                        )
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 26) {
            if let track = album.artworkTrack {
                LazyArtworkView(track: track, size: 196, cornerRadius: 16)
            } else {
                ArtworkView(image: nil, size: 196, cornerRadius: 16)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("专辑")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.hpAccent)
                    .tracking(1.4)

                Text(album.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                    .lineLimit(2)

                Text(album.artist)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.72))

                Text("\(album.tracks.count) 首歌曲  ·  \(Track.formatTime(album.duration))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))

                HStack(spacing: 10) {
                    Button {
                        if let first = album.tracks.first {
                            onPlay(first, album.tracks)
                        }
                    } label: {
                        Label("播放专辑", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(AccentFillButtonStyle())

                    Button(action: back) {
                        Label("返回", systemImage: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.72))
                    }
                    .buttonStyle(HoverHighlightButtonStyle())
                }
            }

            Spacer()
        }
    }
}

struct ArtistGridView: View {
    let artists: [ArtistGroup]
    let onOpen: (ArtistGroup) -> Void
    let onPlay: (ArtistGroup) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 174), spacing: 20, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(artists) { artist in
                    ArtistCard(
                        artist: artist,
                        open: { onOpen(artist) },
                        play: { onPlay(artist) }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
    }
}

private struct ArtistCard: View {
    let artist: ArtistGroup
    let open: () -> Void
    let play: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 11) {
            ZStack {
                if let track = artist.artworkTrack {
                    LazyArtworkView(track: track, size: 138, cornerRadius: 69)
                } else {
                    ArtworkView(image: nil, size: 138, cornerRadius: 69)
                }

                if isHovering {
                    Circle()
                        .fill(.black.opacity(0.30))
                    Button(action: play) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(LinearGradient.hpAccentFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 138, height: 138)
            .onTapGesture(perform: open)

            VStack(spacing: 3) {
                Text(artist.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.92))
                    .lineLimit(1)
                Text("\(artist.tracks.count) 首歌曲 · \(artist.albumCount) 张专辑")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            isHovering ? Color.hpTextPrimary.opacity(0.05) : Color.clear,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .onHover { isHovering = $0 }
    }
}

struct ArtistDetailView: View {
    let artist: ArtistGroup
    let back: () -> Void
    let onPlay: (Track, [Track]) -> Void

    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                Divider().opacity(0.18)

                LazyVStack(spacing: 2) {
                    ForEach(artist.tracks) { track in
                        TrackRow(
                            track: track,
                            isCurrent: player.currentTrack?.id == track.id,
                            isPlaying: player.isPlaying,
                            isFavorite: library.isFavorite(track),
                            play: { onPlay(track, artist.tracks) },
                            toggleFavorite: { library.toggleFavorite(track) },
                            reveal: { library.reveal(track) },
                            remove: { library.remove(track) }
                        )
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
    }

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 26) {
            if let track = artist.artworkTrack {
                LazyArtworkView(track: track, size: 190, cornerRadius: 95)
            } else {
                ArtworkView(image: nil, size: 190, cornerRadius: 95)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("艺术家")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.hpAccent)
                    .tracking(1.4)

                Text(artist.name)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                    .lineLimit(2)

                Text("\(artist.tracks.count) 首歌曲 · \(artist.albumCount) 张专辑")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.42))

                HStack(spacing: 10) {
                    Button {
                        if let first = artist.tracks.first {
                            onPlay(first, artist.tracks)
                        }
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 17)
                            .frame(height: 36)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(AccentFillButtonStyle())

                    Button(action: back) {
                        Label("返回", systemImage: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .foregroundStyle(Color.hpTextPrimary.opacity(0.72))
                    }
                    .buttonStyle(HoverHighlightButtonStyle())
                }
            }

            Spacer()
        }
    }
}

struct EmptyLibraryView: View {
    let isSearching: Bool
    let isDropTargeted: Bool

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.hpAccent.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: isSearching ? "magnifyingglass" : "waveform")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.hpAccent)
            }

            VStack(spacing: 7) {
                Text(isSearching ? "没有找到相关音乐" : (isDropTargeted ? "松开即可导入" : "漫域音乐，从一首歌开始"))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.hpTextPrimary)
                Text(isSearching ? "换个关键词试试" : "支持 MP3、M4A、AAC、FLAC、WAV、AIFF 等格式")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.45))
            }

            if !isSearching {
                Button {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                } label: {
                    Label("前往设置添加音乐", systemImage: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                }
                .buttonStyle(AccentFillButtonStyle())

                Text("也可以在设置中导入文件夹")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.32))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
