# 歌曲自动监听入库（功能 1）

## Context

用户添加过文件夹后，如果之后往该文件夹里放入新歌，当前软件不会自动发现——必须手动点设置页的"重新扫描资料库"或"添加音乐"才能入库。而且现有的"重新扫描"（[LibraryStore.rescanLibrary()](file:///Users/chenl/Documents/workbuddy/漫域音乐/Sources/HarmonyPlayer/Services/LibraryStore.swift#L130-L196)）调的是 [refreshTracks(_:)](file:///Users/chenl/Documents/workbuddy/漫域音乐/Sources/HarmonyPlayer/Services/LibraryStore.swift#L701-L743)，它只对**已存在的 track.url 重新读 metadata**，不会遍历 source 文件夹发现新文件。

需求：每次启动软件时，自动遍历所有已添加的来源（sources），把新增的音频文件入库到曲库，无需用户手动操作。

## 分支

`codex/auto-folder-rescan`，从最新 main（48626e9）拉取。功能 2「重复检测」是另一个独立分支 `codex/duplicate-detect`，**本分支合并后再开**，不在本计划内。

## 实施方案

### 1. LibraryStore 新增 `rescanSourcesForNewTracks()` 方法

在 [LibraryStore.swift](file:///Users/chenl/Documents/workbuddy/漫域音乐/Sources/HarmonyPlayer/Services/LibraryStore.swift) 里新增一个实例方法，逻辑直接复用 [add(urls:)](file:///Users/chenl/Documents/workbuddy/漫域音乐/Sources/HarmonyPlayer/Services/LibraryStore.swift#L230-L332) 的核心流程，但**不重复记录 sources**（sources 已有），且**无新歌时静默不打扰用户**：

```swift
/// 启动加载完成后自动扫描已添加的来源，把新增音频文件入库。
/// 静默扫描：发现新歌时提示"自动扫描到 N 首新歌"，无新歌时不显示任何提示。
func rescanSourcesForNewTracks() {
    guard canEdit else { return }
    guard !sources.isEmpty, !isImporting else { return }
    isImporting = true
    importNotice = nil
    removedDuringImport.removeAll()
    removedSourcePathsDuringImport.removeAll()
    let clear = clearGeneration
    let sourceURLs = sources.map(\.url)

    Task {
        defer {
            isImporting = false
            removedDuringImport.removeAll()
            removedSourcePathsDuringImport.removeAll()
            clearNoticeAfterDelay()
        }

        let expandedURLs = await Task.detached(priority: .utility, [blockedFolderPaths]) { blocked in
            Self.expandAndFilter(sourceURLs, blockedFolderPaths: blocked)
        }.value

        guard clearGeneration == clear else { return }

        let knownPaths = Set(tracks.map { Self.normalizedPath($0.url) })
        let newURLs = expandedURLs.filter { url in
            let path = Self.normalizedPath(url)
            return !knownPaths.contains(path) && !self.isImportBlocked(path)
        }

        guard !newURLs.isEmpty else {
            importNotice = nil   // 无新歌：静默，不显示提示
            return
        }

        let imported = await Task.detached(priority: .utility) {
            await Self.readTracks(from: newURLs)
        }.value
        guard clearGeneration == clear else { return }

        let livePaths = Set(tracks.map { Self.normalizedPath($0.url) })
        var accepted = imported.filter { track in
            let path = Self.normalizedPath(track.url)
            return !livePaths.contains(path) && !self.isImportBlocked(path)
        }
        if filterShortAudio {
            accepted = accepted.filter { $0.duration >= 60 }
        }
        guard !accepted.isEmpty else {
            importNotice = nil
            return
        }

        let baseGeneration = tracksGeneration
        let updated = (tracks + accepted).sorted { $0.dateAdded > $1.dateAdded }
        let cache = await Task.detached(priority: .utility) {
            TrackDerivedCache.make(from: updated)
        }.value
        guard clearGeneration == clear else { return }

        if tracksGeneration == baseGeneration {
            preparedDerivedCache = cache
            tracks = updated
        } else {
            var reconciled = tracks
            let currentPaths = Set(tracks.map { Self.normalizedPath($0.url) })
            reconciled.append(contentsOf: accepted.filter {
                let path = Self.normalizedPath($0.url)
                return !currentPaths.contains(path) && !self.isImportBlocked(path)
            })
            reconciled.sort { $0.dateAdded > $1.dateAdded }
            tracks = reconciled
        }

        libraryContentDidChange()
        importNotice = "自动扫描到 \(accepted.count) 首新歌。"
    }
}
```

**为什么独立方法而不是直接调 `add(urls: sources.map(\.url))`**：
- `add` 在无新文件时会把 `importNotice` 设为"没有发现新的可播放音频文件"，启动时弹出这条很烦人；
- `add` 开头会遍历 urls 重复跑 `sources.contains` 去重逻辑（虽然能被 guard 跳过，但语义上 add 是"用户主动添加"动作，启动自动扫描是另一种语义，独立方法更清晰，文案也更贴合（"自动扫描到 N 首新歌"）。

### 2. 在加载完成后触发自动扫描

在 [apply(_:)](file:///Users/chenl/Documents/workbuddy/漫域音乐/Sources/HarmonyPlayer/Services/LibraryStore.swift#L523-L544) 里，`.loaded` case 赋值完所有状态、`isLoading = false` 之前或之后调用一次：

```swift
case .loaded(let payload, let cache):
    preparedDerivedCache = cache
    tracks = payload.tracks
    favoriteIDs = Set(payload.favoriteIDs)
    playlists = payload.playlists
    history = payload.history
    sources = payload.sources
    blockedFolderPaths = payload.blockedFolderPaths
    revision &+= 1
    // 加载成功后自动扫描已添加来源，发现新歌就入库
    rescanSourcesForNewTracks()
```

注意调用顺序：必须先设完 `sources` 和把 `isLoading` 置为 false（`canEdit` 依赖 `!isLoading`），再调用 `rescanSourcesForNewTracks()`。但 `apply` 末尾 `isLoading = false` 在 switch 之后，所以需要把调用挪到 `isLoading = false` 之后，或在 switch 内部先设 `isLoading = false`。实施时把 `isLoading = false` 挪到 `.loaded` case 内（或 switch 之前统一置 false 后再调用），保证 `canEdit` 为 true。

`.missing`（首次启动无 library.json）和 `.failed`（文件损坏）case 不触发自动扫描——前者 sources 为空，后者 canEdit 为 false，guard 会拦住。

### 3. 不需要新增设置开关

用户原话是"每次打开软件时自动扫描"，没说做成开关。自动扫描是默认行为，无需设置项。如果后续用户觉得启动变慢想关掉，再补开关——本次不提前加（遵循"仅实现当前提出的需求"）。

### 4. 不需要改 SettingsView / HarmonyPlayerApp

LibraryStore 自己在 `init` → `startLoading` → `apply` 链路里完成自动扫描，App 入口和设置页无需改动。

## 关键文件

- [Sources/HarmonyPlayer/Services/LibraryStore.swift](file:///Users/chenl/Documents/workbuddy/漫域音乐/Sources/HarmonyPlayer/Services/LibraryStore.swift)
  - 新增 `rescanSourcesForNewTracks()` 方法（紧跟 `rescanLibrary()` 之后，约 L196 处）
  - 修改 `apply(_:)`（L523-L544）：`.loaded` case 末尾调用 `rescanSourcesForNewTracks()`
  - 复用现有：`expandAndFilter`（L651）、`readTracks`（L745）、`isImportBlocked`（L337）、`normalizedPath`、`libraryContentDidChange`、`scheduleSave`、`clearNoticeAfterDelay`、`filterShortAudio`、`clearGeneration`、`tracksGeneration`、`preparedDerivedCache`

## 验证

1. **单元/集成测试**：`swift test`（现有 94 个测试全过；本功能是 IO + 异步流程，不易写单测，靠手动验证）
2. **编译**：`swift build -c release`
3. **签名校验**：`scripts/build-app.sh` 构建 dist 副本 `dist/漫域音乐-auto-rescan.app`，`codesign --verify` 通过
4. **手动端到端验证**：
   - 确保有至少一个已添加的文件夹来源（之前用过软件的话 sources 已有）
   - 往该文件夹放一首新歌（复制一个 .mp3 进去）
   - `pkill -f "漫域音乐"` 关掉旧进程，`open dist/漫域音乐-auto-rescan.app`
   - 预期：歌曲菜单出现新歌，播放条上方短暂提示"自动扫描到 1 首新歌"
   - 再启动一次（无新歌）：预期无提示，不弹"没有发现新的可播放音频文件"
5. **文档**：更新 CHANGELOG.md 和 docs/releases/unreleased.md，记录"启动时自动扫描已添加文件夹，发现新歌自动入库"

## 风险与边界

- **与手动 import 并发**：`rescanSourcesForNewTracks` 复用 `isImporting` 状态机，启动后用户立刻手动点"添加音乐"会被 `guard !isImporting` 拦截——可接受（启动扫描很快，用户一般不会秒级操作）
- **sources 里的文件来源**（非文件夹）：`expandAndFilter` 对单文件 URL 直接判断扩展名，能正确处理
- **加载失败**：`isPersistenceSuppressed` 时 `canEdit` 为 false，guard 拦截，不扫描——保护原文件不被覆写
- **性能**：扫描整个 sources 树会遍历所有文件，但 `expandAndFilter` 只对支持的扩展名收集，`readTracks` 只对真正的新文件（diff 后）读 metadata，老文件不重读——增量 diff，启动开销可控
