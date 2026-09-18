# 下一版本（尚未分配版本号）

- 发布状态：开发中
- 上一稳定版本：`v3.11.0`
- 当前 `VERSION`：`3.11.0`

## 摘要

- 播放模式三合一与整页队列选歌：播放页原来的随机/循环两个按钮融合为「三态播放模式钮 + 列表⇄气泡切换钮」，点列表图标整页跳转到播放队列选歌页，点气泡跳回播放页。
- 修复切换歌曲时播放页歌词先显示“正在等待歌词”占位、歌词到达后再跳一下的问题：新增会话级歌词缓存，资料库加载完成后在后台批量预热全部曲目的内嵌歌词/LRC；播放每首歌曲时再提前读取队列接下来两首。切歌时若缓存已就绪，歌词在同一轮状态更新中同步落位，占位不再出现；只有确认没有歌词的歌曲才显示“本歌曲暂无歌词”。

## 用户可见更新

### 新增

- 新增播放页内部「列表 ⇄ 气泡」融合切换钮（位于原循环按钮位置，即上一首按钮左边）：在播放页点列表图标，封面+歌词区域整块切换为当前播放队列的选歌列表（不离开播放页），点任意歌曲立即切换播放，再点气泡图标切回封面+歌词，图标随状态 morph。队列列表行可右键「从队列移除」；队列为空时显示空状态提示。

### 改进

- 歌曲列表多选入口位置调整：原顶部工具栏的「✓ 编辑」胶囊按钮移到歌曲列表列头「时长」右侧，图标中心与下方歌曲行的爱心按钮居中对齐，仅显示勾选圆图标（去掉「编辑」文字）；点击图标后，全选、删除所选、取消三个纯图标按钮像子菜单一样从图标右侧滑出（浮层，不挤占列宽），图标自身变为实心高亮，再点一次即完成退出，顶部搜索栏右侧不再有多选胶囊与批量操作条。
- 随机播放、顺序播放、单曲循环三种模式融合为一个播放模式按钮：每点一下切换一个模式（顺序播放 → 单曲循环 → 随机播放 → 顺序播放），图标随模式 morph：顺序播放为灰色顺序箭头、单曲循环/随机播放时图标高亮。播放页与底部播放条两处同步。
- 菜单栏「播放」菜单：原「循环模式」子菜单 + 「随机播放」开关合并为「播放模式」子菜单（顺序播放 / 单曲循环 / 随机播放，当前模式打勾）。
- 首页快捷操作「随机播放」现在会正确同步三态播放模式状态。
- 歌词居中补偿：刚播放到前几句时，当前行被居中会导致上方空一大块（前面没有歌词）。LyricTimelineView 的 `centerActive` 在计算 scrollTo 目标 offset 时增加「leadCompensation」补偿——activeIndex=0 往上推 36pt，activeIndex=4 时归零，线性衰减。因为叠在原逐行动画上，切换过渡自然圆滑，不额外引入新动画。

- 歌词预加载：资料库加载完成后后台逐项低优先级解析全部曲目的内嵌歌词与同名 LRC；播放期间每加载一首歌曲，也会提前发起队列接下来两曲的歌词读取。切换歌曲时歌词直接显示，不再先闪一段“暂无歌词/正在等待歌词”再跳成正文。
- 歌词占位状态区分加载中与确认无歌词：正在读取时显示“正在载入歌词”；确认歌曲确实没有内嵌歌词或 LRC 文件时才显示“本歌曲暂无歌词 / 未在歌曲内嵌信息或同名 LRC 文件中找到歌词。”
- 连续快速切歌时歌词面板做极轻“呼吸”：切歌瞬间整块歌词内容透明度下沉到 0.5，约 0.14 秒内恢复，盖住列表重排顿挫；歌词视图身份保持不变、不做销毁重建，只改合成层透明度，零布局开销。
- 连续快速切歌时立即暂停播放：相邻两次切歌间隔小于 0.7 秒即判定为快切，快切期间保持暂停，切歌停顿 0.4 秒后只播放最后选定的最新一首。修复“切了很多首后，声音和进度条仍停在第一二首、直到切完才跳到最新”的错位；慢速点歌（间隔大于 0.7 秒）仍立即播放，行为不变。
- 修复快切期间播放条把切歌耗时误记为播放进度的问题：连续切歌五六秒，进度条不再虚走到五六秒；快切期间插值冻结在真实媒体时间，恢复播放后从 0 平滑起步，不再出现“先显示 0:06 再跳回 0:01”的跳变。播放栏与播放页两处进度行行为一致。

### 修复

- 修复每切换一首歌曲歌词区域都先显示等待提示、几百毫秒后再替换为歌词造成跳动的问题（大部分歌曲本来就有歌词）。
- 修复快速连切时播放条虚走、恢复播放后跳回 0 的问题：切歌耗时不再计入播放进度。

## 技术变更

- 新增 `PlaybackMode`（`Models.swift`）：`sequential / singleRepeat / shuffle` 三态枚举，提供 `systemImage`（顺序=`arrow.right.to.line`、单曲=`repeat.1`、随机=`shuffle`）、`helpText` 与 `next`（顺序→单曲→随机→顺序）。
- `AudioPlayer`：新增 `@Published private(set) var playbackMode` 与 `setPlaybackMode(_:)` / `cyclePlaybackMode()`；切换模式时同步底层 `isShuffle` 与 `repeatMode`（顺序=shuffle false/.off，单曲=shuffle false/.one，随机=shuffle true/.off），播放推进、收尾与随机选曲逻辑沿用原有实现。
- `LyricTimelineView`：`centerActive(in:animated:)` 新增 `leadCompensation` —— 当前行 `activeIndex <= 4` 时对 `baseTarget` 叠加向上偏移（`max(0, 4 - activeIndex) * 9`，activeIndex=0 → 36pt、activeIndex=4 → 0pt），前几句歌词上移避免「上方空一大块」；补偿随着逐行推进自然衰减，叠在原有 0.7s easeInOut 动画上，过渡平滑。
- `PlayerBar`：删除不再使用的 `QueuePickerMorphSymbol` 组件和 `isQueuePicker` / `onReturnToNowPlaying` 入参。
- `QueuePanel.swift`：删除不再使用的 `QueuePickerView`。
- `TrackListView`：新增 `onRemoveTrack` / `removeTrackLabel` 入参，宿主可覆盖行移除动作与菜单文案（默认仍为资料库移除）。
- 多选状态从 `MainView` 下沉到 `TrackListView` 内部：`@State private var isSelectionMode / selectedIDs` 由列表自管，`TrackRow` 新增 `isSelectionMode / isSelected / onToggleSelection`（多选时行首显示勾选圆钮、点击行切换选中、选中行主题色底）；列头首列占位在多选时由 44pt 变为 84pt（28 勾选框 + 12 间距 + 44 封面），使列头文字与歌曲行内容同向同幅右移 40pt 并保持列对齐，不再向左收缩；列头「时长」右侧新增固定 72pt 宽 `ZStack` 编辑区（与行尾爱心+更多区同宽）：入口 `checkmark.circle` 图标钮 `offset(x: 10)` 与下方爱心中心对齐，编辑态变实心高亮且再点退出；全选/删除/取消三个 18pt 宽图标钮作为浮层 `offset(x: 32)` 从右侧以 `.move(edge: .trailing) + opacity` 滑出，不参与 HStack 布局、不挤占列宽。
- `MainView` 删除顶部工具栏的「编辑」胶囊与批量操作 HStack（已选数量/全选/删除/取消）、对应的 `isSelectionMode / selectedTrackIDs` 状态、`isTrackListSection` 计算属性与切换 destination 时的选择重置；`TrackListView` 调用点不再传多选参数。
- `HarmonyPlayerApp`：播放菜单改为「播放模式」三态子菜单（`PlaybackMode.allCases`，当前模式打勾）。
- `HomeView`：快捷「随机播放」改为 `setPlaybackMode(.shuffle)` 后随机点歌。
- 新增 `Tests/HarmonyPlayerTests/PlaybackModeTests.swift`（3 个用例：三态循环顺序与底层状态同步、直接设置模式、`next` 顺序）。
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

- `swift test`：35/35 通过（新增 3 个 PlaybackMode 用例 + 此前 32 个）。
- Release 构建分支副本 `dist/漫域音乐-queue-picker-mode.app` 签名后实际运行，等待用户验证：播放页点列表钮整页跳到队列选歌页、图标 morph 成气泡；选歌页点歌立即播放，点气泡整页跳回播放页、图标 morph 回列表；播放模式钮按 顺序 → 单曲循环 → 随机 循环切换。
- Release 构建分支副本 `dist/漫域音乐-lyrics-preload.app` 签名后实际运行（已并入本分支构建范围），等待用户验证：连续切换多首歌曲时歌词直接出现、不再先闪等待提示；无歌词歌曲显示“本歌曲暂无歌词”；快切期间进度条冻结不虚走，恢复后从 0 平滑起步。
- `swift test` 全部通过；Release 构建分支副本 `dist/漫域音乐-multiselect-header.app` 签名后实际运行，等待用户验证：顶部工具栏不再有「编辑」胶囊；列头「时长」右侧显示纯勾选圆图标，点击进入多选，区域内切换为全选/删除/取消图标钮，勾选与批量删除行为正常。

## 已知问题与后续

- 随机模式下一首不可预测，极早期（全库预热尚未跑到该曲目时）随机跳到未预热曲目仍可能短暂显示“正在载入歌词”；预热完成后不再出现。
- 后续继续执行一功能一分支，合并和发布完成后删除已用完的分支。

## 修订记录

暂无。
