# Git 与发布管理

## 分支结构

- `main`：稳定主线，只接收经过明确批准的合并
- `codex/*`：功能开发、修复和文档更新分支
- `vX.Y.Z`：正式发布使用的注释标签

当前稳定版本记录在根目录 `VERSION`。已经合并但尚未发布的内容记录在 `docs/releases/unreleased.md`。

## 日常开发

开始任务前先刷新远端，并从一个功能创建一个 `codex/*` 分支：

```bash
git fetch origin
git switch main
git pull --ff-only
git switch -c codex/feature-name
```

开发期间只做本地提交，功能分支不要推送到 GitHub：

```bash
git status
git diff --check
git add <changed-files>
git commit -m "feat: concise description"
```

不要直接在 `main` 上开发，也不要在未获批时合并功能分支。功能分支在开发期间一律不推送 GitHub；只有主人明确说"上传"时，才推送分支，并在同一步完成合并（流程见下节）。

## 文档更新要求

每个功能更新都必须在同一个功能分支中完成：

1. 在 `CHANGELOG.md` 增加简明的用户可见更新。
2. 按需更新 `README.md` 或 `docs/` 下的相关说明。
3. 较大功能或修复合并前，更新 `docs/releases/unreleased.md`。
4. 记录用户可见变化、技术变化、兼容性、验证结果和已知风险。
5. `README.md` 必须保持为项目入口文档，不能写入应用源码。

## 版本化发布记录

发布记录目录为 `docs/releases/`：

- `unreleased.md`：下一版本的累积记录
- `vX.Y.Z.md`：每个正式版本的永久记录
- `TEMPLATE.md`：新版本记录模板
- `README.md`：发布记录索引和归档规则

历史发布记录是只追加档案：

- 不删除旧版本文件
- 不覆盖已经发布的正文
- 不重命名已经发布过的版本
- 勘误只能追加到文件的“修订记录”章节
- 新版本必须加入 `docs/releases/README.md` 的版本索引

## 合并到 main

合并前必须满足：

- 用户已经明确批准合并
- 分支基于最新 `origin/main`
- Release 构建成功
- 应用行为变化时已构建或验证 `.app`
- 打包变化时已执行签名验证
- `CHANGELOG.md`、README 或相关文档已更新
- 较大更新已写入 `docs/releases/unreleased.md`

主人明确说"上传"（即合并批准）时，先推送功能分支到 GitHub，再合并并保留分支历史：

```bash
git push -u origin codex/feature-name
git switch main
git pull --ff-only
git merge --no-ff codex/feature-name
```

推送主线并验证：

```bash
git push origin main
git ls-remote origin refs/heads/main refs/heads/codex/feature-name
```

合并完成后立即删除已经用完的功能分支：

```bash
git branch -d codex/feature-name
git push origin --delete codex/feature-name
```

如果分支曾经被 rebase、压缩或人工确认已安全保存，可以改用 `git branch -D` 删除本地引用。

如果用户明确要求发布，推送后继续创建 GitHub Release：

```bash
gh release create vX.Y.Z \
  --title "漫域音乐 vX.Y.Z" \
  --notes-file "docs/releases/vX.Y.Z.md" \
  --verify-tag
```

## 正式发布

只有用户明确批准发布后，才执行以下流程：

### 1. 确定版本

1. 按语义化版本选择 `X.Y.Z`
2. 更新根目录 `VERSION`
3. 将 `CHANGELOG.md` 的 `Unreleased` 改为正式版本和日期
4. 把 `docs/releases/unreleased.md` 复制为 `docs/releases/vX.Y.Z.md`
5. 补齐版本提交、合并提交、标签、发布日期、验证和已知问题
6. 更新 `docs/releases/README.md` 的版本索引

示例：

```bash
cp docs/releases/unreleased.md docs/releases/v3.9.0.md
```

### 2. 构建和验证

```bash
swift build -c release
./scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 "dist/漫域音乐.app"
```

### 3. 提交发布准备

```bash
git add VERSION CHANGELOG.md README.md docs scripts Sources Resources
git commit -m "release: 漫域音乐 vX.Y.Z"
```

### 4. 创建注释标签

```bash
git tag -a vX.Y.Z -m "漫域音乐 vX.Y.Z"
```

### 5. 推送并核验

```bash
git push origin main
git push origin vX.Y.Z
git ls-remote origin refs/heads/main refs/tags/vX.Y.Z
```

标签、`VERSION`、`CHANGELOG.md` 和 `docs/releases/vX.Y.Z.md` 中的版本号必须一致。

## 结束语规则

- 每次功能完成或成功合并后，最终回复必须单独一行以“完成了喵，恭喜主人喵！”结束。
- 普通问答、状态检查、代码审查、规划和未完成工作不使用该结束语。

### 6. 重置未发布记录

正式发布完成后，将 `docs/releases/unreleased.md` 重置为下一版本的空记录，但不得删除或重写已经生成的 `vX.Y.Z.md`。

## 回退与恢复

查看历史：

```bash
git log --oneline --decorate --graph
```

撤销最近一次提交但保留修改：

```bash
git reset --soft HEAD~1
```

安全撤销已经提交的版本：

```bash
git revert <commit>
```

临时查看旧版本：

```bash
git switch --detach v3.8.0
```

从旧版本创建恢复分支：

```bash
git switch -c codex/restore-v3.8 v3.8.0
```

除非已确认不需要当前修改，否则不要使用 `git reset --hard`。
