# macOS GKI Tools

Tiny macOS helper scripts for building and packing an Android arm64 GKI kernel.
They do not manage kernel config. Edit defconfig/fragments in your kernel tree
yourself.

## Requirements

```sh
brew install llvm openssl@3 dtc lz4 gnu-sed zip
```

Default paths:

```sh
LLVM_DIR=prebuilts/clang/host/darwin-x86/clang-$CLANG_VERSION
OPENSSL_DIR=/opt/homebrew/opt/openssl@3
BREW_BIN=/opt/homebrew/bin
```

## Build

```sh
tools/build-gki-macos.sh
```

Default targets:

```sh
Image.gz Image.lz4
```

Useful overrides:

```sh
JOBS=8 tools/build-gki-macos.sh
OUT_DIR=/tmp/gki-out tools/build-gki-macos.sh Image.gz
GKI_LOCALVERSION_SUFFIX=-MyKernel tools/build-gki-macos.sh
```

Outputs:

```sh
out/macos-gki/arch/arm64/boot/Image.gz
out/macos-gki/arch/arm64/boot/Image.lz4
out/macos-gki-dist/manifest.txt
```

## Pack

```sh
ANYKERNEL3_DIR=/path/to/AnyKernel3 tools/package-anykernel3.sh
```

If `out/anykernel3-macos-gki` already has AnyKernel3 files, the script reuses
that as a template.

Output:

```sh
out/macos-gki-anykernel3.zip
```

The generated zip replaces only the boot kernel image. It does not include or
flash vendor modules.
