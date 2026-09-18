# 下一版本（尚未分配版本号）

- 发布状态：开发中
- 上一稳定版本：`v3.11.0`
- 当前 `VERSION`：`3.11.0`

## 摘要

修复切换歌曲时播放页歌词先显示“正在等待歌词”占位、歌词到达后再跳一下的问题：新增会话级歌词缓存，资料库加载完成后在后台批量预热全部曲目的内嵌歌词/LRC；播放每首歌曲时再提前读取队列接下来两首。切歌时若缓存已就绪，歌词在同一轮状态更新中同步落位，占位不再出现；只有确认没有歌词的歌曲才显示“本歌曲暂无歌词”。

## 用户可见更新

### 新增

- 暂无

### 改进

- 歌词预加载：资料库加载完成后后台逐项低优先级解析全部曲目的内嵌歌词与同名 LRC；播放期间每加载一首歌曲，也会提前发起队列接下来两曲的歌词读取。切换歌曲时歌词直接显示，不再先闪一段“暂无歌词/正在等待歌词”再跳成正文。
- 歌词占位状态区分加载中与确认无歌词：正在读取时显示“正在载入歌词”；确认歌曲确实没有内嵌歌词或 LRC 文件时才显示“本歌曲暂无歌词 / 未在歌曲内嵌信息或同名 LRC 文件中找到歌词。”
- 连续快速切歌时歌词面板做极轻“呼吸”：切歌瞬间整块歌词内容透明度下沉到 0.5，约 0.14 秒内恢复，盖住列表重排顿挫；歌词视图身份保持不变、不做销毁重建，只改合成层透明度，零布局开销。
- 连续快速切歌时立即暂停播放：相邻两次切歌间隔小于 0.7 秒即判定为快切，快切期间保持暂停，切歌停顿 0.4 秒后只播放最后选定的最新一首。修复“切了很多首后，声音和进度条仍停在第一二首、直到切完才跳到最新”的错位；慢速点歌（间隔大于 0.7 秒）仍立即播放，行为不变。
- 修复快切期间播放条把切歌耗时误记为播放进度的问题：连续切歌五六秒，进度条不再虚走到五六秒；快切期间插值冻结在真实媒体时间，恢复播放后从 0 平滑起步，不再出现“先显示 0:06 再跳回 0:01”的跳变。播放栏与播放页两处进度行行为一致。

### 修复

- 修复每切换一首歌曲歌词区域都先显示等待提示、几百毫秒后再替换为歌词造成跳动的问题（大部分歌曲本来就有歌词）。
- 修复快速连切时播放条虚走、恢复播放后跳回 0 的问题：切歌耗时不再计入播放进度。

## 技术变更

- 新增 `LyricsCache`（`Sources/HarmonyPlayer/Services/LyricsCache.swift`）：`@unchecked Sendable` 会话缓存，NSLock 保护已解析歌词字典、无歌词 ID 集合与在途任务字典；`immediateResult(for:)` 提供主线程同步读取（`.ready([LyricLine]) / .missing`），`load(track:)` 返回合并去重的 `Task<[LyricLine]?, Never>`（同一首歌只允许一次磁盘 IO，解析为空按无歌词缓存）；`preload(_:)` 逐项 utility 优先级预热并微让步，`preloadNext(_:)` 为队列邻近曲目即时发起读取，`removeAll()` 在内存压力时清空。
- `EmbeddedMetadataReader` 新增 `readLyrics(from:)` 轻量路径：FLAC 遍历元数据块时只解析唯一的 VORBIS_COMMENT（块类型 4），解析到即返回；PICTURE（块类型 6）等其他块一律 `skip` seek 跳过、不读取 MB 级内容。
- `AudioMetadataLoader.lyrics(for:)` 的 FLAC 内嵌歌词读取由全量 `read(from:)` 改为 `readLyrics(from:)`。
- `AudioPlayer`：新增 `@Published private(set) var lyricsResolved`；`load(_:)` 与 `restorePlaybackState` 中的歌词加载统一改为 `prepareLyrics(for:)`——先同步查 `LyricsCache`（命中则在当前主线程更新轮内直接赋值 `lyricLines` 并置 `lyricsResolved = true`），未命中才异步等待并在校验曲目 ID 后发布；新增 `prefetchUpcomingLyrics()` 预热队列顺序接下来两曲。
- `MainView`：资料库加载完成（`onAppear` 未在加载 / `isLoading` 变为 false）时调用 `LyricsCache.shared.preload(library.tracks)`，不绑定“启动预加载封面”开关。
- `HomeView` 首页推荐歌词改为经由 `LyricsCache.load(track:)` 获取，与预热/播放共用同一份缓存。
- `NowPlayingView` 歌词面板新增“呼吸”：`@State lyricsDimmed/lyricsDimmerGeneration`，`onChange(of: currentTrack?.id)` 时置暗并用代数号合并连续切换（只有最后一次的恢复生效），`DispatchQueue.main.asyncAfter` 0.06s 后以 0.14s easeInOut 恢复；作用于 Group 的 `.opacity`，无 `.id`、无视图重建，Reduce Motion 时跳过。
- `AudioPlayer` 新增快切暂停：`rapidSwitchWindow = 0.7s / rapidSwitchSettleDelay = 0.4s`，`lastLoadAt / isRapidSwitching / switchGeneration` 状态；`load(_:)` 开头计算与上次加载的间隔，处于快切（本次间隔小或已在快切中）时 `player.pause()` 并由 `scheduleRapidSwitchResume(generation:trackID:)` 延迟恢复——代数号保证只有最后一次切换的任务执行 `player.play()`；周期时间观察器在 `isRapidSwitching` 时丢弃回报，进度条不显示前两曲的旧位置。
- `AudioPlayer.isRapidSwitching` 由私有改为 `@Published private(set)`，暴露给进度 UI。
- `PlayerBar.PlaybackProgressRow` 新增 `isRapidSwitching` 入参（播放栏与播放页两处调用均传入 `player.isRapidSwitching`）：TimelineView 的墙钟航位推算改为 `isPlaying && !isRapidSwitching` 才推进，否则冻结显示锚点时间；新增 `onChange(of: isRapidSwitching)` 在快切开始/结束两个边沿把锚点重钉到真实媒体时间（load 已置 0），保证新曲目从 0 平滑起步；时间 tick 重锚分支同样改用 `advancing` 判定，快切期间的 tick 不影响锚点。
- `MemoryPressureMonitor` 内存压力处理增加清空 `LyricsCache`。
- `LongSessionMemoryTests` 的合成曲目由 0.3s 调整为 4s：快切修复后最新曲目会在停顿后恢复播放，旧短曲会在收尾 2s RunLoop 内播完自动切歌，使“当前曲目 = 最后切换曲目”的断言失效（旧断言实际依赖快切滞后 bug）。
- 新增 `Tests/HarmonyPlayerTests/LyricsCacheTests.swift`（合成 FLAC 字节流：验证跳过前置 PICTURE 块读取歌词、无注释块返回 nil、同名 LRC 加载与同步命中、无歌词缓存为 .missing、removeAll 清空）。

## 兼容性与迁移

- 暂无数据格式或配置迁移；歌词缓存为会话内存缓存，`library.json` 格式不变。

## 验证

- `swift test`：32/32 通过（新增 5 个 LyricsCache 用例）。
- Release 构建分支副本 `dist/漫域音乐-lyrics-preload.app` 签名后实际运行，等待用户验证：连续切换多首歌曲时歌词直接出现、不再先闪等待提示；无歌词歌曲显示“本歌曲暂无歌词”；快切期间进度条冻结不虚走，恢复后从 0 平滑起步。

## 已知问题与后续

- 随机模式下一首不可预测，极早期（全库预热尚未跑到该曲目时）随机跳到未预热曲目仍可能短暂显示“正在载入歌词”；预热完成后不再出现。
- 后续继续执行一功能一分支，合并和发布完成后删除已用完的分支。

## 修订记录

暂无。
