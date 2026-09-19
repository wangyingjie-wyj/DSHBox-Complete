# DSHBox 1.3.1 完整构建工程

本仓库把 DSHBox 安卓源码和该版本使用的全部应用运行材料放在一起。克隆或下载本仓库后，无须另找 Debian、Node.js 或 DSH 包，也无须手工拼目录。

上游项目：[WSK-build/DSHBox](https://github.com/WSK-build/DSHBox)，版本 [v1.3.1](https://github.com/WSK-build/DSHBox/releases/tag/v1.3.1)。这是完整构建材料的整理版本，保留上游许可证和署名。

验证状态：一键构建和 414 项单元测试通过，完整源码 ZIP 在新目录中也已重新构建成功。本机 x86 模拟器的 ARM 转译无法启动 PRoot/DSH，完整运行验收未通过。详情和证据见 `docs/VALIDATION.md`。

## Windows 一键打包

1. 将完整仓库解压到普通本地目录，例如 `D:\DSHBox-Complete`。
2. 准备 JDK 21 和 Android SDK。Android Studio 的 SDK Manager 可以安装下文列出的组件。
3. 双击根目录的 **Build.cmd**。
4. 成功后，在 **dist/DSHBox-v1.3.1-local.apk** 取得完整 APK。

脚本自动查找本机 JDK/SDK，校验全部运行材料、还原分片文件、执行 Gradle 编译，并再次检查 APK 内所有运行材料的 SHA-256。缺失材料或构建错误会明确失败。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1 -NoPause
```

仅检查材料：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1 -VerifyOnly -NoPause
```

标准 Android Studio / Gradle 构建也会在 preBuild 前检查并还原材料。仓库根目录就是可打开的 Android Gradle 工程，不需要再套一层父目录。

## 已包含的材料

| 内容 | 位置 |
|---|---|
| 完整安卓源码、资源、测试 | app/、common/、sandbox-manager/、bridge/、terminal-*/ |
| Debian、Node.js、Android 适配层及校验清单 | runtime/android-assets/runtime/ |
| DSH 0.1.5-rc.2 及校验文件 | runtime/android-assets/dsh/ |
| Debian 大层的全部分片 | runtime/chunks/ |
| PRoot、talloc、android-shmem、zstd 预编译库 | app/src/main/jniLibs/、libs/ |
| 移动端插件、link shim、离线终端软件包 | app/src/main/assets/ |
| 固定版本依赖、Gradle Wrapper | gradle/、各模块 Gradle 文件 |
| 构建脚本、环境制作脚本、文档和网站素材 | 根目录、tools/、runtime-bundle/、docs/、website/ |
| 材料哈希、来源和原版对齐记录 | materials.lock.json、docs/PROVENANCE.md |
| 原始许可证及第三方声明 | LICENSE、THIRD_PARTY_NOTICES.md |

大型 Debian 层以 48 MiB 分片随普通 Git 仓库保存；全部分片都在仓库内，不使用 Git LFS，也不依赖额外 Release 下载。构建脚本自动恢复 base.tar.zst 并验证 SHA-256。

## 电脑上的编译工具

| 工具 | 版本 |
|---|---|
| JDK | 21 推荐 |
| Gradle | 8.11.1，Wrapper 附带官方 SHA-256 |
| Android Gradle Plugin | 8.9.2 |
| Kotlin | 2.0.21 |
| Android SDK | API 36 |
| Android Build Tools | 36.0.0 |
| Android NDK | 27.0.12077973 |

JDK、Android SDK/NDK 和 Maven 编译依赖属于电脑工具及依赖缓存，没有复制用户机器上的整个 SDK 或缓存目录。首次构建会下载 Gradle、Maven 依赖和缺失 SDK 组件，需要可用网络及已接受的 SDK 许可。应用运行材料本身全部随仓库提供。

本机成功联网构建并缓存依赖后，可尝试 `Build.ps1 -Offline -NoPause`。它不承诺在尚未准备编译工具的新电脑上完全离线构建。

可用 JAVA_HOME 指定 JDK，用 ANDROID_HOME 或未提交的 local.properties 指定 SDK。机器路径、签名密钥和编译缓存不会上传。

## 签名和运行验证

没有 keystore.properties 时，上游逻辑会用本机 debug 密钥签署 release APK。长期分发请配置自己的签名密钥并单独备份，切勿提交私钥和密码。与作者签名不同的 APK 通常不能直接覆盖安装作者版本。

目标是复用同版运行材料重新构建完整 APK，不承诺与作者成品字节完全一致。运行环境是 ARM64 Linux；x86_64 安卓模拟器报告支持 ARM 转译，不等于能够执行其中的 PRoot 沙盒。

实际构建和设备运行结果见 docs/VALIDATION.md，只记录已完成的检查。GitHub Actions 仅手动触发。

## 上游材料

原始 README 保留于 docs/upstream/README.md，Git 历史保留原始源码及整合修改。正常 APK 构建使用已固定并校验的环境包；runtime-bundle/ 中的原始环境制作脚本保留作开发参考，重新拉取 Debian/npm 包可能得到不同内容。
