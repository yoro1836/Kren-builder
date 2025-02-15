#!/usr/bin/env bash
set -ex

# --- Secrets Check ---
if [[ -z $CHAT_ID ]] || [[ -z $TOKEN ]] || [[ -z $GH_TOKEN ]]; then
  echo "error: please fill required secrets (CHAT_ID, TOKEN, GH_TOKEN)!"
  exit 1
fi

mkdir -p android-kernel && cd android-kernel
WORKDIR=$(pwd)
BUILDERDIR=$WORKDIR/..
source $BUILDERDIR/config.sh

# --- Telegram functions ---
upload_file() {
  local file="$1"
  chmod 777 "$file"
  curl -s -F document=@"$file" "https://api.telegram.org/bot$TOKEN/sendDocument" \
    -F chat_id="$CHAT_ID" -F "disable_web_page_preview=true" -F "parse_mode=markdown" -o /dev/null
}

send_msg() {
  local msg="$1"
  curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" -d "disable_web_page_preview=true" -d "parse_mode=markdown" -d text="$msg" -o /dev/null
}

# --- MAIN ---

# Module ZIP Name (AnyKernel 제거)
MODULE_ZIP_NAME=$(
  ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE-//g')
  echo "$ZIP_NAME" | sed 's/.zip/-modules.zip/g' | sed "s/KVER/$KERNEL_VERSION/g"
)

# Clone Kernel Source
git clone --depth=1 $KERNEL_REPO -b $KERNEL_BRANCH $WORKDIR/common

# Extract Kernel Version
cd $WORKDIR/common; KERNEL_VERSION=$(make kernelversion); cd $WORKDIR

# Toolchain Download & Setup
mkdir clang
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-$AOSP_CLANG_VERSION.tar.gz"
if [[ $USE_AOSP_CLANG == "true" ]]; then
  wget -qO clang.tar.gz "$CLANG_URL" && tar -xf clang.tar.gz -C clang/ && rm -f clang.tar.gz
elif [[ $USE_CUSTOM_CLANG == "true" ]]; then
  if [[ $CUSTOM_CLANG_SOURCE == *'.tar.'* ]]; then
    wget -q $CUSTOM_CLANG_SOURCE && tar -C clang/ -xf *.tar.* && rm -f *.tar.*
  else
    rm -rf clang && git clone $CUSTOM_CLANG_SOURCE -b $CUSTOM_CLANG_BRANCH clang --depth=1
  fi
fi
if ! echo clang/bin/* | grep -q 'aarch64-linux-gnu'; then
  git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gas/linux-x86 -b main binutils
  export PATH="$WORKDIR/clang/bin:$WORKDIR/binutils:$PATH"
else
  export PATH="$WORKDIR/clang/bin:$PATH"
fi
COMPILER_STRING=$(clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

git config --global user.email "kontol@example.com"; git config --global user.name "Your Name"

# Telegram Message (AnyKernel 제거)
send_msg "$(
cat <<EOF
*~~~ Kren CI (Modules) ~~~*
GKI: \`$GKI_VERSION\`  
Kernel: \`$KERNEL_VERSION\`  
Status: \`$STATUS\`  
Date: \`$KBUILD_BUILD_TIMESTAMP\`
Compiler: \`$COMPILER_STRING\`
EOF
)"

# Build Modules
cd common
if [[ $BUILD_KERNEL == "yes" ]]; then
  set +e; (
    make ARCH=arm64 LLVM=1 LLVM_IAS=1 O=$WORKDIR/out CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- $KERNEL_DEFCONFIG
    make -j$(nproc --all) ARCH=arm64 LLVM=1 LLVM_IAS=1 O=$WORKDIR/out CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- modules
    make ARCH=arm64 LLVM=1 LLVM_IAS=1 O=$WORKDIR/out CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- modules_install INSTALL_MOD_PATH=$WORKDIR/out # modules_install 명령어 추가
  ) 2>&1 | tee $WORKDIR/build.log; set -e
elif [[ $GENERATE_DEFCONFIG == "yes" ]]; then # GENERATE_DEFCONFIG 제거 (이미 이전 버전에서 제거됨)
  make ARCH=arm64 LLVM=1 LLVM_IAS=1 O=$WORKDIR/out CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- $KERNEL_DEFCONFIG
  mv $WORKDIR/out/.config $WORKDIR/config
  ret=$(curl -s bashupload.com -T $WORKDIR/config); send_msg "$ret"; exit 0 # config upload 제거 (이미 이전 버전에서 제거됨)
fi
cd $WORKDIR

send_msg "✅ Module build success! Collecting & uploading module files..."

# Find and Upload Modules
declare -a module_files=()
find "$WORKDIR/out/lib/modules/$KERNELRELEASE/kernel" -name "*.ko" -print0 | while IFS= read -r -d $'\0' module_file; do
  module_files+=("$module_file")
done

if [[ ${#module_files[@]} -gt 0 ]]; then
  send_msg "✅ Found ${#module_files[@]} kernel modules. Zipping and uploading artifacts..." # 메시지 수정
  # Zipping Modules (AnyKernel 완전 제거)
  zip -r9 "$MODULE_ZIP_NAME" "${module_files[@]}" -x LICENSE # 모듈 파일 직접 ZIP
  cd rel || cd $WORKDIR # 릴리즈 저장소로 이동 (rel 디렉토리 없으면 WORKDIR 유지)
  for release_file in "$WORKDIR"/*.zip; do # *.zip 파일만 업로드
    gh release upload "$TAG" "$release_file" || { echo "❌ Module artifact upload failed: $release_file" && exit 1; }
    sleep 2
  done
  cd "$WORKDIR"; send_msg "✅ Kernel module artifacts uploaded!"
else
  send_msg "⚠️ No kernel module files to upload."
fi


# GitHub Release (AnyKernel 제거, 메시지 간결화)
TAG="$BUILD_DATE"
RELEASE_MESSAGE="$MODULE_ZIP_NAME (Modules)"
if [[ "$STATUS" == "STABLE" ]]; then
  URL="$GKI_RELEASES_REPO/releases/$TAG"
else
  URL="$GKI_RELEASES_REPO/releases/download/$TAG/$MODULE_ZIP_NAME"
fi
GITHUB_USERNAME=$(echo "$GKI_RELEASES_REPO" | awk -F'https://github.com/' '{print $2}' | awk -F'/' '{print $1}')
REPO_NAME=$(echo "$GKI_RELEASES_REPO" | awk -F'https://github.com/' '{print $2}' | awk -F'/' '{print $2}')

git clone --depth=1 "https://${GITHUB_USERNAME}:${GH_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git" rel || { echo "❌ Failed to clone GKI releases repo" && exit 1; }
cd rel || exit 1
gh release create "$TAG" -t "$RELEASE_MESSAGE" || { echo "❌ Failed to create release $TAG" && exit 1; }
sleep 2
for release_file in "$WORKDIR"/*.zip; do # *.zip 파일만 업로드
  gh release upload "$TAG" "$release_file" || { echo "❌ Failed to upload $release_file" && exit 1; }
  sleep 2
done

send_msg "📦 [$RELEASE_MESSAGE]($URL)"
exit 0
