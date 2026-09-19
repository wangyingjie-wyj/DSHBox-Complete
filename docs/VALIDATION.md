# 验证记录

状态：构建验证通过；本机模拟器完整运行验收未通过。用户已知晓该限制，并明确授权将完整工程和本次构建的 APK 上传 GitHub；本次发布不表示设备运行验收通过。

## 已完成

- 本地作者 APK SHA-256 与官方 GitHub Release digest 一致。
- 全部 9 项运行材料的 SHA-256 核对通过。
- 一键脚本的材料检查、分片恢复、损坏拒绝和 APK 材料核对已验证。
- 实际移走 166,589,858 字节的完整 Debian 层后，脚本从四个仓库分片还原成功，SHA-256 与原件一致。
- `:app:assembleRelease testDebugUnitTest` 构建成功，55 个测试套件、414 项测试全部通过，0 失败、0 错误、0 跳过。
- `Build.ps1 -NoPause` 一键入口实际执行成功，并逐项核对生成 APK 内全部 9 个运行材料。
- 将 Git 导出的完整源码 ZIP 解压到全新目录后，脚本从仓库分片还原 Debian 层，并通过 `Build.ps1 -Offline -NoPause` 重新构建成功；该检查使用本机已准备好的 JDK/SDK 和依赖缓存，未引用桌面原工程中的运行文件。
- APK 的 v2 签名验证通过，包名 `com.dshbox.app`、版本 1.3.1（7）、minSdk 29、targetSdk 36。
- 594 个 APK ZIP 条目中 591 个与原版完全相同，包括全部 DEX 和资源；三项差异为 Git 版本元数据及两份 libtermux.so 的 GNU Build ID。两种 ABI 的 .text/.rodata 等其余 ELF 字节均相同。
- 作者原 APK 在隔离的 API 30 x86_64 模拟器上通过 ARM64 转译安装和环境解包，但 PRoot 沙盒发生 signal 11，DSH 启动未通过。该结果不能作为重建 APK 的运行验收。

## 模拟器运行结果

| 环境 | 实际结果 |
|---|---|
| Android 11 / API 30 x86_64，强制 ARM64 转译 | 重建 APK 安装、Activity 和运行环境解包成功；PRoot signal 11，终端无可用 shell/Node，DSH 端口连接失败。作者原 APK 也有同样结果。 |
| Android 16 / API 36.1 x86_64 镜像，强制 ARM64 转译 | 安装和初始化成功；实际输入 `node --version` 后，ARM 转译器 `guest_signal_handling_arch.cc:42` 断言失败并 signal 6；没有输出 Node 版本；DSH 超过 120 秒就绪超时，3080 端口拒绝连接。 |
| 官方 API 30 ARM64 镜像，在 x86 Windows 上用 TCG 直接启动 | 内核及 Android init 曾启动，但 zygote/Windows 模拟器图形内存路径失败；系统未达到可用 ADB，不能作为 APK 运行验证。 |

失败截图和精简日志在 `validation-evidence/`。首页的状态标签不作为验收依据，必须实际确认终端命令、Node 和 DSH HTTP 服务可用。

所有模拟器均为本任务独立创建。未使用或修改用户原有 AVD 数据。

## 下一步

后续仍需在可执行 ARM64 Linux 沙盒的设备（例如 ARM64 安卓真机或受支持的 ARM64 主机模拟器）上完成运行验收。构建和静态一致性通过不能替代实际运行验证。

交付 APK：`dist/DSHBox-v1.3.1-local.apk`，SHA-256：`444f032f67ffdc2c5805f8b9d3944da336c61adcbd3f6859151c7737793f743e`。
