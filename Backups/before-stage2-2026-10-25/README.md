# 下一阶段开发前备份

日期：2026-10-25（Asia/Shanghai）。当前应用：干了吗 0.2.0 / build 3。

- current-source：当前完整工程源码、测试、脚本、文档及 Xcode 工程。
- before-ui-refactor-source：主面板重构前的历史源码快照。
- ganlema-app：当前可运行应用（本机临时签名）。
- focusdock-before-rename-app：改名前的应用备份。解压后可将 FocusDock.previous 改为 FocusDock.app。
- manifest.json：文件大小和 SHA-256，用于核验。

真实 tasks.store / habits.store、原始数据库备份、个人偏好、编译缓存、凭据均未包含。原始数据库备份仍保留在本机 work/ui-refactor/user-backup-*，避免把私人任务上传 GitHub。Swift 项目继续使用原 Bundle ID 与本机数据路径。

GitHub 上传状态以实际仓库提交为准；本地生成这些文件不代表已经上传。
