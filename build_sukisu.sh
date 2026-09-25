#!/bin/bash
set -euo pipefail

TOOLCHAIN=/cannon
KERNEL=$TOOLCHAIN/kernel
OUT_DIR=$TOOLCHAIN/out
AK_DIR=$TOOLCHAIN/Anykernel3
SOURCE_CONFIG=$TOOLCHAIN/sukisu-originos4.config
OUTPUT_ZIP=$TOOLCHAIN/Cannon-SukiSU-OriginOS4.zip

export PATH="$TOOLCHAIN/clang/bin:$TOOLCHAIN/gcc64/bin:$TOOLCHAIN/gcc32/bin:$PATH"
export CCACHE_DIR="$TOOLCHAIN/.ccache"
export USE_CCACHE=1
export KCFLAGS="-fno-builtin-stpcpy"

COMMON_ARGS=(
  ARCH=arm64
  CLANG_TRIPLE=aarch64-linux-gnu-
  CROSS_COMPILE=/cannon/cross64/aarch64-linux-gnu-
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

# P73 is enabled in the shipping config, but the public Kconfig nests its
# companion PN553 driver under the generic NFC menu.
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" --enable NFC
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" --enable NFC_PN553_DEVICES

# Re-assert the KernelSU option after olddefconfig in case the vendor Kconfig
# ordering dropped it.
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" --enable KSU
make -C "$KERNEL" O="$OUT_DIR" "${COMMON_ARGS[@]}" olddefconfig

cp "$OUT_DIR/.config" "$TOOLCHAIN/sukisu-result.config"
diff -u "$SOURCE_CONFIG" "$OUT_DIR/.config" > "$TOOLCHAIN/sukisu-config.diff" || true

echo "--- kernel release string ---"
make -C "$KERNEL" O="$OUT_DIR" "${COMMON_ARGS[@]}" -s kernelrelease | tee "$TOOLCHAIN/kernelrelease.txt"

grep -E '^CONFIG_(KSU|LOCALVERSION)' "$OUT_DIR/.config" || true

make -C "$KERNEL" O="$OUT_DIR" "${COMMON_ARGS[@]}" -k -j"$(nproc)" Image.gz
test -s "$OUT_DIR/arch/arm64/boot/Image.gz"

# Build whatever modules the config enables so Module.symvers carries the
# vmlinux export CRCs; used to pre-check vendor module compatibility.
make -C "$KERNEL" O="$OUT_DIR" "${COMMON_ARGS[@]}" -k -j"$(nproc)" modules \
  > "$TOOLCHAIN/modules-build.log" 2>&1 || echo "modules build had warnings/errors (tolerated)"
test -s "$OUT_DIR/Module.symvers" || echo "WARNING: Module.symvers missing"

cd "$AK_DIR"
rm -f Image.gz Cannon-SukiSU-OriginOS4.zip
cp "$OUT_DIR/arch/arm64/boot/Image.gz" Image.gz
zip -r9 "$OUTPUT_ZIP" . \
  -x '.git/*' '*.git*' 'README.md' 'LICENSE' '*.zip' >/dev/null
rm -f Image.gz

sha256sum "$OUTPUT_ZIP" "$OUT_DIR/arch/arm64/boot/Image.gz"
ls -lh "$OUTPUT_ZIP" "$OUT_DIR/arch/arm64/boot/Image.gz" \
  "$OUT_DIR/Module.symvers" "$OUT_DIR/System.map" \
  "$TOOLCHAIN/sukisu-result.config" "$TOOLCHAIN/kernelrelease.txt"
