# Windows 本地构建

仓库内的安卓源码、原生库、Debian / Node.js / Android 适配层与 DSH 程序一起构建。材料以根目录 `materials.lock.json` 为准；脚本不联网下载运行环境。

## 开始构建

1. 安装 JDK 21 和 Android SDK（Android API 36、SDK Build-Tools；可用 Android Studio 安装并接受 SDK 许可）。现有工具会自动识别。
2. 双击仓库根目录 `Build.cmd`。第一次编译需要联网下载 Gradle 和 Maven 依赖。
3. 成功后，安装包在 `dist\DSHBox-v1.3.1-local.apk`。窗口会显示成功或失败，并停留等待按键。

命令行也可以运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1 -NoPause
```

只还原并核对材料，不编译、不要求 JDK / SDK：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1 -VerifyOnly -NoPause
```

已有完整 Gradle、依赖和 SDK 缓存时离线构建：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1 -Offline -NoPause
```

`Build.cmd` 同样接受这些参数；传 `-NoPause` 可关闭末尾等待。`-Offline` 会先检查当前 wrapper URL 对应的 Gradle 缓存，再传入 Gradle 的 `--offline`；依赖未缓存时会失败，不会下载补齐。请提前安装 Android 平台和构建工具，以免 SDK 缺失。

## 脚本自动完成的事

- 流式核对 lock 中每个材料的字节数和 SHA-256；完整文件正确就直接使用。
- 若大文件缺失或损坏，按 lock 指定顺序校验本地分块，流式合并到临时文件，确认最终 SHA-256 正确后原子替换。
- 缺少无分块的材料、分块损坏或校验失败时明确报错。脚本不会从网络获取运行环境。
- 优先寻找 JDK 21；支持此 Gradle 版本可运行的 JDK 17–23。搜索 `JAVA_HOME`、`D:\AllTools\Java`、常见 Java 安装目录、Android Studio 的 `jbr` 和 `PATH`。
- 从 `local.properties`、`ANDROID_HOME`、`ANDROID_SDK_ROOT` 和 `%LOCALAPPDATA%\Android\Sdk` 寻找 SDK。仅更新本地 `local.properties` 的 `sdk.dir`，保留其余配置。
- 调用 `gradlew.bat :app:assembleRelease`，检查退出码，再逐项验证 APK 内所有 `assets/runtime/`、`assets/dsh/` 文件与 lock 完全一致。
- 把验证后的 APK 复制到 `dist`，输出文件路径与 SHA-256。不会自动安装 APK 或连接手机、模拟器。

可以独立运行 `Restore-Materials.ps1` 还原材料。GitHub 为普通 Git 文件设置了大小上限，因此大型 `base.tar.zst` 用多个小于上限的块存进仓库；完整文件在本地重组并被 Git 忽略。下载仓库后无需再单独找环境包。

## 签名和“相同”的范围

源码仍使用上游签名逻辑：存在本地 `keystore.properties` 时使用自定义发行密钥，否则 `assembleRelease` 使用本机 debug 密钥。作者的签名私钥没有公开，所以重新构建的 APK 不会与作者成品逐字节相同，通常不能覆盖作者签名的已安装版本。

`keystore.properties`、签名私钥（例如 `.jks`、`.keystore`）、密码和本机配置只能保存在本地，不应提交到 Git。运行环境内容通过 hash 验证；界面和设备行为还需要 ARM64 Android 设备验收。单次构建成功或材料 hash 相同不能替代设备测试。
