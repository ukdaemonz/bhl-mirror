#!/bin/bash

mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev

for mod in squashfs overlay nvme ext4 exfat virtio_blk ahci usb-storage sr_mod iso9660 vfat xfs btrfs f2fs dm_mod loop; do
    modprobe "$mod" 2>/dev/null
done

# FIX. Wait for devices
echo "Waiting for storage devices to settle..."
for _ in 1 2 3 4 5; do
    read -t 1 -r _ 2>/dev/null
    echo -n "."
done
echo "done."

# Parse live= parameter from the kernel command line
LIVE_PARAM=""
ISO_HINT=""
for arg in $(cat /proc/cmdline); do
    case "$arg" in
        live=*)
            LIVE_PARAM="${arg#live=}"
            ;;
        iso-scan/filename=*|findiso=*|fromiso=*)
            ISO_HINT="${arg#*=}"
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

setup_ventoy_dm() {
    [ -d /ventoy ] || return 0
    echo "Ventoy runtime detected (/ventoy), setting up virtual ISO device..."

    if [ -x /ventoy/busybox/sh ] && [ -f /ventoy/hook/ventoy-hook-lib.sh ]; then
        /ventoy/busybox/sh -c '
            . /ventoy/hook/ventoy-hook-lib.sh
            mkdir -p /dev/mapper
            vtdisk=""
            for _ in 0 1 2 3 4 5 6 7 8 9; do
                cand=$(get_ventoy_disk_name)
                if [ -n "$cand" ] && [ "$cand" != "unknown" ] && [ -b "$cand" ]; then
                    vtdisk="$cand"
                    break
                fi
                for sysb in /sys/block/*; do
                    b="${sysb##*/}"
                    case "$b" in loop*|ram*|dm-*|sr*) continue ;; esac
                    if ! not_ventoy_disk "$b" && [ -b "/dev/$b" ]; then
                        vtdisk="/dev/$b"
                        break 2
                    fi
                done
                $SLEEP 1
            done
            vtiso=$(get_ventoy_iso_name)
            if [ -n "$vtiso" ] && [ "$vtiso" != "unknown" ]; then
                echo "$vtiso" > /ventoy/bhl_iso_path
            fi
            if [ -n "$vtdisk" ] && [ -b "$vtdisk" ]; then
                create_ventoy_device_mapper "$vtdisk" --readonly
                if ! [ -b /dev/mapper/ventoy ] && ! [ -b /dev/dm-0 ]; then
                    VT_DM_BIN=$(ventoy_find_bin_path dmsetup)
                    [ -z "$VT_DM_BIN" ] && VT_DM_BIN="$VTOY_PATH/tool/dmsetup"
                    dm_id=$($VT_DM_BIN ls 2>/dev/null | $GREP ventoy | $SED "s/.*(\([0-9][0-9]*\), *\([0-9][0-9]*\)).*/\1 \2/")
                    if [ -n "$dm_id" ]; then
                        $BUSYBOX_PATH/mknod -m 0660 /dev/dm-0 b $dm_id 2>/dev/null
                        $BUSYBOX_PATH/mknod -m 0660 /dev/mapper/ventoy b $dm_id 2>/dev/null
                    fi
                fi
                set_ventoy_hook_finish
            fi
        '
    elif [ -x /ventoy/tool/vtoydump ] && [ -x /ventoy/tool/vtoydm ] && [ -x /ventoy/tool/dmsetup ] && [ -f /ventoy/ventoy_os_param ]; then
        mkdir -p /dev/mapper
        local line="" vtdisk="" vtiso=""
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            line=$(/ventoy/tool/vtoydump -f /ventoy/ventoy_os_param 2>/dev/null) && [ -n "$line" ] && break
            read -t 1 -r _ 2>/dev/null
        done
        if [ -n "$line" ]; then
            vtdisk="${line%%#*}"
            vtiso="${line##*#}"
            [ -n "$vtiso" ] && echo "$vtiso" > /ventoy/bhl_iso_path
            if [ -b "$vtdisk" ] && [ -f /ventoy/ventoy_image_map ]; then
                /ventoy/tool/vtoydm -p -f /ventoy/ventoy_image_map -d "$vtdisk" > /ventoy/ventoy_dm_table
                /ventoy/tool/dmsetup --readonly create ventoy /ventoy/ventoy_dm_table 2>/dev/null
            fi
        fi
    fi

    if [ -f /ventoy/bhl_iso_path ] && [ -z "$ISO_HINT" ]; then
        ISO_HINT=$(cat /ventoy/bhl_iso_path 2>/dev/null)
    fi
}

setup_ventoy_dm

mkdir -pv /mnt/probe /mnt/iso /mnt/squashfs /mnt/rw /mnt/root

SEARCH_PATHS="/live/rootfs.squashfs /rootfs.squashfs /boot/rootfs.squashfs"
FILESYSTEMS="iso9660 exfat vfat ext4 xfs btrfs f2fs" # Added "exfat" FS for Ventoy compatibility

FOUND_SQUASHFS=""
FOUND_DEV=""

try_iso_file() {
    local iso="$1"
    local src_dev="$2"
    local paths="$3"
    [ -f "$iso" ] || return 1

    local iso_loop
    iso_loop=$(losetup -f --show "$iso" 2>/dev/null) || return 1
    if mount -t iso9660 -o ro "$iso_loop" /mnt/iso 2>/dev/null; then
        for p in $paths; do
            local clean_p="${p#/}"
            if [ -f "/mnt/iso/$clean_p" ]; then
                FOUND_SQUASHFS="/mnt/iso/$clean_p"
                FOUND_DEV="$iso_loop ($iso on $src_dev)"
                echo "Found rootfs.squashfs inside ISO: $FOUND_SQUASHFS [$FOUND_DEV]"
                return 0
            fi
        done
        umount /mnt/iso 2>/dev/null
    fi
    losetup -d "$iso_loop" 2>/dev/null
    return 1
}

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

        if [ -n "$ISO_HINT" ]; then
            try_iso_file "$mnt/${ISO_HINT#/}" "$dev" "$paths" && return 0
        fi
        if [ -n "$LIVE_FILE" ]; then
            case "$LIVE_FILE" in
                *.iso|*.ISO)
                    try_iso_file "$mnt/${LIVE_FILE#/}" "$dev" "$paths" && return 0
                    ;;
            esac
        fi
        for iso in \
            "$mnt"/blackhat*.iso "$mnt"/BlackHat*.iso "$mnt"/BHL*.iso \
            "$mnt"/*/blackhat*.iso "$mnt"/*/BlackHat*.iso "$mnt"/*/BHL*.iso \
            "$mnt"/*/*/blackhat*.iso "$mnt"/*/*/BlackHat*.iso \
            "$mnt"/*.iso "$mnt"/*/*.iso; do
            [ -f "$iso" ] || continue
            try_iso_file "$iso" "$dev" "$paths" && return 0
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
    for dev in /dev/mapper/ventoy /dev/dm-* /dev/sr* /dev/sd* /dev/nvme* /dev/vd* /dev/mmcblk* /dev/hd*; do
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
