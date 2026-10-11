#!/bin/bash

JOBS="${JOBS:-$(nproc)}"
INITIAL_DIR="${INITIAL_DIR:-$(pwd)}"
BHL_VERSION="0.0.1"
KVER="${KVER:-7.2.8}"
ZFS_VERSION="2.4.4"
ZFS_SHA256="2a3c70d55a37cc71618a95a60e81ad66530201eb118d37741dc92efcf848c8b1"
ZFS_ARC_MAX="${ZFS_ARC_MAX:-1073741824}"
PUBLIC_INDEX_ADDRESS="${PUBLIC_INDEX_ADDRESS:-77.105.133.52}"

if [[ -v JOBS ]]; then
    if [ "$JOBS" -eq 0 ] 2>/dev/null; then
        echo "MAKEJOBS cannot be '0'"
        echo "Re-run script with example 'JOBS=2 ./zfs-2.4.4.sh'"
        exit 1
    fi
fi

if curl -fsS -m 10 "http://${PUBLIC_INDEX_ADDRESS}/" &>/dev/null; then
    echo "Public index of BlackHat working"
else
    echo "Public index is not working or network is down"
    echo "Run 'sh ~/net-fix.sh' or manually set network up"
    exit 1
fi

KERNEL_DIR="${KERNEL_DIR:-}"
for cand in "/lib/modules/${KVER}/build" "/sources/linux-${KVER}" "/usr/src/linux-${KVER}"; do
    if [ -d "$cand" ] && [ -f "$cand/Makefile" ]; then
        KERNEL_DIR="$cand"
        break
    fi
done

if [ -z "$KERNEL_DIR" ]; then
    mkdir -pv /sources
    cd /sources || exit 1
    if [ ! -f "linux-${KVER}-blackhat.tar.xz" ]; then
        wget -c --tries=20 --timeout=30 \
            "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/kernel/linux-${KVER}-blackhat.tar.xz" || exit 1
    fi
    tar -xf "linux-${KVER}-blackhat.tar.xz" || exit 1
    KERNEL_DIR="/sources/linux-${KVER}"
fi

if [ ! -f "$KERNEL_DIR/.config" ]; then
    if [ -f "/boot/config-${KVER}-bhl" ]; then
        cp "/boot/config-${KVER}-bhl" "$KERNEL_DIR/.config"
    elif [ -f "/sources/config-${KVER}-bhl" ]; then
        cp "/sources/config-${KVER}-bhl" "$KERNEL_DIR/.config"
    else
        wget -q -O "$KERNEL_DIR/.config" \
            "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/kernel/config-${KVER}-bhl" || exit 1
    fi
fi

if [ ! -f "$KERNEL_DIR/include/generated/utsrelease.h" ]; then
    make -C "$KERNEL_DIR" olddefconfig modules_prepare -j"$JOBS" || exit 1
fi

mkdir -pv /sources/extra/
cd /sources/extra || exit 1

rm -f "zfs-${ZFS_VERSION}.tar.gz"
if ! wget -c --tries=5 --timeout=20 \
    "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/zfs-${ZFS_VERSION}.tar.gz" 2>/dev/null; then
    if ! wget -c --tries=5 --timeout=20 \
        "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/zfs/zfs-${ZFS_VERSION}.tar.gz" 2>/dev/null; then
        wget -c --tries=10 --timeout=30 \
            "https://github.com/openzfs/zfs/releases/download/zfs-${ZFS_VERSION}/zfs-${ZFS_VERSION}.tar.gz" || exit 1
    fi
fi

if [[ -f "zfs-${ZFS_VERSION}.tar.gz" ]]; then
    GOT_SHA="$(sha256sum "zfs-${ZFS_VERSION}.tar.gz" | awk '{print $1}')"
    if [ "$GOT_SHA" != "$ZFS_SHA256" ]; then
        echo "Error: sha256 mismatch for zfs-${ZFS_VERSION}.tar.gz ($GOT_SHA)"
        exit 1
    fi

    rm -rf "zfs-${ZFS_VERSION}"
    tar -xf "zfs-${ZFS_VERSION}.tar.gz" && cd "zfs-${ZFS_VERSION}/" || exit 1

    if ! (
        ./configure --prefix=/usr \
            --sysconfdir=/etc \
            --sbindir=/sbin \
            --libdir=/usr/lib \
            --with-config=all \
            --with-linux="$KERNEL_DIR" \
            --with-linux-obj="$KERNEL_DIR" \
            --enable-systemd \
            --with-udevdir=/usr/lib/udev \
            --with-udevruledir=/usr/lib/udev/rules.d \
            --with-systemdunitdir=/usr/lib/systemd/system \
            --with-systemdpresetdir=/usr/lib/systemd/system-preset \
            --with-systemdgeneratordir=/usr/lib/systemd/system-generators \
            --with-systemdmodulesloaddir=/usr/lib/modules-load.d \
            --without-tirpc \
            --disable-pyzfs
    ); then
        echo "Error: configure failed!"
        exit 1
    fi

    if ! (make -j"$JOBS" && make install); then
        echo "Error: build or installation failed!"
        exit 1
    fi

    ldconfig 2>/dev/null || true
    depmod -a "$KVER" || exit 1

    if [ ! -f /etc/hostid ]; then
        zgenhostid
    fi

    mkdir -p /etc/modules-load.d /etc/modprobe.d
    echo "zfs" > /etc/modules-load.d/zfs.conf
    echo "options zfs zfs_arc_max=${ZFS_ARC_MAX}" > /etc/modprobe.d/zfs.conf

    if ! type -p zpool zfs zdb zgenhostid mount.zfs &>/dev/null; then
        echo "Error: ZFS binaries were not found in PATH!"
        exit 1
    fi

    if ! find "/lib/modules/${KVER}" -name "zfs.ko*" | grep -q .; then
        echo "Error: zfs.ko kernel module was not installed!"
        exit 1
    fi

    systemctl enable zfs-import-cache.service zfs-mount.service zfs-zed.service zfs-import.target zfs.target 2>/dev/null || true

    cd "$INITIAL_DIR" || exit 1
else
    echo "No archive found."
    echo "Try to re-run this script"
    exit 1
fi

rm -rf "/sources/extra/zfs-${ZFS_VERSION}/"
rm -f "/sources/extra/zfs-${ZFS_VERSION}.tar.gz"

echo "Successfully installed OpenZFS-${ZFS_VERSION}"
