import Foundation

struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: Double
    let dateAdded: Date
    // 音频技术参数：首次扫描写入，老 library.json 缺键解码为 nil（弹层显示"未知"）
    var bitrate: Int?       // bits per second
    var sampleRate: Int?    // Hz
    var channels: Int?      // 声道数

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        artist: String,
        album: String,
        duration: Double,
        dateAdded: Date = .now,
        bitrate: Int? = nil,
        sampleRate: Int? = nil,
        channels: Int? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.dateAdded = dateAdded
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.channels = channels
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

enum LibrarySection: String, CaseIterable, Identifiable, Sendable {
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

    var helpText: String {
        switch self {
        case .off: "开启列表循环"
        case .all: "切换为单曲循环"
        case .one: "关闭循环"
        }
    }

    mutating func advance() {
        switch self {
        case .off: self = .all
        case .all: self = .one
        case .one: self = .off
        }
    }
}

/// 三态合一的播放模式：顺序播放 → 单曲循环 → 随机播放，点击一个按钮循环切换。
/// 底层播放推进仍由 AudioPlayer 的 isShuffle / repeatMode 执行。
enum PlaybackMode: String, CaseIterable, Sendable {
    case sequential
    case singleRepeat
    case shuffle

    var systemImage: String {
        switch self {
        case .sequential: "repeat"
        case .singleRepeat: "repeat.1"
        case .shuffle: "shuffle"
        }
    }

    var helpText: String {
        switch self {
        case .sequential: "顺序播放"
        case .singleRepeat: "单曲循环"
        case .shuffle: "随机播放"
        }
    }

    /// 当前模式下再点一次进入的模式：顺序 → 单曲循环 → 随机 → 顺序。
    var next: PlaybackMode {
        switch self {
        case .sequential: .singleRepeat
        case .singleRepeat: .shuffle
        case .shuffle: .sequential
        }
    }
}

extension Notification.Name {
    static let focusLibrarySearch = Notification.Name("HarmonyPlayer.focusLibrarySearch")
    static let openSettings = Notification.Name("HarmonyPlayer.openSettings")
    /// 空库引导等入口：跳过设置页，直接弹出"添加文件或文件夹"面板。
    static let openImportPanel = Notification.Name("HarmonyPlayer.openImportPanel")
    /// 点击歌手名进入艺术家详情页，object 传艺术家名 String。
    static let openArtist = Notification.Name("HarmonyPlayer.openArtist")
}


struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: Double?
    let text: String
    /// 译文：双语 LRC 中与原文时间戳相同的相邻行的文本。
    /// 单语歌词该字段为 nil。显示开关关闭时只渲染 text。
    let translation: String?

    init(id: Int, time: Double?, text: String, translation: String? = nil) {
        self.id = id
        self.time = time
        self.text = text
        self.translation = translation
    }
}

struct AlbumGroup: Identifiable, Hashable {
    let title: String
    let artist: String
    let tracks: [Track]

    var id: String { "\(title)|\(artist)" }
    var artworkTrack: Track? { tracks.first }
    var duration: Double { tracks.reduce(0) { $0 + $1.duration } }
}

struct ArtistGroup: Identifiable, Hashable, Sendable {
    let name: String
    let tracks: [Track]

    var id: String { name }
    var artworkTrack: Track? { tracks.first }
    var albumCount: Int { Set(tracks.map(\.displayAlbum)).count }
}


enum LibraryDestination: Hashable, Identifiable {
    case section(LibrarySection)
    case playlist(UUID)
    case settings
    case stats

    var id: String {
        switch self {
        case .section(let section):
            return "section-\(section.rawValue)"
        case .playlist(let id):
            return "playlist-\(id.uuidString)"
        case .settings:
            return "settings"
        case .stats:
            return "stats"
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
    /// 每次播放的时间戳，用于按天/周/月/年聚合统计。
    /// 老版本 library.json 没有该字段，解码时默认为空数组，
    /// 旧的 lastPlayedAt + playCount 仍保留兼容。
    var recentEvents: [Date]

    var id: UUID { trackID }

    init(
        trackID: UUID,
        lastPlayedAt: Date,
        playCount: Int,
        recentEvents: [Date] = []
    ) {
        self.trackID = trackID
        self.lastPlayedAt = lastPlayedAt
        self.playCount = playCount
        self.recentEvents = recentEvents
    }

    private enum CodingKeys: String, CodingKey {
        case trackID, lastPlayedAt, playCount, recentEvents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trackID = try c.decode(UUID.self, forKey: .trackID)
        lastPlayedAt = try c.decode(Date.self, forKey: .lastPlayedAt)
        playCount = try c.decode(Int.self, forKey: .playCount)
        // 老数据无 recentEvents 字段时回退为空数组，不影响旧的 playCount/lastPlayedAt。
        recentEvents = try c.decodeIfPresent([Date].self, forKey: .recentEvents) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trackID, forKey: .trackID)
        try c.encode(lastPlayedAt, forKey: .lastPlayedAt)
        try c.encode(playCount, forKey: .playCount)
        try c.encode(recentEvents, forKey: .recentEvents)
    }
}

/// 播放统计的时间范围维度。
enum StatsRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "今天"
        case .week: "本周"
        case .month: "本月"
        case .year: "本年"
        }
    }

    /// 当前时间所属区间的起始时刻。
    var intervalStart: Date {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .day:
            return calendar.startOfDay(for: now)
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else {
                return calendar.startOfDay(for: now)
            }
            return interval.start
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: now) else {
                return calendar.startOfDay(for: now)
            }
            return interval.start
        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: now) else {
                return calendar.startOfDay(for: now)
            }
            return interval.start
        }
    }
}

enum TrackSortOrder: String, CaseIterable, Identifiable {
    case title
    case artist
    case album
    case duration
    case dateAdded

    var id: String { rawValue }
}


enum RecommendationFrequency: String, CaseIterable, Identifiable {
    case daily
    case everyLaunch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "每天更新"
        case .everyLaunch: "每次打开软件时更新"
        }
    }

    var systemImage: String {
        switch self {
        case .daily: "calendar"
        case .everyLaunch: "arrow.clockwise"
        }
    }
}

enum RecommendationSettings {
    static let frequencyKey = "ManyuMusic.recommendationFrequency"
    static let independentKey = "ManyuMusic.recommendationIndependent"
    static let trackIDKey = "ManyuMusic.recommendationTrackID"
    static let dayKey = "ManyuMusic.recommendationDay"
}
