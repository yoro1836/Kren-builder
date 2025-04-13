#!/usr/bin/env bash

# Kernel name
KERNEL_NAME="Zero"

# GKI Version
GKI_VERSION="android12-5.10"

# Build variables
export TZ="Asia/Seoul"
export KBUILD_BUILD_USER="Yoro1836"
export KBUILD_BUILD_HOST="$KERNEL_NAME"
export KBUILD_BUILD_TIMESTAMP=$(date)

# AnyKernel variables
ANYKERNEL_REPO="https://github.com/yoro1836/Anykernel"
ANYKERNEL_BRANCH="main"

# Kernel
KERNEL_REPO="https://github.com/yoro1836/zero_kernel"
KERNEL_BRANCH="S908EXXUBEXK5"
KERNEL_DEFCONFIG="zero_defconfig"
DEFCONFIG_FILE="$workdir/common/arch/arm64/configs/$KERNEL_DEFCONFIG"

# Defconfigs would be merged in the compiling processes
DEFCONFIGS_EXAMPLE="
vendor/xiaomi.config
vendor/gold.config
"
DEFCONFIGS="
" # Leave this empty if you don't need to merge any configs

# Releases repository
GKI_RELEASES_REPO="https://github.com/yoro1836/zero_kernel"

# AOSP Clang
USE_AOSP_CLANG="true"
AOSP_CLANG_SOURCE="r547379" # Should be version number or direct link to clang tarball

# Custom clang
USE_CUSTOM_CLANG="false"
CUSTOM_CLANG_SOURCE="https://github.com/ZyCromerZ/Clang/releases/download/21.0.0git-20250412-release/Clang-21.0.0git-20250412.tar.gz"
CUSTOM_CLANG_BRANCH=""

# Zip name
BUILD_DATE=$(date -d "$KBUILD_BUILD_TIMESTAMP" +"%Y-%m-%d-%H%M")
ZIP_NAME="$KERNEL_NAME-KVER-VARIANT.zip"
# Note: KVER and VARIANT are placeholder and they will be changed in the build.sh script.
