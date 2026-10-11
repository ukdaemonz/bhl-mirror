#!/bin/bash

JOBS="${JOBS:-$(nproc)}"
INITIAL_DIR="${INITIAL_DIR:-$(pwd)}"
BHL_VERSION="0.0.1"
PUBLIC_INDEX_ADDRESS="77.105.133.52"

# First, check if we are on UEFI
if [ ! -d /sys/firmware/efi ]; then
    echo "Error: booted not in UEFI-mode, efibootmgr not needed"
    exit 1
fi

# Check if kernel is 64-bit
if [ "$(uname -m)" != "x86_64" ]; then
    echo "Warning: 32-bit userspace detected!"
    echo "Installation may break NVRAM. Continue? [y/n]"
    read -r ans
    [ "$ans" = "y" ] || exit 1
fi

if [ -r /sys/firmware/efi/fw_platform_size ]; then
    FW_SIZE=$(cat /sys/firmware/efi/fw_platform_size)
    if [ "$FW_SIZE" = "1" ] && [ "$(uname -m)" != "x86_64" ]; then
        echo "Error: 64-bit UEFI on 32-bit system. Refusing."
        exit 1
    fi
    if [ "$FW_SIZE" = "0" ] && [ "$(uname -m)" != "i686" ] && [ "$(uname -m)" != "i386" ]; then
        echo "Error: 32-bit UEFI on 64-bit system. Refusing."
        exit 1
    fi
fi

# Check if index available and/or network is up
if curl "http://${PUBLIC_INDEX_ADDRESS}/" &>/dev/null; then
    echo "Public index of BlackHat working"
else
    echo "Public index is not working or network is down"
    echo "Run 'sh ~/net-fix.sh' or manually set network up"
    exit 1
fi

mkdir -pv /sources/extra/
cd /sources/extra

# Get dependencies
wget "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/efibootmgr/efivar-39.tar.gz"
wget "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/efibootmgr/popt-1.19.tar.gz"
# Get main package
wget "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/efibootmgr/efibootmgr-18.tar.gz"
# Efivar-39 patch
wget "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/efibootmgr/efivar-39-upstream_fixes-1.patch"

# efivar-39
if [[ -f "efivar-39.tar.gz" ]]; then
    tar -xf efivar-39.tar.gz && cd efivar-39/ || exit 1
    mv ../efivar-39-upstream_fixes-1.patch ./ || exit 1
    
    # Apply patch
    if [[ -f "efivar-39-upstream_fixes-1.patch" ]]; then
        patch -Np1 -i efivar-39-upstream_fixes-1.patch || exit 1
    fi
    # Build and install efivar-39
    if ! (make ENABLE_DOCS=0 -j"$JOBS" && make install ENABLE_DOCS=0 LIBDIR=/usr/lib); then
        echo "Error: installation failed!"
        exit 1
    fi
    cd /sources/extra/
else
    echo "No archive found."
    echo "Try to re-run this script"
    exit 1
fi

# popt-1.19
if [[ -f "popt-1.19.tar.gz" ]]; then
    tar -xf popt-1.19.tar.gz && cd popt-1.19/ || exit 1
    
    if ! (./configure --prefix=/usr --disable-static && make -j"$JOBS" && make install); then
        echo "Error: configuration, build or installation failed!"
        exit 1
    fi
    cd /sources/extra
else
    echo "No archive found."
    echo "Try to re-run this script"
    exit 1
fi

# efibootmgr-18
if [[ -f "efibootmgr-18.tar.gz" ]]; then
    tar -xf efibootmgr-18.tar.gz && cd efibootmgr-18/ || exit 1
    
    if ! (make -j"$JOBS" && make install); then
        echo "Error: build or installation failed!"
        exit 1
    fi
    # Mount efivars
    if ! (mountpoint /sys/firmware/efi/efivars || mount -v -t efivarfs efivarfs /sys/firmware/efi/efivars); then
        echo "Error: failed to mount /sys/firmware/efi/efivars!"
        echo 'Do not use efibootmgr-18 commands before you successfully mount efivars!!!'
    fi    
    cd "$INITIAL_DIR" || exit 1
else
    echo "No archive found."
    echo "Try to re-run this script"
    exit 1
fi

# Cleaning
rm -rf /sources/extra/{efivar-39,popt-1.19,efibootmgr-18}/
rm -f /sources/extra/{efivar-39,popt-1.19,efibootmgr-18}.tar.gz
rm -f /sources/extra/efivar-39-upstream_fixes-1.patch

echo "Successfully installed efibootmgr-18"
