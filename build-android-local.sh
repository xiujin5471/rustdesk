#!/bin/bash
# KidGuard local RustDesk Android build (Windows host)
# vcpkg manifest mode keeps only ONE android triplet installed at a time,
# so vcpkg deps and cargo must be interleaved per-ABI (binary cache makes
# the vcpkg step fast after the first run).
set -e
export ANDROID_NDK_HOME='D:\dev\rustdesk-build\android-ndk-r28c'
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export VCPKG_ROOT='D:\dev\vcpkg'
export JAVA_HOME='D:\dev\jdk17'
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PATH=/d/dev/vcpkg/downloads/tools/msys2/e2658da9dc9ffbb3/usr/bin:/c/Users/Administrator/.cargo/bin:/d/dev/rustdesk-build/flutter3245/bin:$PATH
export LC_ALL=C
unset PERL
# Stop msys2 sh from rewriting POSIX-looking args (e.g. -DOPENSSLDIR="/usr/local/ssl")
# when spawning native compilers; the rewrite mangles quotes and paths. Exclude only
# the openssl -D defines — install-step paths like /D/www/... must still convert.
export MSYS2_ARG_CONV_EXCL='-DOPENSSLDIR;-DENGINESDIR;-DMODULESDIR'
export MSYS_NO_PATHCONV=1
# openssl-sys reads uppercase-underscore CC/AR variants which cargo-ndk does not
# set; give it sh-safe forward-slash paths (backslash paths break in Makefile sh).
NDKBIN_WIN="D:/dev/rustdesk-build/android-ndk-r28c/toolchains/llvm/prebuilt/windows-x86_64/bin"
WRAP="D:/www/rustdesk/target/.cargo-ndk-3.1.2"
export CC_AARCH64_LINUX_ANDROID="$WRAP/cc.exe" CXX_AARCH64_LINUX_ANDROID="$WRAP/cxx.exe" AR_AARCH64_LINUX_ANDROID="$WRAP/ar.exe" RANLIB_AARCH64_LINUX_ANDROID="$WRAP/ranlib.exe"
export CC_ARMV7_LINUX_ANDROIDEABI="$WRAP/cc.exe" CXX_ARMV7_LINUX_ANDROIDEABI="$WRAP/cxx.exe" AR_ARMV7_LINUX_ANDROIDEABI="$WRAP/ar.exe" RANLIB_ARMV7_LINUX_ANDROIDEABI="$WRAP/ranlib.exe"
export CC_X86_64_LINUX_ANDROID="$WRAP/cc.exe" CXX_X86_64_LINUX_ANDROID="$WRAP/cxx.exe" AR_X86_64_LINUX_ANDROID="$WRAP/ar.exe" RANLIB_X86_64_LINUX_ANDROID="$WRAP/ranlib.exe"
export AR="$NDKBIN_WIN/llvm-ar.exe" RANLIB="$NDKBIN_WIN/llvm-ranlib.exe"
# cc crate appends its own bare --target=<triple> (no API level) which overrides
# the wrapper's api-21 target and makes NDK r28 default to the newest API.
# Re-append the versioned target so it wins (later flag wins in clang).
# Bash can't export dashed names, so pass via env per cargo invocation.
envargs=$(cat <<EOF
CFLAGS_aarch64-linux-android=--target=aarch64-linux-android21
CXXFLAGS_aarch64-linux-android=--target=aarch64-linux-android21
CFLAGS_aarch64_linux_android=--target=aarch64-linux-android21
CXXFLAGS_aarch64_linux_android=--target=aarch64-linux-android21
CFLAGS_armv7-linux-androideabi=--target=armv7a-linux-androideabi21
CXXFLAGS_armv7-linux-androideabi=--target=armv7a-linux-androideabi21
CFLAGS_armv7_linux_androideabi=--target=armv7a-linux-androideabi21
CXXFLAGS_armv7_linux_androideabi=--target=armv7a-linux-androideabi21
CFLAGS_x86_64-linux-android=--target=x86_64-linux-android21
CXXFLAGS_x86_64-linux-android=--target=x86_64-linux-android21
CFLAGS_x86_64_linux_android=--target=x86_64-linux-android21
CXXFLAGS_x86_64_linux_android=--target=x86_64-linux-android21
EOF
)
export ANDROID_NDK_HOME='D:\dev\rustdesk-build\android-ndk-r28c'
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export VCPKG_ROOT='D:\dev\vcpkg'
export JAVA_HOME='D:\dev\jdk17'
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
NDK_BIN="/d/dev/rustdesk-build/android-ndk-r28c/toolchains/llvm/prebuilt/windows-x86_64/bin"
export PATH="$NDK_BIN:$PATH"

cd /d/www/rustdesk

targets=(aarch64-linux-android armv7-linux-androideabi x86_64-linux-android)
abis=(arm64-v8a armeabi-v7a x86_64)
vcpkg_abis=(arm64-v8a armeabi-v7a x86_64)
syslib=(aarch64-linux-android arm-linux-androideabi x86_64-linux-android)

for i in 0 1 2; do
  echo "=== VCPKG DEPS ${abis[$i]} ==="
  ./flutter/build_android_deps.sh "${vcpkg_abis[$i]}"

  echo "=== CARGO BUILD ${targets[$i]} ==="
  /usr/bin/env $envargs cargo ndk --platform 21 --target "${targets[$i]}" build --locked --release --lib --features flutter,hwcodec

  mkdir -p "flutter/android/app/src/main/jniLibs/${abis[$i]}"
  cp "target/${targets[$i]}/release/liblibrustdesk.so" "flutter/android/app/src/main/jniLibs/${abis[$i]}/librustdesk.so"
  cp "$NDK_BIN/../sysroot/usr/lib/${syslib[$i]}/libc++_shared.so" "flutter/android/app/src/main/jniLibs/${abis[$i]}/"
done

echo "=== ALL SO DONE ==="
ls -la flutter/android/app/src/main/jniLibs/*/
