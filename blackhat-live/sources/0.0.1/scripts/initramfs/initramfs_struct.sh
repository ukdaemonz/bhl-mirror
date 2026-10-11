#!/bin/bash

mkdir -pv /tmp/initramfs/{bin,sbin,dev,proc,sys,lib,lib64,usr/lib,usr/bin,usr/sbin,etc,mnt/root,mnt/squashfs,mnt/rw,mnt/test}
cd /tmp/initramfs/
cp -v /lib/ld-linux-x86-64.so.2 ./lib/ && ln -sv ../lib/ld-linux-x86-64.so.2 ./lib64/ld-linux-x86-64.so.2

for bin in bash mount umount switch_root losetup modprobe mkdir cp mv ls cat sh blkid; do
    if [ -f /bin/$bin ]; then
        cp /bin/$bin /tmp/initramfs/bin/
    elif [ -f /usr/bin/$bin ]; then
        cp /usr/bin/$bin /tmp/initramfs/bin/
    elif [ -f /sbin/$bin ]; then
        cp /sbin/$bin /tmp/initramfs/sbin/
    elif [ -f /usr/sbin/$bin ]; then
        cp /usr/sbin/$bin /tmp/initramfs/usr/sbin/
    fi
done

for bin in /tmp/initramfs/bin/* /tmp/initramfs/sbin/* /tmp/initramfs/usr/bin/* /tmp/initramfs/usr/sbin/*; do
    if [ -f "$bin" ]; then
        echo "Processing: $bin"
        ldd "$bin" 2>/dev/null | while read line; do
            case "$line" in
                *linux-vdso*|*ld-linux*) continue ;;
            esac
            lib=$(echo "$line" | awk '{print $3}')
            echo "  Lib: $lib"
            if [ -n "$lib" ] && [ -f "$lib" ]; then
                mkdir -p "/tmp/initramfs$(dirname $lib)"
                cp -L "$lib" "/tmp/initramfs$lib"
                echo "Copied: $lib"
            else
                echo "Skipped (not found): $lib"
            fi
        done
    fi
done

KVER=7.2.8
mkdir -p /tmp/initramfs/lib/modules/$KVER

for mod in fs/{squashfs,overlayfs,ext4,exfat} drivers/{nvme,ata,char,devfreq,gpu,i3c,md,memstick,mfd,misc,mmc,patform,power,scsi,tty,ufs,usb,virtio}; do
    if [ -d /lib/modules/$KVER/kernel/$mod ]; then
        mkdir -p "/tmp/initramfs/lib/modules/$KVER/kernel/$(dirname $mod)"
        cp -r "/lib/modules/$KVER/kernel/$mod" "/tmp/initramfs/lib/modules/$KVER/kernel/$mod"
    fi
done
