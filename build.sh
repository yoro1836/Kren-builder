#!/usr/bin/env bash
set -ex

ret=0
if [[ -z $CHAT_ID ]]; then
    echo "error: please fill CHAT_ID secret!"
    ((ret++))
fi

if [[ -z $TOKEN ]]; then
    echo "error: please fill TOKEN secret!"
    ((ret++))
fi

if [[ -z $GH_TOKEN ]]; then
    echo "error: please fill GH_TOKEN secret!"
    ((ret++))
fi

[[ $ret -gt 0 ]] && exit $ret

mkdir -p android-kernel && cd android-kernel

WORKDIR=$(pwd)
BUILDERDIR=$WORKDIR/..
source $BUILDERDIR/config.sh

# ------------------
# Telegram functions
# ------------------

upload_file() {
    local file="$1"

    if [[ -f $file ]]; then
        chmod 777 "$file"
    else
        echo "[ERROR] file $file doesn't exist"
        exit 1
    fi

    curl -s -F document=@"$file" "https://api.telegram.org/bot$TOKEN/sendDocument" \
        -F chat_id="$CHAT_ID" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=markdown" \
        -o /dev/null
}

send_msg() {
    local msg="$1"
    curl -s -X POST "https://api.telegram.org/bot$TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d "disable_web_page_preview=true" \
        -d "parse_mode=markdown" \
        -d text="$msg" \
        -o /dev/null
}

# ---------------
#   MAIN
# ---------------

# Add kernel variant into ZIP_NAME
if [[ $USE_KSU == "yes" ]]; then
    # ksu magic mount
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/MKSU/g')
elif [[ $USE_KSU_NEXT == "yes" ]]; then
    # ksu next
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE/KSU_NEXT/g')
else
    # vanilla
    ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/OPTIONE-//g')
fi

# Clone the kernel source
git clone --depth=1 $KERNEL_REPO -b $KERNEL_BRANCH $WORKDIR/common

# Extract kernel version
cd $WORKDIR/common
KERNEL_VERSION=$(make kernelversion)
ZIP_NAME=$(echo "$ZIP_NAME" | sed "s/KVER/$KERNEL_VERSION/g")
cd $WORKDIR

# Download Toolchains
mkdir $WORKDIR/clang
if [[ $USE_AOSP_CLANG == "true" ]]; then
    wget -qO $WORKDIR/clang.tar.gz https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-$AOSP_CLANG_VERSION.tar.gz
    tar -xf $WORKDIR/clang.tar.gz -C $WORKDIR/clang/
    rm -f $WORKDIR/clang.tar.gz
elif [[ $USE_CUSTOM_CLANG == "true" ]]; then
    if [[ $CUSTOM_CLANG_SOURCE =~ git ]]; then
        if [[ $CUSTOM_CLANG_SOURCE == *'.tar.'* ]]; then
            wget -q $CUSTOM_CLANG_SOURCE
            tar -C $WORKDIR/clang/ -xf $WORKDIR/*.tar.*
            rm -f $WORKDIR/*.tar.*
        else
            rm -rf $WORKDIR/clang
            git clone $CUSTOM_CLANG_SOURCE -b $CUSTOM_CLANG_BRANCH $WORKDIR/clang --depth=1
        fi
    else
        echo "error: Clang source other than git is not supported."
        exit 1
    fi
elif [[ $USE_AOSP_CLANG == "true" ]] && [[ $USE_CUSTOM_CLANG == "true" ]]; then
    echo "error: You have to choose one, AOSP Clang or Custom Clang!"
    exit 1
else
    echo "stfu."
    exit 1
fi

# Clone binutils if they don't exist
if ! echo $WORKDIR/clang/bin/* | grep -q 'aarch64-linux-gnu'; then
    git clone --depth=1 https://android.googlesource.com/platform/prebuilts/gas/linux-x86 -b main $WORKDIR/binutils
    export PATH="$WORKDIR/clang/bin:$WORKDIR/binutils:$PATH"
else
    export PATH="$WORKDIR/clang/bin:$PATH"
fi

# Extract clang version
COMPILER_STRING=$(clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

# KSU or KSU-Next setup
if [[ $USE_KSU_NEXT == "yes" ]]; then
    if [[ $USE_KSU_SUSFS == "yes" ]]; then
        curl -LSs https://raw.githubusercontent.com/rifsxd/KernelSU-Next/refs/heads/next/kernel/setup.sh | bash -s next-susfs
    else
        curl -LSs https://raw.githubusercontent.com/rifsxd/KernelSU-Next/refs/heads/next/kernel/setup.sh | bash -
    fi
    cd $WORKDIR/KernelSU-Next
    KSU_NEXT_VERSION=$(git describe --abbrev=0 --tags)
elif [[ $USE_KSU == "yes" ]] && [[ $USE_KSU_SUSFS == "yes" ]]; then
    if [[ $USE_KSU_SUSFS == "yes" ]]; then
        curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s susfs-v1.5.5
    else
        curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s main
    fi
elif [[ $USE_KSU == "yes" ]] || [[ $USE_KSU_NEXT == "yes" ]] && [[ $USE_KSU_SUSFS != "yes" ]]; then
    echo
    echo "error: You have to choose one, MKSU or KSUN!"
    exit 1
fi

cd $WORKDIR

git config --global user.email "kontol@example.com"
git config --global user.name "Your Name"

# SUSFS4KSU setup
 if [[ $USE_KSU == "yes" ]] || [[ $USE_KSU_NEXT == "yes" ]] && [[ $USE_KSU_SUSFS == "yes" ]]; then
    git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu -b gki-$GKI_VERSION $WORKDIR/susfs4ksu
    SUSFS_PATCHES="$WORKDIR/susfs4ksu/kernel_patches"

    if [[ $USE_KSU == "yes" ]]; then
        ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/KSU/KSUxSUSFS/g')
    elif [[ $USE_KSU_NEXT == "yes" ]]; then
       ZIP_NAME=$(echo "$ZIP_NAME" | sed 's/KSU_NEXT/KSUNxSUSFS/g')
    fi

    # Copy header files (Kernel Side)
    cd $WORKDIR/common
    cp $SUSFS_PATCHES/include/linux/* ./include/linux/
    cp $SUSFS_PATCHES/fs/* ./fs/

    # Apply patch to kernel (Kernel Side)
    cd $WORKDIR/common
    cp $SUSFS_PATCHES/50_add_susfs_in_gki-$GKI_VERSION.patch .
    patch -p1 <50_add_susfs_in_gki-$GKI_VERSION.patch || exit 1

    SUSFS_VERSION=$(grep -E '^#define SUSFS_VERSION' ./include/linux/susfs.h | cut -d' ' -f3 | sed 's/"//g')
elif [[ $USE_KSU_SUSFS == "yes" ]] && [[ $USE_KSU != "yes" ]] && [[ $USE_KSU_NEXT != "yes" ]]; then
    echo "error: You can't use SuSFS without KSU enabled!"
    exit 1
fi

cd $WORKDIR

text=$(
    cat <<EOF
*~~~ Kren CI ~~~*
*GKI Version*: \`$GKI_VERSION\`
*Kernel Version*: \`$KERNEL_VERSION\`
*Build Status*: \`$STATUS\`
*Date*: \`$KBUILD_BUILD_TIMESTAMP\`
*KSU*: \`$([[ $USE_KSU == "yes" ]] && echo "true" || echo "false")\`$([[ $USE_KSU == "yes" ]] && echo "
*KSU Version*: \`$KSU_VERSION\`")
*KSU-Next*: \`$([[ $USE_KSU_NEXT == "yes" ]] && echo "true" || echo "false")\`$([[ $USE_KSU_NEXT == "yes" ]] && echo "
*KSU-Next Version*: \`$KSU_NEXT_VERSION\`")
*SUSFS*: \`$([[ $USE_KSU_SUSFS == "yes" ]] && echo "true" || echo "false")\`$([[ $USE_KSU_SUSFS == "yes" ]] && echo "
*SUSFS Version*: \`$SUSFS_VERSION\`")
*Compiler*: \`$COMPILER_STRING\`
EOF
)

send_msg "$text"

cd $WORKDIR/common
# Build GKI
if [[ $BUILD_KERNEL == "yes" ]]; then
    set +e
    (
        make \
            ARCH=arm64 \
            LLVM=1 \
            LLVM_IAS=1 \
            O=$WORKDIR/out \
            CROSS_COMPILE=aarch64-linux-gnu- \
            CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
            $KERNEL_DEFCONFIG

        make -j$(nproc --all) \
            ARCH=arm64 \
            LLVM=1 \
            LLVM_IAS=1 \
            O=$WORKDIR/out \
            CROSS_COMPILE=aarch64-linux-gnu- \
            CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
            Image modules $([ $STATUS == "STABLE" ] && echo "Image.lz4 Image.gz")
    ) 2>&1 | tee $WORKDIR/build.log
    set -e
elif [[ $GENERATE_DEFCONFIG == "yes" ]]; then
    make \
        ARCH=arm64 \
        LLVM=1 \
        LLVM_IAS=1 \
        O=$WORKDIR/out \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
        $KERNEL_DEFCONFIG

    mv $WORKDIR/out/.config $WORKDIR/config
    ret=$(curl -s bashupload.com -T $WORKDIR/config)
    send_msg "$ret"
    exit 0
fi
cd $WORKDIR

KERNEL_IMAGE="$WORKDIR/out/arch/arm64/boot/Image"
if ! [[ -f $KERNEL_IMAGE ]]; then
    send_msg "❌ Build failed!"
    upload_file "$WORKDIR/build.log"
    exit 1
else
    send_msg "✅ Kernel build 성공! 모듈 파일 수집 및 업로드 시작..."

    # 모듈 파일 경로를 저장할 배열 선언
    declare -a module_files=()

    # kernel 디렉토리 아래에서 .ko 파일 찾아서 배열에 추가
    find "$WORKDIR/common/kernel" -name "*.ko" -print0 | while IFS= read -r -d $'\0' module_file; do
        module_files+=("$module_file")
    done

    if [[ ${#module_files[@]} -gt 0 ]]; then
        send_msg "✅ 커널 모듈 ${#module_files[@]}개 발견. 아티팩트 업로드..."
        cd "$WORKDIR/rel" || exit 1 # 릴리즈 저장소로 이동 (rel 디렉토리가 없으면 WORKDIR 에서 계속 진행)

        # 각 모듈 파일을 GitHub Release 에 아티팩트로 업로드
        for module_file in "${module_files[@]}"; do
            module_name=$(basename "$module_file")
            if ! gh release upload "$TAG" "$module_file" --name "$module_name"; then
                echo "❌ 모듈 아티팩트 업로드 실패: $module_name"
                exit 1
            fi
            sleep 1 # GitHub API 요청 간 간격 (너무 빠른 요청 방지)
        done
        cd "$WORKDIR" || exit 1 # 원래 디렉토리로 복귀
        send_msg "✅ 커널 모듈 아티팩트 업로드 완료!"
    else
        send_msg "⚠️ 업로드할 커널 모듈 파일 없음."
    fi
fi #  <--  기존 'else' 구문의 'fi'  (KERNEL_IMAGE 없을 때 실패 메시지)

    # AnyKernel Cloning 및 부트 이미지 생성 (기존 코드)
    if [[ $STATUS == "STABLE" ]]; then #  <--  'KERNEL_IMAGE'  존재할 때만 부트 이미지 생성하도록 조건 추가
        git clone --depth=1 "$ANYKERNEL_REPO" -b "$ANYKERNEL_BRANCH" $WORKDIR/anykernel

        # Clone tools
        AOSP_MIRROR=https://android.googlesource.com
        BRANCH=main-kernel-build-2024
        git clone $AOSP_MIRROR/kernel/prebuilts/build-tools -b $BRANCH --depth=1 $WORKDIR/build-tools
        git clone $AOSP_MIRROR/platform/system/tools/mkbootimg -b $BRANCH --depth=1 $WORKDIR/mkbootimg

        # Variables
        KERNEL_IMAGES=$(echo $WORKDIR/out/arch/arm64/boot/Image*)
        AVBTOOL=$WORKDIR/build-tools/linux-x86/bin/avbtool
        MKBOOTIMG=$WORKDIR/mkbootimg/mkbootimg.py
        UNPACK_BOOTIMG=$WORKDIR/mkbootimg/unpack_bootimg.py
        BOOT_SIGN_KEY_PATH=$BUILDERDIR/key/verifiedboot.pem
        BOOTIMG_NAME="${ZIP_NAME%.zip}-boot-dummy.img"

        # Function
        generate_bootimg() {
            local kernel="$1"
            local output="$2"

            # Create boot image
            $MKBOOTIMG --header_version 4 \
                --kernel "$kernel" \
                --output "$output" \
                --ramdisk out/ramdisk \
                --os_version 12.0.0 \
                --os_patch_level $(date +"%Y-%m")

            sleep 1

            # Sign the boot image
            $AVBTOOL add_hash_footer \
                --partition_name boot \
                --partition_size $((64 * 1024 * 1024)) \
                --image "$output" \
                --algorithm SHA256_RSA2048 \
                --key $BOOT_SIGN_KEY_PATH
        }

        # Prepare boot image
        mkdir -p $WORKDIR/bootimg && cd $WORKDIR/bootimg
        cp $KERNEL_IMAGES .

        # Download and unpack GKI
        wget -qO gki.zip https://dl.google.com/android/gki/gki-certified-boot-android12-5.10-2023-01_r1.zip
        unzip -q gki.zip && rm gki.zip
        $UNPACK_BOOTIMG --boot_img="$(pwd)/boot-5.10.img"
        rm "$(pwd)/boot-5.10.img"

        # Generate and sign boot images
        for format in raw lz4 gz; do

            case $format in
                raw)
                    kernel="./Image"
                    output="${BOOTIMG_NAME/dummy/raw}"
                    ;;
                lz4)
                    kernel="./Image.lz4"
                    output="${BOOTIMG_NAME/dummy/lz4}"
                    ;;
                gz)
                    kernel="./Image.gz"
                    output="${BOOTIMG_NAME/dummy/gz}"
                    ;;
            esac

            # Generate and sign
            generate_bootimg "$kernel" "$output"
            mv "$output" "$WORKDIR"
        done
        cd $WORKDIR
    fi #  <--  'if [[ $STATUS == "STABLE" ]]'  조건문 종료

    # Zipping (기존 코드)
    cd $WORKDIR/anykernel
    sed -i "s/DUMMY1/$KERNEL_VERSION/g" anykernel.sh
    sed -i "s/DATE/$BUILD_DATE/g" anykernel.sh

    if [[ $USE_KSU != "yes" ]] && [[ $USE_KSU_NEXT != "yes" ]]; then
        # not using ksu or ksu next
        sed -i "s/KSU//g" anykernel.sh
    elif [[ $USE_KSU != "yes" ]] && [[ $USE_KSU_NEXT == "yes" ]]; then
        # ksu next
        sed -i "s/KSU/KSU Next/g" anykernel.sh
    fi

    if [[ $USE_KSU_SUSFS == "yes" ]]; then
        # included ksu susfs
        sed -i "s/DUMMY2/ x SuSFS/g" anykernel.sh
    else
        # not included ksu susfs
        sed -i "s/DUMMY2//g" anykernel.sh
    fi

    cp $KERNEL_IMAGE .
    zip -r9 $ZIP_NAME ./* -x LICENSE
    mv $ZIP_NAME $WORKDIR
    cd $WORKDIR

    ## Release into GitHub (기존 코드, ZIP 파일 업로드 다시 포함)
    TAG="$BUILD_DATE"
    if [[ $STATUS == "STABLE" ]]; then
        RELEASE_MESSAGE="${ZIP_NAME%.zip}"
    else
        RELEASE_MESSAGE="$ZIP_NAME"
    fi
    if [[ $STATUS == "STABLE" ]]; then
        URL="$GKI_RELEASES_REPO/releases/$TAG"
    else
        URL="$GKI_RELEASES_REPO/releases/download/$TAG/$ZIP_NAME"
    fi
    GITHUB_USERNAME=$(echo "$GKI_RELEASES_REPO" | awk -F'https://github.com/' '{print $2}' | awk -F'/' '{print $1}')
    REPO_NAME=$(echo "$GKI_RELEASES_REPO" | awk -F'https://github.com/' '{print $2}' | awk -F'/' '{print $2}')

    # Clone repository
    git clone --depth=1 "https://${GITHUB_USERNAME}:${GH_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git" "$WORKDIR/rel" || {
        echo "❌ Failed to clone GKI releases repository"
        exit 1
    }

    cd "$WORKDIR/rel" || exit 1

    # Create release
    if ! gh release create "$TAG" -t "$RELEASE_MESSAGE"; then
        echo "❌ Failed to create release $TAG"
        exit 1
    fi

    sleep 2

    # Upload files to release (ZIP 파일 및 IMG 파일 모두 다시 업로드)
    for release_file in "$WORKDIR"/*.zip "$WORKDIR"/*.img; do
        if [[ -f $release_file ]]; then
            if ! gh release upload "$TAG" "$release_file"; then
                echo "❌ Failed to upload $release_file"
                exit 1
            fi
            sleep 2
        fi
    done

    send_msg "📦 [$RELEASE_MESSAGE]($URL)"
    exit 0
