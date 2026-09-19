# 材料来源与变更

- 上游：`https://github.com/WSK-build/DSHBox`
- 上游版本：`v1.3.1`
- 上游 Git 提交：`a45f3384cc75312cb5defccb0dd7acb69964c864`
- 原始源码 ZIP SHA-256：`f666e7cda550e86052bb6a0609362b7d38b02ca85ce774307044964f646f507c`
- 作者发布 APK SHA-256：`92471675edded3266b80e7e2e13e367683955991cefcbba5fd78bcbdf45f5a21`

本机 APK 的 SHA-256 与 GitHub 发布 API 给出的 digest 一致。运行材料从这个已验证的完整 APK 原样提取；单独 DSH 发行包的官方 SHA-256 也与提取的 DSH 包一致。每一个材料及分片的 SHA-256 都保存在根目录 `materials.lock.json`。

完整上游 Release 元数据保存在 `docs/upstream/release-v1.3.1.json`，方便核对单独分发的运行环境 ZIP、DSH 包及 APK。

## 为完整工程所做的调整

1. 将 Gradle 的运行资源路径从仓库外改到仓库内 `runtime/android-assets`。
2. 保留 Debian、Node.js、Android 适配层、DSH 归档及其校验文件的原始字节；大型 Debian 归档用完整分片入库，构建前校验并恢复。
3. 提供 Windows 构建与材料验证入口，并让标准 Gradle `preBuild` 同样执行材料准备。
4. 固定 NDK 27.0.12077973、Build Tools 36.0.0；NDK 编号与作者 APK 的 `libtermux.so` 内编译标记对应。
5. 源码 ZIP 中两个 ABI 的 `libproot.so` 与作者 APK 不同，实际构建改用作者 APK 中的两份库；原源码版本仍在首次 Git 提交中。哈希变更见 `releaseMaterialOverrides`。
6. 移动端插件 `client.js` 代码内容相同但换行不同，复用 APK 中的原始字节以减少打包差异。
7. CI 改为手动构建完整 release APK，原网站部署改为手动，保留全部网站素材。

上述调整没有增加用户会话、手机数据或任何 API 密钥。签名密钥由构建者自行持有，未包含作者的签名私钥。

## 可重建的边界

仓库包含重新构建安卓应用所需的上游源码和固定运行材料。部分第三方组件由上游以已编译二进制提供，其出处和许可继续见 `THIRD_PARTY_NOTICES.md`。它不是从源代码重新编译全部 Debian 软件包、全部 npm 依赖或所有第三方原生库的发行工程。
