# GKI Version
export GKI_VERSION="android12-5.10"

# Build variables
export TZ="Asia/Seoul"
export KBUILD_BUILD_USER="Yoro1836"
export KBUILD_BUILD_HOST="Kren"
export KBUILD_BUILD_TIMESTAMP=$(date)

# AnyKernel variables
export ANYKERNEL_REPO="https://github.com/yoro1836/Anykernel"
export ANYKERNEL_BRANCH="main"

# Kernel
export KERNEL_REPO="https://github.com/yoro1836/Kren_kernel"
export KERNEL_BRANCH="S908EXXUBEXK5"
export KERNEL_DEFCONFIG="kren_defconfig"

# Releases repository
export GKI_RELEASES_REPO="https://github.com/yoro1836/Kren_kernel"

# AOSP Clang
export USE_AOSP_CLANG="false"
export AOSP_CLANG_VERSION="r547379"

# Custom clang
export USE_CUSTOM_CLANG="true"
export CUSTOM_CLANG_SOURCE="https://github.com/ZyCromerZ/Clang/releases/download/12.0.1-20230207-release/Clang-12.0.1-20230207.tar.gz"
export CUSTOM_CLANG_BRANCH=""

# Zip name
export BUILD_DATE=$(date -d "$KBUILD_BUILD_TIMESTAMP" +"%y%m%d%H%M")
export ZIP_NAME="Kren-Kerenl-$BUILD_DATE.zip"
