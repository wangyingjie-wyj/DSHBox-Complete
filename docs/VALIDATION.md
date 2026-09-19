# 验证记录

状态：构建验证通过；模拟器完整运行验收仍在进行，尚未上传 GitHub。

## 已完成

- 本地作者 APK SHA-256 与官方 GitHub Release digest 一致。
- 全部 9 项运行材料的 SHA-256 核对通过。
- 一键脚本的材料检查、分片恢复、损坏拒绝和 APK 材料核对已验证。
- 实际移走 166,589,858 字节的完整 Debian 层后，脚本从四个仓库分片还原成功，SHA-256 与原件一致。
- `:app:assembleRelease testDebugUnitTest` 构建成功，55 个测试套件、414 项测试全部通过，0 失败、0 错误、0 跳过。
- `Build.ps1 -NoPause` 一键入口实际执行成功，并逐项核对生成 APK 内全部 9 个运行材料。
- APK 的 v2 签名验证通过，包名 `com.dshbox.app`、版本 1.3.1（7）、minSdk 29、targetSdk 36。
- 594 个 APK ZIP 条目中 591 个与原版完全相同，包括全部 DEX 和资源；三项差异为 Git 版本元数据及两份 libtermux.so 的 GNU Build ID。两种 ABI 的 .text/.rodata 等其余 ELF 字节均相同。
- 作者原 APK 在隔离的 API 30 x86_64 模拟器上通过 ARM64 转译安装和环境解包，但 PRoot 沙盒发生 signal 11，DSH 启动未通过。该结果不能作为重建 APK 的运行验收。

## 待完成

- 重建 APK 安装、首次初始化、终端及 DSH 实际启动。
- 运行验收通过后再上传仓库并核对远端提交。
