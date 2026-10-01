# KidGuard 定制版 RustDesk — 源码改造与打包要点

> 适用基线：**RustDesk 1.5.0**（源码快照 `D:\www\rustdesk`，已补齐 hbb_common submodule）。
> 目标：① 远端免确认直接控制；② 开机自动待连接。产物在 `dist\`。
> 设备端一次性设置说明见 `dist\SETUP.md`。

---

## 一、源码改造点（升级版本后需重新核对/重打的补丁）

全部补丁在源码里以注释 `KidGuard customization` 标记，`grep -rn "KidGuard customization"` 可列出全部位置。

### 补丁 1：连接免确认（Rust 层，核心）

**文件**：`src/server/connection.rs`
**位置**：`handle_login()` 中 approve-mode 分支（约 2994 行起，原"Click 模式无密码 → 弹确认框"的路径）
**改法**：Android/iOS 受控端跳过确认，直接走 `send_logon_response_and_keep_alive()` 完成授权：

```rust
// KidGuard customization: unattended access on mobile.
#[cfg(any(target_os = "android", target_os = "ios"))]
{
    if !self.send_logon_response_and_keep_alive().await {
        return false;
    }
    self.try_start_cm(lr.my_id, lr.my_name, self.authorized);
    return true;
}
#[cfg(not(any(target_os = "android", target_os = "ios")))]
{
    self.try_start_cm(lr.my_id, lr.my_name, false);
    if hbb_common::get_version_number(&lr.version) >= hbb_common::get_version_number("1.2.0") {
        self.send_login_error(crate::client::LOGIN_MSG_NO_PASSWORD_ACCESS).await;
    }
    return true;
}
```

- 只对 `cfg(android/ios)` 生效，桌面端行为不变。
- 设置了永久密码时走密码自动授权通道（上游原逻辑），本补丁覆盖的是"无密码/Click 模式"路径，两条路都不弹框。

### 补丁 2：录屏授权弹窗自动点击（无障碍服务）

**文件**：`flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/InputService.kt`
**三处改动**：

1. companion object 加布防标记（75 行附近）：
```kotlin
// KidGuard customization: while this is armed, the consent dialog for
// MediaProjection is accepted automatically (unattended access).
@Volatile
private var projectionDialogUntil = 0L

fun onProjectionDialogExpected() {
    projectionDialogUntil = SystemClock.uptimeMillis() + 15_000L
}
```

2. `onAccessibilityEvent()`（原本是空方法）挂接事件：
```kotlin
override fun onAccessibilityEvent(event: AccessibilityEvent) {
    if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
        maybeAutoAcceptMediaProjection()
    }
}
```

3. 新增 `maybeAutoAcceptMediaProjection()`：布防后 15 秒内，遍历窗口找"整个屏幕/Entire screen"单选 + "立即开始/Start now"等按钮（中英文都匹配），`clickNode()` 先试 ACTION_CLICK、失败走 dispatchGesture 坐标点击（API<24 已跳过）。
   同时 `onServiceConnected()` 里补设了 `info.eventTypes = TYPE_WINDOW_STATE_CHANGED` 和 `feedbackType`，否则事件收不到。

**为什么需要**：安卓不允许应用静默跳过 MediaProjection 授权弹窗（系统硬限制），开机自启后服务拉起必然弹一次。本补丁用无障碍服务自动替点，实现零接触。

### 补丁 3：弹窗前布防（Kotlin）

**文件**：`flutter/android/app/src/main/kotlin/com/carriez/flutter_hbb/MainService.kt`
**位置**：`requestMediaProjection()`（约 380 行），`startActivity(intent)` 前加一行：

```kotlin
// KidGuard customization: let InputService auto-accept the consent dialog.
InputService.onProjectionDialogExpected()
startActivity(intent)
```

### 无需改的：开机自启

上游自带 `BootReceiver.kt` + `RECEIVE_BOOT_COMPLETED` 权限，逻辑完整。生效条件（设备端操作，见 SETUP.md）：
- 设置 → 增强 → "开机自启动" 打开（会写 `KEY_START_ON_BOOT_OPT`）
- 必须同时授予 **忽略电池优化** + **显示悬浮窗** 两个权限，缺一个开机广播就被拒

### 签名配置

- keystore：`D:\www\rustdesk\android-release-key.jks`（alias `rustdesk`，store/key 密码 `kidguard2026`，JDK17 keytool 生成，有效期 30 年）
- `flutter/android/key.properties` 已指向它（**不入库**，换机器要重建）
- 官方 CI 用 `sed signingConfigs.release→debug` 的那步不需要，gradle 直接读 key.properties

---

## 二、构建环境（本机已装好，路径备忘）

| 组件 | 版本 | 路径 |
|---|---|---|
| Flutter | 3.24.5 stable（打了 `.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff`） | `D:\dev\rustdesk-build\flutter3245` |
| Rust | 1.75.0，host `x86_64-pc-windows-gnu` + targets：aarch64/armv7/x86_64-linux-android + rustfmt | `C:\Users\Administrator\.cargo` |
| NDK | r28c（CI 同版） | `D:\dev\rustdesk-build\android-ndk-r28c` |
| vcpkg | baseline `9e593bb1`（CI 同 commit） | `D:\dev\vcpkg` |
| cargo-ndk | **3.1.2 补丁版**（见踩坑③，普通版装不上） | 源 `D:\dev\cargo-ndk-patched` |
| VS BuildTools | 2022，VC++ 工具集（vcpkg host 构建必需） | `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools` |
| LLVM | libclang（bindgen 用） | `C:\Program Files\LLVM` |
| JDK | 17 | `D:\dev\jdk17` |
| Android SDK | 复用 KidGuard 的 | `D:\www\KidGuard\.android-build\sdk`（含 android-36） |
| gradle | wrapper 8.11.1，distributionUrl 已改腾讯镜像 | `flutter\android\gradle\wrapper` |

**vcpkg 依赖最小集**（`vcpkg.json` 已裁剪，原版里 aom/vpx/yuv/opus/ffmpeg/host 一堆，实测 Android 端真正需要的）：
```json
cpu-features(android) / aom / libvpx / libyuv / opus / ffmpeg(android)
```

**被墙源码的镜像**（已写入全局 git config，换机器要重设）：
```bash
git config --global url."https://github.com/arthenica/libaom".insteadOf "https://aomedia.googlesource.com/aom"
git config --global url."https://github.com/webmproject/libwebm".insteadOf "https://chromium.googlesource.com/webm/libwebm"
# libyuv 直接改了 res/vcpkg/libyuv/portfile.cmake 指向本地镜像 D:\dev\mirrors\libyuv.git
```
github 抖动时用 k12 中继（k12 访问 github 稳定，本机不稳；但 k12 连不上 googlesource）。

---

## 三、打包流程

### 一键脚本
`D:\www\rustdesk\build-android-local.sh` — 负责 vcpkg 依赖 + 三架构 `librustdesk.so` + `libc++_shared.so` 放进 `jniLibs`。

```bash
# 1) 原生库（首次每架构约 30-40 分钟，之后增量）
bash /d/www/rustdesk/build-android-local.sh

# 2) APK（gradle 缓存热的话约 2-9 分钟）
export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PATH=/d/dev/rustdesk-build/flutter3245/bin:/d/dev/jdk17/bin:$PATH JAVA_HOME='D:\dev\jdk17'
cd /d/www/rustdesk/flutter
flutter build apk --release                                        # universal
flutter build apk --release --split-per-abi --target-platform android-arm64,android-arm,android-x64

# 3) 产物拷到 dist/
cp build/app/outputs/flutter-apk/app-release.apk        ../dist/rustdesk-1.5.0-kidguard-universal.apk
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   ../dist/rustdesk-1.5.0-kidguard-arm64.apk
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk ../dist/rustdesk-1.5.0-kidguard-armv7.apk
cp build/app/outputs/flutter-apk/app-x86_64-release.apk      ../dist/rustdesk-1.5.0-kidguard-x86_64.apk
```

产物：arm64 ≈29MB、armv7 ≈28MB、x86_64 ≈30MB、universal ≈80MB。签名校验：
```bash
/d/www/KidGuard/.android-build/sdk/build-tools/34.0.0/apksigner.bat verify --print-certs dist/xxx.apk
```

**关键结构**：vcpkg manifest 模式同一时刻只保留最后一个 triplet 的安装目录，所以脚本必须**按架构交替**执行（vcpkg 装依赖 → cargo 编该架构 → 下一个架构），二进制缓存让 vcpkg 每轮秒恢复。上游 CI 没这个问题是因为它每架构一个独立 job。

---

## 四、Windows 宿主踩坑（每个都吃过亏，升级工具链前先读）

1. **openssl-sys 要完整 perl**：vendored OpenSSL 的 Configure 需要 `Locale::Maketext::Simple` 等模块，Git Bash 自带 perl 没有 → PATH 首位放 vcpkg 自带的 msys2：`/d/dev/vcpkg/downloads/tools/msys2/<hash>/usr/bin`（脚本里已写死 hash，vcpkg 目录变动要改）。注意 Strawberry Perl（MSWin32）会被 OpenSSL 直接拒绝（"doesn't produce Unix like paths"）。

2. **cargo-ndk 的 CC 是反斜杠路径**：openssl 的 Makefile 经 `/bin/sh` 调 CC 时 `D:\...\cc.exe` 被吃成 `D:www...` → command not found。**已打补丁重装 cargo-ndk**（`D:\dev\cargo-ndk-patched`，`cargo install --path . --locked --force`）：CC/CXX/AR/RANLIB 直接指原生 `clang.exe`/`clang++.exe`/`llvm-ar.exe`/`llvm-ranlib.exe`（正斜杠）。重装必须带 `--locked`，否则依赖解析到 edition2024 编不过。

3. **msys2 撕引号**：sh 调原生 clang 时，`-DOPENSSLDIR="\"/usr/local/ssl\""` 的引号被 argv 二次解析吃掉 → `expected expression`。脚本里 `export MSYS2_ARG_CONV_EXCL='-DOPENSSLDIR;-DENGINESDIR;-DMODULESDIR'` 只豁免这三个宏，**不能设 `*` 全局禁**（否则 install 阶段 `/D/www/...` 路径不转换，llvm-ranlib 打不开）。

4. **openssl-src prefix 形式**：`sanitize_sh()` 把 `D:\www` 转成 `/D/www`（为 windows-gnu 宿主设计的），原生 llvm-ranlib 读不了 → `make install_dev` 失败。**已改 registry 源码** `openssl-src-300.5.3/src/lib.rs` 的 sanitize_sh 保留 `D:/www` 形式。registry 改动 cargo 不感知，要 `rm -rf target/*/build/openssl-sys-* target/*/.fingerprint/openssl-sys-* target/*/deps/libopenssl_src*` 强制重编。

5. **cc crate 的裸 --target**：cc 会追加无 API 号的 `--target=aarch64-linux-android`（排在包装器 api21 之后，后者生效），NDK r28 下裸 target 默认最新 API → libc++ 头文件引用 `pthread_cond_clockwait`（API30+）→ webm-sys 编译失败。脚本用 `env CFLAGS_aarch64-linux-android=--target=aarch64-linux-android21 ...`（**追加在后，后者生效**）锁 API21，三架构都要。bash 变量名不允许连字符，必须走 `/usr/bin/env $envargs cargo ndk ...`。

6. **上游 build.rs 的宿主/目标混淆 bug**（只在 Windows 宿主暴露，Linux CI 没事）：
   - `hwcodec/build.rs`（git 依赖）：`#[cfg(windows)]` 是**宿主**判断 → 给 Android 编了 win.cpp/d3d11。已改为 `if target_os == "windows"`（runtime CARGO_CFG_TARGET_OS）。
   - rustdesk 根 `build.rs`：同样问题，`build_windows()` 已加 target 门控。
   - **git 依赖改文件后 cargo 不会自动重编 build script**（fingerprint 只看 rev）：要 `rm -rf target/<triple>/release/build/<pkg>-* target/<triple>/release/.fingerprint/<pkg>-*`。

7. **armv7 的 triplet 映射**：scrap/hwcodec/magnum-opus 三个 build.rs 把 arm 映射到 `arm-android`，上游靠 msys `ln -sf arm-neon-android arm-android` 兜底——Windows 上不可靠（ln 会在目录里嵌套/失败）。已把三处映射直接改为 `arm-neon-android`（hwcodec/magnum-opus 是 git 依赖，改动同第 6 条要清指纹）。

8. **杂项**：
   - FRB 代码生成（1.80.1）：`flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/macos/Runner/bridge_generated.h`，产物 4 个文件（ios/macos 的 h 要 cp），生成后 `src/bridge_generated.rs` 不存在则 cargo 必挂。
   - `hbb_common` submodule 缺失时按 tag 查 commit：`curl api.github.com/repos/rustdesk/rustdesk/contents/libs/hbb_common?ref=1.5.0` 取 sha，浅克隆后 checkout 去 .git 拷入。
   - vcpkg 下载抖动：源码 tarball 可预放 `D:\dev\vcpkg\downloads\`（文件名+SHA512 与 portfile 一致），或 k12 `curl` 后 scp。
   - `cargo build` 会连带编 `naming`/`rustdesk` 等 bin，Windows 宿主上缺 libsodium（libsodium-sys 在 windows host 永远链 mingw 预编译库）→ 脚本加 `--lib` 只编 so。
   - gradle 下载发行包走 `mirrors.cloud.tencent.com/gradle/`（wrapper properties 已改）。

---

## 五、升级 RustDesk 版本 checklist

1. 新源码放入 `D:\www\rustdesk`（保留 `.cargo/`、`res/vcpkg*`、`vcpkg.json`、`build-android-local.sh`、`flutter/android/key.properties`）
2. 补齐 hbb_common submodule（新 tag 对应 sha）
3. 重打 **补丁 1**（connection.rs，搜 `LOGIN_MSG_NO_PASSWORD_ACCESS` 定位同款分支）
4. 重打 **补丁 2/3**（InputService.kt / MainService.kt，若上游重构了无障碍服务或 MainService 结构，按"布防标记 + 空事件挂接 + 弹窗前布防"三要素重写）
5. 重打 **第 6 条**的两个 build.rs 宿主门控 + **第 7 条**的三处 triplet 映射（git 依赖记得清指纹）
6. 核对 CI workflow（`.github/workflows/flutter-build.yml`）里的 Rust/Flutter/NDK/vcpkg 版本是否变化，同步本地工具链
7. `cargo clean` 或清相关 build 目录后按第三节流程重打
8. 先在雷电模拟器上验证：免确认连接 + 重启自动待连，再铺真机

---

*2026-10-01 初版。基线 1.5.0，产物 dist\rustdesk-1.5.0-kidguard-*.apk，签名指纹 SHA-256 ab9108b9…e3db。*
