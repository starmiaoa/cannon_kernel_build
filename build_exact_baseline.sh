#!/bin/bash
set -euo pipefail

TOOLCHAIN=/cannon
KERNEL=$TOOLCHAIN/kernel
OUT_DIR=$TOOLCHAIN/out
AK_DIR=$TOOLCHAIN/Anykernel3
SOURCE_CONFIG=$TOOLCHAIN/originos4-working.config
OUTPUT_ZIP=$TOOLCHAIN/Cannon-Stock-OriginOS4-ExactConfig.zip

export PATH="$TOOLCHAIN/clang/bin:$TOOLCHAIN/gcc64/bin:$TOOLCHAIN/gcc32/bin:$PATH"
export CCACHE_DIR="$TOOLCHAIN/.ccache"
export USE_CCACHE=1
export KCFLAGS="-Wno-error=unused-but-set-variable -fno-builtin-stpcpy"

COMMON_ARGS=(
  ARCH=arm64
  CLANG_TRIPLE=aarch64-linux-gnu-
  CROSS_COMPILE=aarch64-linux-gnu-
  CROSS_COMPILE_ARM32=arm-linux-gnueabi-
  CC="ccache clang"
  LD=ld.lld
  AR=llvm-ar
  NM=llvm-nm
  OBJCOPY=llvm-objcopy
  OBJDUMP=llvm-objdump
  STRIP=llvm-strip
)

mkdir -p "$OUT_DIR" "$CCACHE_DIR"
ccache -M 50G >/dev/null 2>&1 || true

cp "$SOURCE_CONFIG" "$OUT_DIR/.config"
make -C "$KERNEL" O="$OUT_DIR" "${COMMON_ARGS[@]}" olddefconfig

# The shipping config leaves VOW's DSP selector empty. This public tree then
# descends into an empty directory and never creates vow/built-in.o.
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" --disable MTK_VOW_SUPPORT
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" --enable LEDS_MTK_DISP
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" --enable NFC_PN553_DEVICES
make -C "$KERNEL" O="$OUT_DIR" "${COMMON_ARGS[@]}" olddefconfig

# Keep both configs so unsupported or mutated symbols are visible before flashing.
cp "$OUT_DIR/.config" "$TOOLCHAIN/originos4-result.config"
diff -u "$SOURCE_CONFIG" "$OUT_DIR/.config" > "$TOOLCHAIN/originos4-config.diff" || true

make -C "$KERNEL" O="$OUT_DIR" "${COMMON_ARGS[@]}" -j"$(nproc)" Image.gz
test -s "$OUT_DIR/arch/arm64/boot/Image.gz"

cd "$AK_DIR"
rm -f Image.gz Cannon-Stock-OriginOS4-ExactConfig.zip
cp "$OUT_DIR/arch/arm64/boot/Image.gz" Image.gz
zip -r9 "$OUTPUT_ZIP" . \
  -x '.git/*' '*.git*' 'README.md' 'LICENSE' '*.zip' >/dev/null
rm -f Image.gz

sha256sum "$OUTPUT_ZIP" "$OUT_DIR/arch/arm64/boot/Image.gz"
ls -lh "$OUTPUT_ZIP" "$OUT_DIR/arch/arm64/boot/Image.gz" \
  "$TOOLCHAIN/originos4-result.config" "$TOOLCHAIN/originos4-config.diff"
