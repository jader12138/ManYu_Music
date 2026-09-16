import AppKit
import Combine
import Foundation
import XCTest

@testable import HarmonyPlayer

// MARK: - 隔离的临时工作目录

/// 每个用例独立的临时目录：只在系统临时目录下创建自己唯一的子目录，
/// 清理时也只删除这一个自己创建的路径。
/// 所有用例都不读取、不写入用户的 Application Support / 音乐目录 / UserDefaults。
final class TempWorkspace {
    let root: URL

    init() {
        let name = "HarmonyPlayerTests-\(UUID().uuidString)"
        root = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// 默认的 library.json 位置（此时父目录已存在）。
    var libraryURL: URL { root.appendingPathComponent("library.json") }

    func path(_ relativePath: String) -> URL {
        root.appendingPathComponent(relativePath)
    }

    @discardableResult
    func makeDirectory(_ relativePath: String) throws -> URL {
        let url = path(relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ data: Data, to relativePath: String) throws {
        let url = path(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    func read(_ relativePath: String) throws -> Data {
        try Data(contentsOf: path(relativePath))
    }

    /// 安全护栏：只删除系统临时目录下、且由本类命名的唯一路径。
    /// 任何前缀不匹配的路径都会被拒绝删除。
    func remove() {
        let target = root.standardizedFileURL
        let temp = FileManager.default.temporaryDirectory.standardizedFileURL
        guard target.path.hasPrefix(temp.path),
              target.lastPathComponent.hasPrefix("HarmonyPlayerTests-")
        else { return }
        try? FileManager.default.removeItem(at: target)
    }
}

extension XCTestCase {
    /// 创建独立临时目录，并在用例结束时只清理这个目录。
    func makeTempWorkspace() -> TempWorkspace {
        let workspace = TempWorkspace()
        addTeardownBlock { workspace.remove() }
        return workspace
    }
}

// MARK: - 数据构造

/// 稳定且可比较的 UUID（低位递增），用于断言平局时的排序。
func testUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "%08x-0000-4000-8000-%012x", value, value))!
}

func makeTestTrack(
    id: UUID = UUID(),
    title: String,
    artist: String = "默认艺人",
    album: String = "默认专辑",
    duration: Double = 180,
    dateAdded: Date = Date(timeIntervalSince1970: 1_000),
    directory: String = "/tmp/harmony-tests",
    fileName: String? = nil
) -> Track {
    let name = fileName ?? "\(title.isEmpty ? "untitled" : title)-\(id.uuidString.prefix(8)).mp3"
    let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
    return Track(
        id: id,
        url: url,
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        dateAdded: dateAdded
    )
}

func makeBrowseRequest(
    section: LibrarySection,
    search: String = "",
    sortOrder: TrackSortOrder = .title,
    ascending: Bool = true
) -> LibraryBrowseRequest {
    LibraryBrowseRequest(
        revision: 1,
        isLoading: false,
        section: section,
        search: search,
        sortOrder: sortOrder,
        ascending: ascending
    )
}

// MARK: - 异步等待（有截止超时，不做长轮询）

/// 载入完成信号：由 `isLoading` 的 Combine 订阅置位。
private final class LoadSignal {
    var isLoaded = false
}

/// 用 Combine 订阅 `isLoading` 作为完成信号，配合 `Task.yield` 与硬截止超时等待。
/// 不阻塞主线程（不会卡住 MainActor 上完成载入的 Task），也不会无限等下去。
@MainActor
func waitForLibraryLoad(
    _ store: LibraryStore,
    timeout: TimeInterval = 10,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    if !store.isLoading { return }

    let signal = LoadSignal()
    let cancellable = store.$isLoading
        .filter { !$0 }
        .prefix(1)
        .sink { _ in signal.isLoaded = true }
    defer { cancellable.cancel() }

    let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
    while !signal.isLoaded, ContinuousClock.now < deadline {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(5))
    }

    XCTAssertTrue(signal.isLoaded, "资料库未在 \(timeout)s 内完成载入", file: file, line: line)
}

/// 让 400ms 防抖窗口过去，用于断言“被取消的旧写入不会回写”。
/// 只做一次有界等待，不轮询、不用于等待载入。
func settleSaveDebounce() async {
    try? await Task.sleep(for: .milliseconds(700))
}

// MARK: - 落盘 JSON 读写

/// 复现旧版落盘格式：只写 tracks / favoriteIDs，缺 playlists / history 字段。
func encodeLegacyLibraryJSON(
    tracks: [Track],
    favoriteIDs: [UUID],
    extraKeys: [String: Any] = [:]
) throws -> Data {
    let tracksData = try JSONEncoder().encode(tracks)
    let trackObjects = try JSONSerialization.jsonObject(with: tracksData) as? [[String: Any]] ?? []

    var object: [String: Any] = [
        "tracks": trackObjects,
        "favoriteIDs": favoriteIDs.map(\.uuidString)
    ]
    object.merge(extraKeys) { _, new in new }
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

/// 只读探针，用来检查 store 真实写出的文件内容。
struct PersistedLibraryProbe: Decodable {
    let tracks: [Track]
    let favoriteIDs: [UUID]
    let playlists: [Playlist]
    let history: [PlayHistoryEntry]
}

func decodeLibraryFile(_ data: Data) throws -> PersistedLibraryProbe {
    try JSONDecoder().decode(PersistedLibraryProbe.self, from: data)
}

// MARK: - 测试内生成的图片（不读取任何用户资源）

/// 用 CoreGraphics 现场生成 PNG，避免依赖仓库或用户目录里的图片。
func makePNGData(width: Int, height: Int) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setFillColor(CGColor(red: 0.25, green: 0.45, blue: 0.85, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))

    guard let image = context.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}
