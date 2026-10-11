#!/bin/bash

JOBS="${JOBS:-$(nproc)}"
INITIAL_DIR="${INITIAL_DIR:-$(pwd)}"
BHL_VERSION="0.0.1"
PUBLIC_INDEX_ADDRESS="77.105.133.52:8844"

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
# Get dependencies
wget "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/efibootmgr/efivar-39.tar.gz"
wget "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/efibootmgr/popt-1.19.tar.gz"
# Get main package
wget "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/efibootmgr/efibootmgr-18.tar.gz"
