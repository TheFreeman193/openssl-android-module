#!/usr/bin/env bash

showUsage() {
    echo 'Usage: build-openssl.sh [-n] [-i API] [-a ARCH] [BUILD_OPTIONS]

Options:
  -i, --api      Target Android API (SDK level) (must be supported by NDK)
  -a, --arch     Target architecture/ABI (arm64|arm64-v8a|arm|armeabi|armeabi-v7a|x86|x86_64|riscv64|mips|mips64)
  -n, --noop     Show build configuration only
  BUILD_OPTIONS  Override build options passed to src/Configure
                 Defaults to: no-shared no-engine no-tests no-capieng

Notes:
    - The "arm" arch defaults to ARMv7-A from NDK r16 and ARMv5TE beforehand
    - The "arm64" arch defaults to ARMv8-A
    - The "armeabi" arch forces ARMv5TE (only available up to NDK r16)
    - The "armeabi-v7a" arch forces ARMv7-A (available from NDK r4)
    - The "arm64-v8a" arch forces ARMv7-A (available from NDK r10)
    - The "x86_64" arch is available from NDK r10
    - The "x86" arch is available from NDK r6
    - The "mips" arch is available only from NDK r8 to r16
    - The "mips64" arch is available only from NDK r10 to r16
    - The "riscv64" arch is available from NDK r27

    You can force a specific 32-bit ARM architecture with "-a arm" plus additional BUILD_OPTIONS:
        -D__ARM_ARCH__=7 -march=armv7-a -mcpu=cortex-a15              # ARMv7-A targeting Cortex-A15 CPU
        -D__ARM_ARCH__=7 -march=armv7-a -mfloat-abi=softfp -mfpu=neon # ARMv7-A, soft FP via NEON/VFPv3
        -D__ARM_ARCH__=7 -march=armv7-a -mhard-float                  # ARMv7-A, hard FP
        -D__ARM_ARCH__=5 -march=armv5te                               # ARMv5TE

    You can force a specific 64-bit ARM architecture with "-a arm64" plus additional BUILD_OPTIONS:
        -D__ARM_ARCH__=9 -march=armv9-a                               # ARMv9-A
    
    This script assumes a 64-bit Linux distro with Perl and dependencies required by the NDK.
    On Windows, you may use WSL2 provided the distro can access the Git repo and NDK (either via
    interop or by having both in the WSL filesystem). MinGW* is unlikely to work due to Windows
    command length limits.

Examples:
    export ANDROID_NDK_ROOT=~/Android/Sdk/ndk/29.0.14206865
    ./build-openssl.sh
        - Builds for ARM64 and latest API with NDK r29 from Android Studio

    export ANDROID_NDK_ROOT=/mnt/c/NdkLinux/android-ndk-r27d
    /mnt/c/openssl-android-module/build-openssl.sh -i 32 -a armeabi-v7a
        - Builds for ARMv7-A targeting API 32 with NDK r27d LTS on WSL
        - Interop enabled
        - Linux NDK r27d downloaded/extracted at C:\NdkLinux\android-ndk-r27d
        - openssl-android-module Git repo at C:\openssl-android-module

    pwsh -f ./GetNDK/Get-NDK.ps1 -Version 16 -NdkDir ~/ndk-old
    export ANDROID_NDK_ROOT=~/ndk-old/Linux64/16
    ./build-openssl.sh -a arm -D__ARM_ARCH__=5 -march=armv5te
        - Builds for ARMv5TE with highest available API (27) for the last NDK that supports it (r16b)
        - Uses Get-NDK.ps1 from GetNDK submodule to download NDK r16b
'
    exit 0
}

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
WHITE='\033[1;37m'
DEFAULT='\033[0m'

ndkPath=;
if [ -n "$ANDROID_NDK_ROOT" ] && [ -f "$ANDROID_NDK_ROOT/source.properties" ]; then
    ndkPath="$ANDROID_NDK_ROOT"
elif [ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ]; then
    if [ -d "$ANDROID_NDK_HOME/ndk" ]; then
        latestApiNdk="$(ls "$ANDROID_NDK_HOME/ndk" | grep '^[1-3][0-9]\|^[1-9]' | sort -V | tail -n1)"
        [ -n "$latestApiNdk" ] && [ -f "$ANDROID_NDK_HOME/ndk/$latestApiNdk/source.properties" ] &&
            ndkPath="$ANDROID_NDK_HOME/ndk/$latestApiNdk"
    fi
    [ -z "$ndkPath" ] && [ -f "$ANDROID_NDK_HOME/ndk-bundle/source.properties" ] && ndkPath="$ANDROID_NDK_HOME/ndk-bundle"
fi
ndkRevision=;
opts=;
osslArch=;
osslPath=;
apiLevel=highest
arch="arm64-v8a"
SIMULATE=;
while [ $# -gt 0 ]; do
    case "$1" in
        -h|-\?|\?|--help|help)
            showUsage; exit 0
        ;;
        --noop|-n|-[ai]*n)
            SIMULATE=1; shift; continue
        ;;
        --api|--sdk|-i|-[an]*i)
            apiLevel="$(echo -e "$2" | sed 's/[^[:alnum:]_\-]//g' | tr 'A-Z' 'a-z')"
            shift; shift; continue
        ;;
        --arch|--abi|-a|-[in]*a)
            arch="$(echo -e "$2" | sed 's/[^[:alnum:]_\-]//g' | tr 'A-Z' 'a-z')"
            shift; shift; continue
        ;;
        *)
            newopt="$(printf '%s' "$1" | tr -d '\b\n\r\t\f\v')"
            if [ -n "$newopt" ] && printf '%s' "$newopt" | grep -qv '[;|&\\()]'; then
                opts="$(printf '%s' "$opts $newopt" | sed 's/  \+/ /g;s/^ //;s/ $//')"
                shift; continue
            fi
            echo -e "${YELLOW}WARNING: Invalid build option '$1' ignored$DEFAULT"
            shift; continue
        ;;
    esac
done

[ -z "$opts" ] && opts="no-shared no-engine no-tests no-capieng"

[ -z "$ndkPath" ] && echo -e "${RED}ERROR: \$ANDROID_NDK_ROOT must be set to an Android NDK (the path with source.properties)$DEFAULT" && exit 1
[ ! -f "$ndkPath/source.properties" ] && echo -e "${RED}ERROR: Invalid NDK path: '$ndkPath'$DEFAULT" && exit 1

ndkRevision="$(grep '^Pkg.Revision \?= \?[0-9.]\+$' $ndkPath/source.properties | cut -d'=' -f2 | tr -d ' ' | cut -d'.' -f1)"
if echo -e "$ndkRevision" | grep -qv '^[0-9]\+$' || [ "$ndkRevision" -lt 1 ]; then
    echo -e "${RED}ERROR: Unknown NDK revision: '$ndkRevision'$DEFAULT"
    exit 1
fi

if [ -f "$ndkPath/meta/platforms.json" ]; then
    apiHighest="$(grep '"max": \?[0-9]\+' $ndkPath/meta/platforms.json | tr -d ' ,' | cut -d':' -f2)"
    apiLowest="$(grep '"min": \?[0-9]\+' $ndkPath/meta/platforms.json | tr -d ' ,' | cut -d':' -f2)"
elif [ -d "$ndkPath/platforms" ]; then
    apiHighest="$(ls "$ndkPath/platforms" | sed 's/android-//ig' | sort -V | tail -n1)"
    apiLowest="$(ls "$ndkPath/platforms" | sed 's/android-//ig' | sort -V | head -n1)"
fi
echo -e "$apiLowest-$apiHighest" | grep -qv '^[0-9]\+-[0-9]\+$' && echo -e "${RED}ERROR: Unable to determine available APIs!$DEFAULT" && exit 2


case "$apiLevel" in
    *highest*) apiLevel=$apiHighest;;
    *lowest*) apiLevel=$apiLowest;;
    [3-9]|[1-9][0-9])
        [ "$apiLevel" -lt "$apiLowest" ] || [ "$apiLevel" -gt "$apiHighest" ] &&
            echo -e "${RED}ERROR: Target API level '$apiLevel' is not supported by this NDK. Supported: $apiLowest-$apiHighest$DEFAULT" && exit 2
    ;;
    *) echo -e "${RED}ERROR: Invalid API level '$apiLevel' specified!$DEFAULT" && exit 2;;
esac

case "$arch" in
    armeabi|armv5|armv5te)
        [ "$ndkRevision" -gt 16 ] && echo -e "${RED}ERROR: armeabi (ARMv5TE) is only available up to NDK r16!$DEFAULT" && exit 3
        osslArch=arm
    ;;
    armeabi-v7a|armv7|armv7a|armeabiv7a)
        [ "$ndkRevision" -lt 4 ] && echo -e "${RED}ERROR: armeabi-v7a (ARMv7-A) is only available from NDK r4!$DEFAULT" && exit 3
        osslArch=arm
        [ "$ndkRevision" -lt 17 ] && opts="$opts -D__ARM_ARCH__=7 -march=armv7-a"
    ;;
    riscv|riscv64|risc)
        [ "$ndkRevision" -lt 27 ] && echo -e "${RED}ERROR: riscv64 (RISC-V) is only available from NDK r27!$DEFAULT" && exit 3
        osslArch=riscv64
    ;;
    x86-64|x64|amd64|x86_64|x8664)
        [ "$ndkRevision" -lt 10 ] && echo -e "${RED}ERROR: x86_64 is only available from NDK r10!$DEFAULT" && exit 3
        osslArch=x86_64
    ;;
    x86|x32|i[3-7]86)
        [ "$ndkRevision" -lt 6 ] && echo -e "${RED}ERROR: x86 is only available from NDK r6!$DEFAULT" && exit 3
        osslArch=x86
    ;;
    arm64-v8a|armv8|armv8a|arm64v8a|arm64)
        [ "$ndkRevision" -lt 10 ] && echo -e "${RED}ERROR: 64-bit ARM is only available from NDK r10!$DEFAULT" && exit 3
        osslArch=arm64
    ;;
    mips|mips32)
        [ "$ndkRevision" -lt 8 ] || [ "$ndkRevision" -gt 16 ] &&
            echo -e "${RED}ERROR: mips (MIPS 32-bit) is only available from NDK r8 to r16!$DEFAULT" && exit 3
        osslArch=mips
    ;;
    mips64)
        [ "$ndkRevision" -lt 10 ] || [ "$ndkRevision" -gt 16 ] &&
            echo -e "${RED}ERROR: mips64 (MIPS 64-bit) is only available from NDK r10 to r16!$DEFAULT" && exit 3
        osslArch=mips64
    ;;
    arm) osslArch=arm;;
    *) echo -e "${RED}ERROR: Unknown arch '$arch'!$DEFAULT" && showUsage && exit 3;;
esac

case "$0" in
  *.sh) SCRIPT_ROOT="$(readlink -f "$0" | xargs dirname)";;
  *) SCRIPT_ROOT="$(lsof -p $$ 2>/dev/null | grep -o '/.*build-openssl.sh$' | xargs readlink -f | xargs dirname)";;
esac;

PATH="$ndkPath/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
outPath="$SCRIPT_ROOT/out/API${apiLevel}_NDK$ndkRevision/$arch"
buildPath="$SCRIPT_ROOT/build"
NEED_CLEAN=;

echo -e "
------------------------------------------------------------------------------------------------------------------------
${WHITE}Build config:$DEFAULT      NDK=$ndkRevision API=$apiLevel ABI=$arch NDK_PATH=$ndkPath PATH[0]=$(echo "$PATH" | cut -d':' -f1)
${WHITE}Build path:$DEFAULT        $buildPath
${WHITE}Output path:$DEFAULT       $outPath
${WHITE}Configure command:$DEFAULT perl $SCRIPT_ROOT/src/Configure android-$osslArch -D__ANDROID_API__=$apiLevel $opts
${WHITE}Build command:$DEFAULT     make
------------------------------------------------------------------------------------------------------------------------
"

[ -n "$SIMULATE" ] && exit 0

[ -d "$buildPath" ] || mkdir -p "$buildPath" || exit 4
oldPwd="$PWD"
cd "$buildPath"

if [ -f "$buildPath/apps/lib/libapps-lib-app_libctx.o" ]; then
    echo -e "${WHITE}Clean previous build...$DEFAULT"
    make clean; [ $? -ne 0 ] && cd "$oldPwd" && exit 5
fi

echo -e "${WHITE}Configure with Perl...$DEFAULT"
perl $SCRIPT_ROOT/src/Configure android-$osslArch -D__ANDROID_API__=$apiLevel $opts
[ $? -ne 0 ] && cd "$oldPwd" && exit 6

echo -e "${WHITE}Build with make...$DEFAULT"
make; [ $? -ne 0 ] && cd "$oldPwd" && exit 7
cd "$oldPwd"

echo -e "${WHITE}Copy OpenSSL binary and default config...$DEFAULT"
[ -d "$outPath" ] || mkdir -p "$outPath" || exit 8
cp -ft "$outPath" "$buildPath/apps/openssl" || exit 9
if [ ! -f "$outPath/../openssl.cnf" ] || [ ! "$(sha1sum "$outPath/../openssl.cnf" | cut -d' ' -f1)" = "$(sha1sum "$SCRIPT_ROOT/src/apps/openssl.cnf" | cut -d' ' -f1)" ]; then
    cp -ft "$outPath/../" "$SCRIPT_ROOT/src/apps/openssl.cnf" || exit 9
fi

echo "ABI=$arch
NDK_MAJOR=$ndkRevision
TARGET_API=$apiLevel
BUILD_PROFILE=android-$osslArch
OPTIONS=$opts
openssl_checksum=$(sha1sum "$outPath/openssl" | cut -d' ' -f1)
" > "$outPath/build_info.txt"

echo "NDK_MAJOR=$ndkRevision
TARGET_API=$apiLevel
ABIS=$((cd "$outPath" && ls -Cd */) | sed 's/ \+/ /g;s,/,,g')
" > "$outPath/../builds_info.txt"

echo -e "${GREEN}Build completed.$DEFAULT"
