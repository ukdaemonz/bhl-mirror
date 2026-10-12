#!/bin/bash

JOBS="${JOBS:-$(nproc)}"
INITIAL_DIR="${INITIAL_DIR:-$(pwd)}"
BHL_VERSION="0.0.1"
LIBRESSL_VERSION="4.2.2"
LIBRESSL_SHA256="f034c1210f53743b708aabbe44e6939772b842e87d834415c96f9e4219c340c3"
PUBLIC_INDEX_ADDRESS="${PUBLIC_INDEX_ADDRESS:-77.105.133.52}"

if [[ -v JOBS ]]; then
    if [ "$JOBS" -eq 0 ] 2>/dev/null; then
        echo "MAKEJOBS cannot be '0'"
        echo "Re-run script with example 'JOBS=2 ./libressl-4.2.2.sh'"
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

mkdir -pv /sources/extra/
cd /sources/extra || exit 1

rm -f "libressl-${LIBRESSL_VERSION}.tar.gz"
if ! wget -c --tries=5 --timeout=20 \
    "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/libressl-${LIBRESSL_VERSION}.tar.gz" 2>/dev/null; then
    if ! wget -c --tries=5 --timeout=20 \
        "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/packages/libressl-${LIBRESSL_VERSION}.tar.gz" 2>/dev/null; then
        wget -c --tries=10 --timeout=30 \
            "https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-${LIBRESSL_VERSION}.tar.gz" || exit 1
    fi
fi

if [[ -f "libressl-${LIBRESSL_VERSION}.tar.gz" ]]; then
    GOT_SHA="$(sha256sum "libressl-${LIBRESSL_VERSION}.tar.gz" | awk '{print $1}')"
    if [ "$GOT_SHA" != "$LIBRESSL_SHA256" ]; then
        echo "Error: sha256 mismatch for libressl-${LIBRESSL_VERSION}.tar.gz ($GOT_SHA)"
        exit 1
    fi

    rm -rf "libressl-${LIBRESSL_VERSION}"
    tar -xf "libressl-${LIBRESSL_VERSION}.tar.gz" && cd "libressl-${LIBRESSL_VERSION}/" || exit 1

    if ! (
        ./configure --prefix=/usr \
            --sysconfdir=/etc \
            --libdir=/usr/lib \
            --enable-nc \
            --disable-static
    ); then
        echo "Error: configure failed!"
        exit 1
    fi

    if ! make -j"$JOBS"; then
        echo "Error: build failed!"
        exit 1
    fi

    rm -rf /usr/include/openssl /usr/include/tls.h
    rm -f /usr/lib/libcrypto.so /usr/lib/libssl.so /usr/lib/libtls.so
    rm -f /usr/lib/libcrypto.a /usr/lib/libssl.a /usr/lib/libtls.a

    if ! make install; then
        echo "Error: installation failed!"
        exit 1
    fi

    mkdir -p /etc/ssl/certs
    install -m 644 openssl.cnf /etc/ssl/openssl.cnf
    install -m 644 x509v3.cnf /etc/ssl/x509v3.cnf
    if [ ! -f /etc/ssl/cert.pem ] && [ -f cert.pem ]; then
        install -m 644 cert.pem /etc/ssl/cert.pem
    fi

    ldconfig 2>/dev/null || true

    if ! /usr/bin/openssl version | grep -q "LibreSSL"; then
        echo "Error: /usr/bin/openssl is not LibreSSL!"
        exit 1
    fi

    cd "$INITIAL_DIR" || exit 1
else
    echo "No archive found."
    echo "Try to re-run this script"
    exit 1
fi

rm -rf "/sources/extra/libressl-${LIBRESSL_VERSION}/"
rm -f "/sources/extra/libressl-${LIBRESSL_VERSION}.tar.gz"

echo "Successfully installed LibreSSL-${LIBRESSL_VERSION}"
