import Foundation

struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: Double
    let dateAdded: Date

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        artist: String,
        album: String,
        duration: Double,
        dateAdded: Date = .now
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.dateAdded = dateAdded
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? url.deletingPathExtension().lastPathComponent
            : title
    }

    var displayArtist: String {
        let value = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "未知艺人" : value
    }

    var displayAlbum: String {
        let value = album.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "未知专辑" : value
    }

    var formattedDuration: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        return Self.formatTime(duration)
    }

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, remaining)
    }
}

enum LibrarySection: String, CaseIterable, Identifiable {
    case home
    case all
    case albums
    case artists
    case folders
    case recent
    case history
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .all: "歌曲"
        case .albums: "专辑"
        case .artists: "艺术家"
        case .folders: "文件夹"
        case .recent: "最近添加"
        case .history: "最近播放"
        case .favorites: "我喜欢"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .all: "music.note.list"
        case .albums: "square.stack"
        case .artists: "person.2.fill"
        case .folders: "folder.fill"
        case .recent: "plus.circle.fill"
        case .history: "clock.arrow.circlepath"
        case .favorites: "heart.fill"
        }
    }
}

enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case all
    case one

    var systemImage: String {
        switch self {
        case .off, .all: "repeat"
        case .one: "repeat.1"
        }
    }

    var isActive: Bool { self != .off }

    mutating func advance() {
        switch self {
        case .off: self = .all
        case .all: self = .one
        case .one: self = .off
        }
    }
}

extension Notification.Name {
    static let focusLibrarySearch = Notification.Name("HarmonyPlayer.focusLibrarySearch")
}


struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: Double?
    let text: String
}

struct AlbumGroup: Identifiable, Hashable {
    let title: String
    let artist: String
    let tracks: [Track]

    var id: String { "\(title)|\(artist)" }
    var artworkTrack: Track? { tracks.first }
    var duration: Double { tracks.reduce(0) { $0 + $1.duration } }
}

struct ArtistGroup: Identifiable, Hashable {
    let name: String
    let tracks: [Track]

    var id: String { name }
    var artworkTrack: Track? { tracks.first }
    var albumCount: Int { Set(tracks.map(\.displayAlbum)).count }
}


enum LibraryDestination: Hashable, Identifiable {
    case section(LibrarySection)
    case playlist(UUID)

    var id: String {
        switch self {
        case .section(let section):
            return "section-\(section.rawValue)"
        case .playlist(let id):
            return "playlist-\(id.uuidString)"
        }
    }
}

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var trackIDs: [UUID]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        trackIDs: [UUID] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = createdAt
    }
}

struct PlayHistoryEntry: Identifiable, Codable, Hashable {
    let trackID: UUID
    var lastPlayedAt: Date
    var playCount: Int

    var id: UUID { trackID }
}

enum TrackSortOrder: String, CaseIterable, Identifiable {
    case title
    case artist
    case album
    case duration
    case dateAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: "标题"
        case .artist: "艺人"
        case .album: "专辑"
        case .duration: "时长"
        case .dateAdded: "添加时间"
        }
    }

    var systemImage: String {
        switch self {
        case .title: "textformat"
        case .artist: "person"
        case .album: "square.stack"
        case .duration: "clock"
        case .dateAdded: "calendar"
        }
    }
}
