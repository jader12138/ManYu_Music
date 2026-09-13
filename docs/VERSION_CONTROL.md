# Git 版本管理

## 当前结构

- `main`：稳定的主分支
- `codex/*`：功能开发或修复分支
- `v3.8.0`：当前稳定版本标签

## 日常开发流程

```bash
git switch main
git pull

git switch -c codex/feature-name
# 修改代码

git status
git diff
git add -A
git commit -m "feat: 添加某项功能"

git push -u origin codex/feature-name
```

功能完成后再合并到 `main`。

## 发布版本

```bash
git switch main
git pull

git add -A
git commit -m "release: v3.9.0"
git tag -a v3.9.0 -m "漫域音乐 v3.9.0"
git push origin main
git push origin --tags
```

版本号应与根目录 `VERSION` 文件保持一致。

## 绑定远程仓库

在 GitHub、Gitee 或自建 Git 服务中创建一个空仓库，不要勾选自动创建 README。

SSH 方式：

```bash
git remote add origin git@github.com:用户名/仓库名.git
git push -u origin main
git push origin --tags
```

HTTPS 方式：

```bash
git remote add origin https://github.com/用户名/仓库名.git
git push -u origin main
git push origin --tags
```

如果已经存在 `origin`：

```bash
git remote set-url origin 新的仓库地址
git remote -v
```

## 强制工作约定

- 所有功能开发必须在 `codex/*` 分支进行。
- 完成功能后主动提醒用户合并到 `main`，等待明确同意后才能合并。
- 每个功能更新都必须同步更新 `CHANGELOG.md` 和相关文档。
- 未获得明确发布同意时，不得打发布标签或推送发布版本。

## 回退方式

查看历史：

```bash
git log --oneline --decorate --graph
```

撤销最近一次提交，但保留修改：

```bash
git reset --soft HEAD~1
```

安全撤销已经提交的版本：

```bash
git revert 提交ID
```

临时查看旧版本：

```bash
git switch --detach v3.7.0
```

从旧版本创建恢复分支：

```bash
git switch -c codex/restore-v3.7 v3.7.0
```

避免直接使用 `git reset --hard`，除非已确认不需要当前未提交的修改。
