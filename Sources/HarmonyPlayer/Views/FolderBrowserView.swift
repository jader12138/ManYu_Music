import SwiftUI

struct FolderGroup: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let tracks: [Track]

    var id: String { path }
    var duration: Double { tracks.reduce(0) { $0 + $1.duration } }
}

struct FolderBrowserView: View {
    let groups: [FolderGroup]
    let onPlay: (Track) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(groups) { group in
                    FolderDisclosureGroup(group: group, onPlay: onPlay)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }
}

private struct FolderDisclosureGroup: View {
    let group: FolderGroup
    let onPlay: (Track) -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayer
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            LazyVStack(spacing: 2) {
                ForEach(group.tracks) { track in
                    TrackRow(
                        track: track,
                        isCurrent: player.currentTrack?.id == track.id,
                        isPlaying: player.isPlaying,
                        isFavorite: library.isFavorite(track),
                        play: { onPlay(track) },
                        toggleFavorite: { library.toggleFavorite(track) },
                        reveal: { library.reveal(track) },
                        remove: { library.remove(track) }
                    )
                }
            }
            .padding(.top, 7)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.hpGold)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.92))
                    Text(group.path)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.hpTextPrimary.opacity(0.36))
                        .lineLimit(1)
                }

                Spacer()

                Text("\(group.tracks.count) 首 · \(Track.formatTime(group.duration))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.hpTextPrimary.opacity(0.40))
            }
            .padding(.horizontal, 13)
            .frame(height: 58)
            .background(Color.hpTextPrimary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .tint(Color.hpTextPrimary.opacity(0.52))
    }
}
