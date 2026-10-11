#!/bin/bash

JOBS="${JOBS:-$(nproc)}"
INITIAL_DIR="${INITIAL_DIR:-$(pwd)}"
BHL_VERSION="0.0.1"
PUBLIC_INDEX_ADDRESS="77.105.133.52"

if [[ -v JOBS ]]; then
    if [ "$JOBS" -eq 0 ] 2>/dev/null; then
        echo "MAKEJOBS cannot be '0'"
        echo "Re-run script with example 'JOBS=2 ./dosfstools-4.2.sh'"
        exit 1
    fi
fi

mkdir -pv /sources/extra/
cd /sources/extra

# Check if index available and/or network is up
if curl "http://${PUBLIC_INDEX_ADDRESS}/" &>/dev/null; then
    echo "Public index of BlackHat working"
else
    echo "Public index is not working or network is down"
    echo "Run 'sh ~/net-fix.sh' or manually set network up"
    exit 1
fi

wget "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/dosfstools-4.2.tar.gz"

if [[ -f "dosfstools-4.2.tar.gz" ]]; then
    tar -xf dosfstools-4.2.tar.gz && cd dosfstools-4.2/ || exit 1
    # If anything fails, do not clean sources, just exit with code 1
    if ! (./configure --prefix=/usr); then
        echo "Error: configure failed!"
        exit 1
    fi
    # Disabling ANY trash (documentation)
    sed -i \
      -e '/^dist_doc_DATA = /,/^\s*COPYING ChangeLog NEWS README$/d' \
      -e '/^install-dist_docDATA:/,/^$/d' \
      -e '/^uninstall-dist_docDATA:/,/^$/d' \
      -e 's/^DATA = \$(dist_doc_DATA)$/DATA =/' \
      -e 's/^install-data-am: install-dist_docDATA$/install-data-am:/' \
      -e 's/^uninstall-am: uninstall-dist_docDATA$/uninstall-am:/' \
      -e 's/ install-dist_docDATA//g' \
      -e 's/ uninstall-dist_docDATA//g' \
      Makefile
      
    if ! (make -j"$JOBS" && make install); then
        echo "Error: installation failed!"
        exit 1
    fi
    # Checking for binaries
    if ! type -p mkfs.fat fsck.fat fatlabel &>/dev/null; then
        echo "Error: binaries were not found in PATH!"
        exit 1
    fi
    
    cd "$INITIAL_DIR" || exit 1
else
    echo "No archive found."
    echo "Try to re-run this script"
    exit 1
fi
# Cleaning
rm -rf /sources/extra/dosfstools-4.2/
rm -f /sources/extra/dosfstools-4.2.tar.gz

echo "Successfully installed dosfstools-4.2"
