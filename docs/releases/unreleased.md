# 下一版本（v1.1.0-beta2 测试版或 v1.1.0 正式版准备中）

- 发布状态：**v1.1.0-beta1 已于 2026-09-23 发布**（GitHub Releases，prerelease，不顶替 v0.5 稳定版；见文末附录）。
- 已发布 1.1 内测：`v1.1.0-beta1`。
- 上一稳定版本：`v0.5`（原 v3.12.0）
- 当前 `VERSION`：`1.1.0-beta1`（已随 beta1 发布）

## 本轮摘要（2026-09-23，分支 `codex/v1.1-beta1`：封面转场动画优化 + 改号 1.1）

### 用户可见变化

- 播放页切歌时专辑封面切换动画改为**缩放渐入**：新封面从 92% 缩放渐入放大到 100% + 淡入，旧封面原地淡出，丝滑无位移。
- 动画时长从 0.5s 缩短到 0.35s，切歌更利落。
- 设置 → 关于页显示版本号 `1.1.0-beta1`。

### 技术变更

- **`AudioPlayer.loadArtwork(for:)`**：在 `Task { }` 之前加入同步 `ArtworkCache.shared.image(for:tier:)` 查找。缓存命中时在同一个 runloop 内设置 `self.artwork`，让 SwiftUI `.id(player.currentTrack?.id)` 触发的转场动画第一帧就有正确封面图，消除"图突然换"的视觉跳变。缓存未命中时仍走异步路径，且命中后跳过重复赋值。
- **`NowPlayingView.albumPanel`**：转场从 `.asymmetric(insertion: .modifier(ArtworkPushInModifier), removal: .modifier(ArtworkFadeOutModifier))` 改为 `.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity)`。原因：新旧视图共享同一个 `player.artwork`，push-out 下旧视图滑出时显示新图导致违和感；缩放渐入在同位置渐变，对共享图属性不敏感。
- 删除不再引用的 `ArtworkPushInModifier` 和 `ArtworkFadeOutModifier` 两个自定义 `ViewModifier`（约 25 行）。
- 动画曲线从 `.easeOut(duration: 0.5)` 改为 `.easeInOut(duration: 0.35)`。

### 兼容性

- 无数据格式变更，`library.json` 和 UserDefaults 完全兼容。
- 无新增系统权限需求。

### 验证

- `swift build` 编译通过。
- `swift test --disable-sandbox` 全部通过（0 failures）。
- `scripts/build-app.sh` release 打包成功，`codesign --verify --deep --strict` 通过。
- 真机启动后连续切歌 5 次以上，封面切换平滑无跳变、无闪烁、无旧图残留。

## 发布附录：v1.1.0-beta1

- **标签**：`v1.1.0-beta1`（annotated tag），打在 main 合并提交上。
- **GitHub Release**：prerelease=true、latest=false（不顶替 v0.5 稳定版）。
- **资产**：`ManyuMusic-1.1.0-beta1.dmg`。
- **前身版本**：v1.0.0-beta1（2026-09-23）。

## 历史附录：v1.0.0-beta1（2026-09-23，分支 codex/version-1.0-beta1 + codex/readme-rewrite）

### 用户可见变化

- 软件本体版本号从 `3.13.0-beta5` 升级为 `1.0.0-beta1`（内部测试版标识）。
- 删除侧栏左上角 Logo 的旧版兜底绘制（深蓝紫渐变 + 白色播放三角），资源异常时显示主题色音符中性占位。
- README 全面重写，覆盖 v1.0.0-beta1 全部功能。

### 技术变更

- `VERSION` → `1.0.0-beta1`；`Info.plist` 模板 `CFBundleShortVersionString` → `1.0.0`，`ManyuMusicReleaseName` → `1.0.0-beta1`。
- `SidebarView.swift`：删除 `BrandMark` 中约 60 行旧版 Logo 渐变/三角/月牙兜底绘制代码。
- `README.md` 全文重写。

### 验证

- 编译通过、单测全部通过、release 签名验证通过、真机运行确认侧栏为最新白色图标。

## 更早历史

### GitHub 版本线重排（2026-09-23，分支 `codex/renumber-versions-0x`）

主人决定：1.0 正式版尚未发布，以前的版本号都不算，GitHub 上全部历史版本改编号为 0.1 起的连续序列，下一步直接发布 1.0 测试版。

- **用户可见变化**：仅 GitHub Releases / Git 标签层面，应用本体无任何改动。
- **编号映射**（时间从旧到新）：

  | 旧标签 | 新标签 | 指向提交 | 说明 |
  | --- | --- | --- | --- |
  | `v3.8.0` | `v0.1` | `f52ba86` | 原仅有标签无 Release，本次补建 Release（无安装包，说明据 `docs/releases/v3.8.0.md` 整理） |
  | `v3.9.0` | `v0.2` | `526d1fa` | 稳定版 |
  | `v3.10.0` | `v0.3` | `09c92dd` | 稳定版 |
  | `v3.11.0` | `v0.4` | `daa8d34` | 稳定版 |
  | `v3.12.0` | `v0.5` | `26b16e0` | 稳定版，Latest；DMG 改名 `ManyuMusic-0.5.dmg` |
  | `v3.13.0-beta1` | `v0.6` | `cdd851e` | prerelease；DMG 改名 `ManyuMusic-0.6.dmg` |
  | `v3.13.0-beta2` | `v0.7` | `e2cfa7e` | prerelease；DMG 改名 `ManyuMusic-0.7.dmg` |
  | `v3.13.0-beta3` | `v0.8` | `b8125d0` | prerelease；DMG 改名 `ManyuMusic-0.8.dmg` |
  | `v3.13.0-beta4` | `v0.9` | `a1f2632` | prerelease；DMG 改名 `ManyuMusic-0.9.dmg` |
  | `v3.13.0-beta5` | `v0.10` | `6b4e352` | prerelease；DMG 改名 `ManyuMusic-0.10.dmg` |

- **技术变更**：新标签全部为 annotated tag，指向与旧标签相同的提交，tagger 日期保留原值（2026-09-13 ~ 2026-09-21）；Release 按时间从旧到新重建（稳定版 `--latest=false`，最后由 GitHub 自动把 Latest 落到 v0.5），标题/正文中的旧版本号字符串整体替换，6 个 DMG 下载后以新文件名重新上传；校验回下载 v0.5/v0.9 的 SHA-256 与原包逐字节一致（`0c5b00f5…`、`20fb6a53…`）；旧 10 个标签与 9 个旧 Release 全部删除（远端 + 本地）。
