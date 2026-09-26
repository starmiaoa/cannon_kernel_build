#!/bin/bash
set -euo pipefail

TOOLCHAIN=/cannon
KERNEL=$TOOLCHAIN/kernel
OUT_DIR=$TOOLCHAIN/out
AK_DIR=$TOOLCHAIN/Anykernel3
OUTPUT_ZIP=$TOOLCHAIN/Cannon-SukiSU-Wosnxn.zip

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

# Start from the tree author's defconfig, then align vermagic and enable KSU.
make -C "$KERNEL" O="$OUT_DIR" "${COMMON_ARGS[@]}" cannon_user_defconfig
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" \
  --set-str LOCALVERSION "-perf-00243-g9a0d96109bda"
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" --disable LOCALVERSION_AUTO
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" --enable KSU
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" --disable MTK_DEVAPC
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" --disable DEVAPC_MT6853
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" --disable DEVAPC_ARCH_V2
"$KERNEL/scripts/config" --file "$OUT_DIR/.config" --disable DEVAPC_MMAP_DEBUG
make -C "$KERNEL" O="$OUT_DIR" "${COMMON_ARGS[@]}" olddefconfig

cp "$OUT_DIR/.config" "$TOOLCHAIN/wosnxn-result.config"
grep -E '^CONFIG_(KSU|LOCALVERSION)' "$OUT_DIR/.config" || true

echo "--- kernel release string ---"
make -C "$KERNEL" O="$OUT_DIR" "${COMMON_ARGS[@]}" -s kernelrelease | tee "$TOOLCHAIN/kernelrelease.txt"

make -C "$KERNEL" O="$OUT_DIR" "${COMMON_ARGS[@]}" -k -j"$(nproc)" Image.gz
test -s "$OUT_DIR/arch/arm64/boot/Image.gz"

# Build whatever modules the config enables for Module.symvers (CRC preflight).
make -C "$KERNEL" O="$OUT_DIR" "${COMMON_ARGS[@]}" -k -j"$(nproc)" modules \
  > "$TOOLCHAIN/modules-build.log" 2>&1 || echo "modules build had warnings/errors (tolerated)"
test -s "$OUT_DIR/Module.symvers" || echo "WARNING: Module.symvers missing"

cd "$AK_DIR"
rm -f Image.gz Cannon-SukiSU-Wosnxn.zip
cp "$OUT_DIR/arch/arm64/boot/Image.gz" Image.gz
zip -r9 "$OUTPUT_ZIP" . \
  -x '.git/*' '*.git*' 'README.md' 'LICENSE' '*.zip' >/dev/null
rm -f Image.gz

sha256sum "$OUTPUT_ZIP" "$OUT_DIR/arch/arm64/boot/Image.gz"
ls -lh "$OUTPUT_ZIP" "$OUT_DIR/arch/arm64/boot/Image.gz" \
  "$OUT_DIR/Module.symvers" "$OUT_DIR/System.map" \
  "$TOOLCHAIN/wosnxn-result.config" "$TOOLCHAIN/kernelrelease.txt"
