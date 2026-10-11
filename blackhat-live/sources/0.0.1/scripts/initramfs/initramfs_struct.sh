#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INITRAMFS_DIR="${INITRAMFS_DIR:-/tmp/initramfs}"
KVER="${KVER:-7.2.8}"

mkdir -pv "$INITRAMFS_DIR"/{bin,sbin,dev,proc,sys,lib,lib64,usr/lib,usr/bin,usr/sbin,etc,mnt/root,mnt/squashfs,mnt/rw,mnt/test,mnt/probe,mnt/iso}
cd "$INITRAMFS_DIR" || exit 1
cp -v /lib/ld-linux-x86-64.so.2 ./lib/ && ln -sfv ../lib/ld-linux-x86-64.so.2 ./lib64/ld-linux-x86-64.so.2

for bin in bash mount umount switch_root losetup modprobe mkdir cp mv ls cat sh blkid sleep mknod grep sed awk rm ln; do
    if [ -f "/bin/$bin" ]; then
        cp "/bin/$bin" "$INITRAMFS_DIR/bin/"
    elif [ -f "/usr/bin/$bin" ]; then
        cp "/usr/bin/$bin" "$INITRAMFS_DIR/bin/"
    elif [ -f "/sbin/$bin" ]; then
        cp "/sbin/$bin" "$INITRAMFS_DIR/sbin/"
    elif [ -f "/usr/sbin/$bin" ]; then
        cp "/usr/sbin/$bin" "$INITRAMFS_DIR/usr/sbin/"
    fi
done

for bin in "$INITRAMFS_DIR"/bin/* "$INITRAMFS_DIR"/sbin/* "$INITRAMFS_DIR"/usr/bin/* "$INITRAMFS_DIR"/usr/sbin/*; do
    if [ -f "$bin" ]; then
        echo "Processing: $bin"
        ldd "$bin" 2>/dev/null | while read -r line; do
            case "$line" in
                *linux-vdso*|*ld-linux*) continue ;;
            esac
            lib=$(echo "$line" | awk '{print $3}')
            echo "  Lib: $lib"
            if [ -n "$lib" ] && [ -f "$lib" ]; then
                mkdir -p "$INITRAMFS_DIR$(dirname "$lib")"
                cp -L "$lib" "$INITRAMFS_DIR$lib"
                echo "Copied: $lib"
            else
                echo "Skipped (not found): $lib"
            fi
        done
    fi
done

mkdir -p "$INITRAMFS_DIR/lib/modules/$KVER"

for mod in fs/{squashfs,overlayfs,ext4,exfat,iso9660,vfat,fat,nls} drivers/{nvme,ata,block,char,devfreq,gpu,i3c,md,memstick,mfd,misc,mmc,platform,power,scsi,tty,ufs,usb,virtio}; do
    if [ -d "/lib/modules/$KVER/kernel/$mod" ]; then
        mkdir -p "$INITRAMFS_DIR/lib/modules/$KVER/kernel/$(dirname "$mod")"
        cp -r "/lib/modules/$KVER/kernel/$mod" "$INITRAMFS_DIR/lib/modules/$KVER/kernel/$mod"
    fi
done

for depfile in modules.dep modules.dep.bin modules.alias modules.alias.bin modules.symbols modules.symbols.bin modules.builtin modules.builtin.bin modules.builtin.modinfo modules.order; do
    if [ -f "/lib/modules/$KVER/$depfile" ]; then
        cp -v "/lib/modules/$KVER/$depfile" "$INITRAMFS_DIR/lib/modules/$KVER/"
    fi
done

if [ -f "$SCRIPT_DIR/initrd_mount.sh" ]; then
    cp -v "$SCRIPT_DIR/initrd_mount.sh" "$INITRAMFS_DIR/init"
    chmod 0755 "$INITRAMFS_DIR/init"
fi
