#!/bin/bash
# build-iso.sh -- assemble BlackHat Live hybrid ISO (BIOS + UEFI)
set -euo pipefail

ISO_NAME="blackhat-live-0.0.1"
KERNEL="vmlinuz-blackhat-live-0.0.1"
INITRAMFS="initramfs-blackhat-live-0.0.1.img"
KERNEL_CONFIG="config-7.2.8-bhl"
ROOTFS="rootfs.squashfs"
VOLID="BHL_LIVE"
LIMINE_DIR="${LIMINE_DIR:-/usr/share/limine}"

WORKDIR="$(pwd)/iso"
ISOROOT="$WORKDIR/iso_root"
OUTPUT="$(pwd)/${ISO_NAME}.iso"

for f in "$KERNEL" "$INITRAMFS" "$KERNEL_CONFIG" "$ROOTFS"; do
    [ -f "$f" ] || { echo "Missing file: $f"; exit 1; }
done
for b in limine-bios.sys limine-bios-cd.bin limine-uefi-cd.bin BOOTX64.EFI; do
    [ -f "$LIMINE_DIR/$b" ] || { echo "Missing limine binary: $LIMINE_DIR/$b"; exit 1; }
done
command -v xorriso >/dev/null || { echo "xorriso not installed"; exit 1; }
command -v limine  >/dev/null || { echo "limine (cli) not installed"; exit 1; }

rm -rf "$ISOROOT"
mkdir -p "$ISOROOT/EFI/BOOT" "$ISOROOT/boot/limine"

cp "$KERNEL"        "$ISOROOT/$KERNEL"
cp "$INITRAMFS"     "$ISOROOT/$INITRAMFS"
cp "$KERNEL_CONFIG" "$ISOROOT/$KERNEL_CONFIG"
cp "$ROOTFS"        "$ISOROOT/$ROOTFS"

cp "$LIMINE_DIR/limine-bios.sys"    "$ISOROOT/boot/limine/"
cp "$LIMINE_DIR/limine-bios-cd.bin" "$ISOROOT/boot/limine/"
cp "$LIMINE_DIR/limine-uefi-cd.bin" "$ISOROOT/boot/limine/"
cp "$LIMINE_DIR/BOOTX64.EFI"        "$ISOROOT/EFI/BOOT/BOOTX64.EFI"

cat > "$ISOROOT/boot/limine/limine.conf" <<EOF # New limine.conf format
timeout: 5
default_entry: 1

/BlackHat Live 0.0.1 (x86_64)
    protocol: linux
    kernel_path: boot:///$KERNEL
    module_path: boot:///$INITRAMFS
    cmdline: console=tty0
EOF

xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "$VOLID" \
    -b boot/limine/limine-bios-cd.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
    --efi-boot boot/limine/limine-uefi-cd.bin \
        -efi-boot-part --efi-boot-image \
        --protective-msdos-label \
    "$ISOROOT" \
    -o "$OUTPUT"

limine bios-install "$OUTPUT"

echo
echo "Built: $OUTPUT"
ls -lh "$OUTPUT"
