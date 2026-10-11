#!/bin/bash

mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev

modprobe squashfs 2>/dev/null
modprobe overlay 2>/dev/null
modprobe nvme 2>/dev/null
modprobe ext4 2>/dev/null
modprobe exfat 2>/dev/null
modprobe virtio_blk 2>/dev/null
modprobe ahci 2>/dev/null
modprobe usb-storage 2>/dev/null
modprobe sr_mod 2>/dev/null
modprobe iso9660 2>/dev/null
modprobe vfat 2>/dev/null
modprobe xfs 2>/dev/null
modprobe btrfs 2>/dev/null
modprobe f2fs 2>/dev/null

# FIX. Wait for devices
echo "Waiting for storage devices to settle..."
for _ in 1 2 3 4 5; do
    read -t 1 -r _ 2>/dev/null
    echo -n "."
done
echo "done."

# Parse live= parameter from the kernel command line
LIVE_PARAM=""
for arg in $(cat /proc/cmdline); do
    case "$arg" in
        live=*)
            LIVE_PARAM="${arg#live=}"
            ;;
    esac
done

LIVE_DEV=""
LIVE_FILE=""
if [ -n "$LIVE_PARAM" ]; then
    case "$LIVE_PARAM" in
        *:*)
            LIVE_DEV="${LIVE_PARAM%%:*}"
            LIVE_FILE="${LIVE_PARAM#*:}"
            ;;
        *)
            LIVE_DEV="$LIVE_PARAM"
            ;;
    esac
    echo "Live parameter detected:"
    echo "  Device: $LIVE_DEV"
    echo "  File:   $LIVE_FILE"
fi

mkdir -pv /mnt/probe /mnt/squashfs /mnt/rw /mnt/root

SEARCH_PATHS="/live/rootfs.squashfs /rootfs.squashfs /boot/rootfs.squashfs"
FILESYSTEMS="ext4 exfat xfs btrfs vfat iso9660" # Added "exfat" FS for Ventoy compatibility

FOUND_SQUASHFS=""
FOUND_DEV=""

# Try to locate rootfs.squashfs on the given block device
# On success, the device stays mounted at /mnt/probe and FOUND_SQUASHFS
# holds a usable path to the image file
try_device() {
    local dev="$1"
    local mnt="/mnt/probe"
    local paths="$SEARCH_PATHS"

    # If this is the device from the live= parameter and a file path was
    # supplied, try that path first
    if [ -n "$LIVE_FILE" ] && [ "$dev" = "$LIVE_DEV" ]; then
        paths="$LIVE_FILE $SEARCH_PATHS"
    fi

    for fs in $FILESYSTEMS; do
        mount -t "$fs" -o ro "$dev" "$mnt" 2>/dev/null || continue
        for p in $paths; do
            local clean_p="${p#/}"
            if [ -f "$mnt/$clean_p" ]; then
                FOUND_SQUASHFS="$mnt/$clean_p"
                FOUND_DEV="$dev"
                echo "Found rootfs.squashfs: $FOUND_SQUASHFS (dev=$FOUND_DEV, fs=$fs)"
                return 0
            fi
        done
        umount "$mnt" 2>/dev/null
    done
    return 1
}

# Priority 1: the device passed via the live= parameter (if valid)
if [ -n "$LIVE_DEV" ] && [ -b "$LIVE_DEV" ]; then
    echo "Trying live= device first: $LIVE_DEV"
    try_device "$LIVE_DEV"
fi

# Priority 2: scan every block device we can find
if [ -z "$FOUND_SQUASHFS" ]; then
    for dev in /dev/sd* /dev/nvme* /dev/vd* /dev/sr* /dev/mmcblk* /dev/hd*; do
        [ -b "$dev" ] || continue
        [ "$dev" = "$LIVE_DEV" ] && continue
        if try_device "$dev"; then
            break
        fi
    done
fi

if [ -z "$FOUND_SQUASHFS" ]; then
    echo "ERROR: rootfs.squashfs not found on any device!"
    exec /bin/bash
fi

# Mount the squashfs image
if ! mount -t squashfs -o ro "$FOUND_SQUASHFS" /mnt/squashfs 2>/dev/null; then
    echo "Direct mount failed, trying loop device..."
    LOOP_DEV=$(losetup -f --show "$FOUND_SQUASHFS")
    if [ -z "$LOOP_DEV" ]; then
        echo "ERROR: Cannot create loop device!"
        exec /bin/bash
    fi
    echo "Loop device: $LOOP_DEV"
    if ! mount -t squashfs -o ro "$LOOP_DEV" /mnt/squashfs; then
        echo "ERROR: Cannot mount squashfs via loop device!"
        exec /bin/bash
    fi
fi

# Writable overlay layer in RAM
if ! mount -t tmpfs tmpfs /mnt/rw; then
    echo "ERROR: Cannot mount tmpfs for rw layer!"
    exec /bin/bash
fi
mkdir -pv /mnt/rw/upper /mnt/rw/work

echo "Mounting overlayfs..."
if ! mount -t overlay overlay \
    -o lowerdir=/mnt/squashfs,upperdir=/mnt/rw/upper,workdir=/mnt/rw/work \
    /mnt/root; then
    echo "ERROR: Cannot mount overlayfs!"
    exec /bin/bash
fi

echo "Switching root..."
exec switch_root /mnt/root /lib/systemd/systemd
