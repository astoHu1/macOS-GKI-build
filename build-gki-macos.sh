#!/bin/sh
# SPDX-License-Identifier: MIT
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT_DIR=${OUT_DIR:-"$ROOT_DIR/out/macos-gki"}
DIST_DIR=${DIST_DIR:-"$ROOT_DIR/out/macos-gki-dist"}
OPENSSL_DIR=${OPENSSL_DIR:-/opt/homebrew/opt/openssl@3}
BREW_BIN=${BREW_BIN:-/opt/homebrew/bin}
HOST_TOOLS_DIR="$ROOT_DIR/prebuilts/build-tools/darwin-x86/bin"
MACOS_INCLUDE_DIR="$ROOT_DIR/tools/macos-kbuild/include"
MACOS_BIN_DIR="$ROOT_DIR/tools/macos-kbuild/bin"
SDKROOT=${SDKROOT:-$(xcrun --show-sdk-path)}
HOST_TARGET=${HOST_TARGET:-$(uname -m)-apple-darwin}
TARGET_TRIPLE=${TARGET_TRIPLE:-aarch64-linux-gnu}

require_exe() {
	if [ ! -x "$1" ]; then
		echo "missing executable: $1" >&2
		exit 1
	fi
}

require_file() {
	if [ ! -f "$1" ]; then
		echo "missing file: $1" >&2
		exit 1
	fi
}

detect_jobs() {
	jobs=$(sysctl -n hw.logicalcpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
	case "$jobs" in
	''|*[!0-9]*|0)
		echo 1
		;;
	*)
		echo "$jobs"
		;;
	esac
}

has_jobs_arg() {
	for arg in "$@"; do
		case "$arg" in
		-j|-j[0-9]*|--jobs|--jobs=*)
			return 0
			;;
		esac
	done
	return 1
}

ACK_CLANG_VERSION=${ACK_CLANG_VERSION:-$(sed -n 's/^CLANG_VERSION=//p' "$ROOT_DIR/common/build.config.constants" | head -n 1)}
LLVM_DIR=${LLVM_DIR:-"$ROOT_DIR/prebuilts/clang/host/darwin-x86/clang-$ACK_CLANG_VERSION"}
TARGET_CC="$LLVM_DIR/bin/clang --target=$TARGET_TRIPLE"

require_exe "$LLVM_DIR/bin/clang"
require_exe "$LLVM_DIR/bin/clang++"
require_exe "$LLVM_DIR/bin/llvm-ar"
require_file "$OPENSSL_DIR/include/openssl/opensslv.h"
require_file "$OPENSSL_DIR/lib/libcrypto.dylib"
require_file "$SDKROOT/usr/include/sys/types.h"
require_exe "$HOST_TOOLS_DIR/make"
require_exe "$HOST_TOOLS_DIR/bison"
require_exe "$HOST_TOOLS_DIR/flex"
require_exe "$BREW_BIN/gsed"
require_exe "$BREW_BIN/dtc"
require_exe "$BREW_BIN/lz4"
require_file "$MACOS_INCLUDE_DIR/elf.h"
require_file "$MACOS_INCLUDE_DIR/endian.h"

export PATH="$MACOS_BIN_DIR:$LLVM_DIR/bin:$BREW_BIN:$HOST_TOOLS_DIR:$PATH"
export MAKE="$HOST_TOOLS_DIR/make"

GKI_LOCALVERSION_SUFFIX=${GKI_LOCALVERSION_SUFFIX:-}
GKI_KERNELRELEASE=${GKI_KERNELRELEASE:-}
DEFCONFIG=${DEFCONFIG:-wonder_gki_defconfig}
FRAGMENT_CONFIG=${FRAGMENT_CONFIG:-"$ROOT_DIR/common/arch/arm64/configs/wonder.fragment"}
BASE_DEFCONFIG=${BASE_DEFCONFIG:-"$ROOT_DIR/common/arch/arm64/configs/gki_defconfig"}
ANDROID_BRANCH=${ANDROID_BRANCH:-$(sed -n 's/^BRANCH=//p' "$ROOT_DIR/common/build.config.common" | head -n 1)}
KMI_GENERATION=${KMI_GENERATION:-$(sed -n 's/^KMI_GENERATION=//p' "$ROOT_DIR/common/build.config.common" | head -n 1)}
case " ${KCFLAGS:-} " in
*" -D__ANDROID_COMMON_KERNEL__ "*) ;;
*) KCFLAGS="${KCFLAGS:-} -D__ANDROID_COMMON_KERNEL__" ;;
esac
ANDROID_RELEASE=
case "$ANDROID_BRANCH" in
android-mainline)
	ANDROID_RELEASE=mainline
	;;
android[0-9][0-9]-*)
	ANDROID_RELEASE=${ANDROID_BRANCH%%-*}
	;;
esac
if [ -n "$ANDROID_RELEASE" ]; then
	if [ -n "$KMI_GENERATION" ]; then
		case "$KMI_GENERATION" in
		*[!0-9]*)
			echo "invalid KMI_GENERATION: $KMI_GENERATION" >&2
			exit 1
			;;
		esac
		KMI_LOCALVERSION="-$ANDROID_RELEASE-$KMI_GENERATION"
	else
		KMI_LOCALVERSION="-$ANDROID_RELEASE"
	fi
	mkdir -p "$OUT_DIR"
	if [ -z "$GKI_KERNELRELEASE" ]; then
		printf '%s\n' "$KMI_LOCALVERSION" > "$OUT_DIR/localversion"
	fi
fi

[ "$#" -gt 0 ] || set -- Image.gz Image.lz4

if [ -n "${JOBS:-}" ]; then
	case "$JOBS" in
	*[!0-9]*|0)
		echo "JOBS must be a positive integer: $JOBS" >&2
		exit 1
		;;
	esac
	MAKE_JOBS_OPT="-j$JOBS"
	set -- "-j$JOBS" "$@"
else
	MAKE_JOBS_OPT="-j$(detect_jobs)"
	if ! has_jobs_arg "$@"; then
		set -- "$MAKE_JOBS_OPT" "$@"
	fi
fi

run_make() {
	"$HOST_TOOLS_DIR/make" -C "$ROOT_DIR/common" O="$OUT_DIR" \
		ARCH=arm64 \
		LLVM=1 \
		LLVM_IAS=1 \
		CC="$TARGET_CC" \
		LD="$LLVM_DIR/bin/ld.lld" \
		NM="$LLVM_DIR/bin/llvm-nm" \
		OBJCOPY="$LLVM_DIR/bin/llvm-objcopy" \
		HOSTCC="$LLVM_DIR/bin/clang" \
		HOSTCXX="$LLVM_DIR/bin/clang++" \
		HOSTLD="$LLVM_DIR/bin/clang" \
		HOSTAR="$LLVM_DIR/bin/llvm-ar" \
		HOSTCFLAGS="-target $HOST_TARGET -isysroot $SDKROOT -I$MACOS_INCLUDE_DIR -I$OPENSSL_DIR/include ${HOSTCFLAGS:-}" \
		HOSTLDFLAGS="-target $HOST_TARGET -isysroot $SDKROOT -L$OPENSSL_DIR/lib ${HOSTLDFLAGS:-}" \
		KCFLAGS="$KCFLAGS" \
		SED="$BREW_BIN/gsed" \
		DTC="$BREW_BIN/dtc" \
		LOCALVERSION="$GKI_LOCALVERSION_SUFFIX" \
		${GKI_KERNELRELEASE:+KERNELRELEASE=$GKI_KERNELRELEASE} \
		"$@"
}

prepare_defconfig() {
	require_file "$BASE_DEFCONFIG"
	require_file "$FRAGMENT_CONFIG"
	mkdir -p "$OUT_DIR"
	merged_config="$OUT_DIR/.config.merged"
	(
		cd "$ROOT_DIR/common"
			KCONFIG_CONFIG="$merged_config" \
			ARCH=arm64 \
			LLVM=1 \
			LLVM_IAS=1 \
			CC="$TARGET_CC" \
			LD="$LLVM_DIR/bin/ld.lld" \
			NM="$LLVM_DIR/bin/llvm-nm" \
			OBJCOPY="$LLVM_DIR/bin/llvm-objcopy" \
			HOSTCC="$LLVM_DIR/bin/clang" \
			HOSTCXX="$LLVM_DIR/bin/clang++" \
			HOSTLD="$LLVM_DIR/bin/clang" \
			HOSTAR="$LLVM_DIR/bin/llvm-ar" \
			HOSTCFLAGS="-target $HOST_TARGET -isysroot $SDKROOT -I$MACOS_INCLUDE_DIR -I$OPENSSL_DIR/include ${HOSTCFLAGS:-}" \
			HOSTLDFLAGS="-target $HOST_TARGET -isysroot $SDKROOT -L$OPENSSL_DIR/lib ${HOSTLDFLAGS:-}" \
			KCFLAGS="$KCFLAGS" \
			SED="$BREW_BIN/gsed" \
			DTC="$BREW_BIN/dtc" \
			LOCALVERSION="$GKI_LOCALVERSION_SUFFIX" \
			"$ROOT_DIR/common/scripts/kconfig/merge_config.sh" \
			-m -r -O "$OUT_DIR" "$BASE_DEFCONFIG" "$FRAGMENT_CONFIG"
	)
	run_make "KCONFIG_ALLCONFIG=$merged_config" alldefconfig
}

write_dist_manifest() {
	require_file "$OUT_DIR/include/config/kernel.release"
	mkdir -p "$DIST_DIR"
	[ ! -f "$OUT_DIR/arch/arm64/boot/Image.gz" ] || cp -f "$OUT_DIR/arch/arm64/boot/Image.gz" "$DIST_DIR/"
	[ ! -f "$OUT_DIR/arch/arm64/boot/Image.lz4" ] || cp -f "$OUT_DIR/arch/arm64/boot/Image.lz4" "$DIST_DIR/"
	cp -f "$OUT_DIR/include/config/kernel.release" "$DIST_DIR/"
	{
		printf 'kernel_release=%s\n' "$(cat "$OUT_DIR/include/config/kernel.release")"
		printf 'ack_clang_version=%s\n' "$ACK_CLANG_VERSION"
		printf 'clang_version=%s\n' "$("$LLVM_DIR/bin/clang" --version | sed -n '1p')"
		printf 'llvm_dir=%s\n' "$LLVM_DIR"
		printf 'target_triple=%s\n' "$TARGET_TRIPLE"
		printf 'kcflags=%s\n' "$KCFLAGS"
		printf 'localversion_suffix=%s\n' "$GKI_LOCALVERSION_SUFFIX"
		[ ! -f "$OUT_DIR/.config" ] || sed -n 's/^\(CONFIG_CC_VERSION_TEXT=.*\)$/\1/p; s/^\(CONFIG_CLANG_VERSION=.*\)$/\1/p; s/^\(CONFIG_TOOLS_SUPPORT_RELR=.*\)$/\1/p; s/^\(CONFIG_RELR=.*\)$/\1/p; s/^\(CONFIG_ARM64_4K_PAGES=.*\)$/\1/p; s/^\(CONFIG_ARM64_16K_PAGES=.*\)$/\1/p; s/^\(CONFIG_MODULE_FORCE_LOAD=.*\)$/\1/p; s/^\(CONFIG_MODVERSIONS=.*\)$/\1/p; s/^\(CONFIG_MODULE_SIG_PROTECT=.*\)$/\1/p; s/^\(CONFIG_KSU=.*\)$/\1/p' "$OUT_DIR/.config"
		[ ! -f "$DIST_DIR/Image.gz" ] || printf 'image_gz=%s\n' "$DIST_DIR/Image.gz"
		[ ! -f "$DIST_DIR/Image.lz4" ] || printf 'image_lz4=%s\n' "$DIST_DIR/Image.lz4"
	} > "$DIST_DIR/manifest.txt"
}

prepare_defconfig
run_make "$@"

if [ -f "$OUT_DIR/include/config/kernel.release" ]; then
	write_dist_manifest
	printf '%s\n' "$DIST_DIR/manifest.txt"
fi
