# 歌曲信息新增音频技术参数

## Context

[TrackInfoView.swift](file:///Users/chenl/Documents/workbuddy/漫域音乐/Sources/HarmonyPlayer/Views/TrackInfoView.swift) 是从歌曲列表/播放页三个点菜单弹出的"歌曲信息"弹层，当前展示 8 行：标题/艺人/专辑/时长/格式/播放次数/文件大小/文件位置。

主人希望在弹层中补充音频技术参数，便于了解每首曲目的工程规格：

* **比特率**（如 320 kbps、1411 kbps）

* **采样率**（如 44.1 kHz、48 kHz、96 kHz）

* **通道数量**（单声道/立体声/5.1 等）

* **文件大小** —— 此项已存在（[TrackInfoView.swift:43](file:///Users/chenl/Documents/workbuddy/漫域音乐/Sources/HarmonyPlayer/Views/TrackInfoView.swift#L43-L70) 用 `ByteCountFormatter` 显示，对音频文件通常已以 MB 呈现），本轮不动。

参数从 `AVURLAsset` 的音频轨道实时读取，写回 `Track` 模型并随 library.json 持久化，与现有 title/artist/album/duration 一致。

## 实施步骤

### 1. 创建分支

从最新 `main` 创建 `codex/track-audio-info`，一功能一分支。

### 2. 扩展 Track 模型（[Models.swift:3-28](file:///Users/chenl/Documents/workbuddy/漫域音乐/Sources/HarmonyPlayer/Models/Models.swift#L3-L28)）

新增三个可选字段（`Int?`），保证旧 library.json 缺键时 synthesized Codable 走 `decodeIfPresent` 不崩：

```swift
struct Track: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: Double
    let dateAdded: Date
    // 新增（首次扫描写入，老库解码为 nil → 弹层显示"未知"）
    var bitrate: Int?       // bits per second
    var sampleRate: Int?    // Hz
    var channels: Int?      // 声道数
    ...
}
```

`init` 增加三个默认 `nil` 参数，现有调用点无需改。

### 3. AudioMetadataLoader 抽取音频轨道参数（[AudioMetadataLoader.swift:10-48](file:///Users/chenl/Documents/workbuddy/漫域音乐/Sources/HarmonyPlayer/Services/AudioMetadataLoader.swift#L10-L48)）

复用现有 `asset`（已 `AVURLAssetPreferPreciseDurationAndTimingKey`）：

```swift
let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
var bitrate: Int?
var sampleRate: Int?
var channels: Int?
if let audioTrack = audioTracks.first {
    let dataRate = await audioTrack.load(.estimatedDataRate)        // bps
    if dataRate > 0 { bitrate = Int(dataRate.rounded()) }
    let descs = await audioTrack.load(.formatDescriptions)
    for case let desc as CMAudioFormatDescription in descs {
        guard let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { continue }
        let asbd = asbdPtr.pointee
        if sampleRate == nil, asbd.mSampleRate > 0 {
            sampleRate = Int(asbd.mSampleRate)
        }
        if channels == nil, asbd.mChannelsPerFrame > 0 {
            channels = Int(asbd.mChannelsPerFrame)
        }
    }
}
```

返回 Track 时传入新参数。

### 4. TrackInfoView 弹层新增三行（[TrackInfoView.swift:26-44](file:///Users/chenl/Documents/workbuddy/漫域音乐/Sources/HarmonyPlayer/Views/TrackInfoView.swift#L26-L44)）

在"格式"行后插入：

```swift
infoRow("格式", ...)           // 现有
infoRow("比特率", formattedBitrate)
infoRow("采样率", formattedSampleRate)
infoRow("通道", formattedChannels)
infoRow("播放次数", ...)        // 现有
```

格式化函数（与现有 `fileSize` 风格一致，未读取返回 "未知"）：

* **比特率**：`bitrate / 1000` → "320 kbps"。若 bps ≥ 1\_000\_000 用 Mbps（高码率 Hi-Res 真无损 WAV 可能 >1.4 Mbps）。

* **采样率**：Hz % 1000 == 0 → "X kHz"；否则 "X.X kHz"（44100 → "44.1 kHz"）。

* **通道**：1 → "单声道"；2 → "立体声"；其他 → "N 声道"（如 "6 声道"）。

### 5. 文档与测试

* [CHANGELOG.md](file:///Users/chenl/Documents/workbuddy/漫域音乐/CHANGELOG.md) 新增"歌曲信息弹层新增比特率/采样率/通道数"项到 Unreleased 区块。

* [docs/releases/unreleased.md](file:///Users/chenl/Documents/workbuddy/漫域音乐/docs/releases/unreleased.md) 新增本轮摘要。

* 无需新增单元测试：参数读取来自 AVFoundation，无业务逻辑可断言；现有 94 项回归不应受影响（仅新增字段与显示行）。

### 6. 编译运行验证

* `swift test --disable-sandbox`（94/94 应通过）

* `swift build -c release --disable-sandbox`

* `scripts/build-app.sh` 打包替换 `dist/漫域音乐.app`（沙箱阻断时手动执行等价命令）

* `pkill -f "漫域音乐"` 后 `open` 重启

* 主人验收：打开任意歌曲三个点 → 歌曲信息，确认显示三新字段（MP3 应见 "320 kbps / 44.1 kHz / 立体声"；CD 提取的 WAV 应见 "1411 kbps / 44.1 kHz / 立体声"；96k/24bit Hi-Res 应见相应的更高数值）。

## 兼容性

* Track 新字段全可选，library.json 老 entries 反序列化 nil，弹层显示"未知"；不强制重扫，但新扫描的曲目会有完整参数。

* 不影响播放、队列、歌词、恢复、推荐、均衡器等任何业务路径——只在元数据加载时多取三个字段。

* 无 UserDefaults、无设置项、无 UI 交互改动。

## 风险

* AVURLAsset 在罕见容器（如极少数 m4b 有声书章节轨）可能不返回音频轨，三字段为 nil → 显示"未知"，可接受。

* `estimatedDataRate` 对 VBR MP3 是平均值；对 CBR 是标称值。普通用户感知不到差异，无需特殊处理。

* CMAudioFormatDescriptionGetStreamBasicDescription 对极少数纯 LPCM 无 ASBD 的资产返回 nil，已 fallback 到 nil。

