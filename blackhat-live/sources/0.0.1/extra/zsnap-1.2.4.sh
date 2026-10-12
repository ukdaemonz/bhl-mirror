#!/bin/bash

INITIAL_DIR="${INITIAL_DIR:-$(pwd)}"
BHL_VERSION="0.0.1"
ZSNAP_VERSION="1.2.4"
ZSNAP_SHA256="e8ba37a732d4ad39f8567da45980f48d0539d876f1a06143d64b6b8293ec95e5"
PUBLIC_INDEX_ADDRESS="${PUBLIC_INDEX_ADDRESS:-77.105.133.52}"

if curl -fsS -m 10 "http://${PUBLIC_INDEX_ADDRESS}/" &>/dev/null; then
    echo "Public index of BlackHat working"
else
    echo "Public index is not working or network is down"
    echo "Run 'sh ~/net-fix.sh' or manually set network up"
    exit 1
fi

mkdir -pv /sources/extra/
cd /sources/extra || exit 1

rm -f "zfs-auto-snapshot-${ZSNAP_VERSION}.tar.gz"
if ! wget -c --tries=5 --timeout=20 \
    "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/zfs-auto-snapshot-${ZSNAP_VERSION}.tar.gz" 2>/dev/null; then
    wget -c --tries=10 --timeout=30 -O "zfs-auto-snapshot-${ZSNAP_VERSION}.tar.gz" \
        "https://github.com/zfsonlinux/zfs-auto-snapshot/archive/refs/heads/master.tar.gz" || exit 1
fi

if [[ -f "zfs-auto-snapshot-${ZSNAP_VERSION}.tar.gz" ]]; then
    GOT_SHA="$(sha256sum "zfs-auto-snapshot-${ZSNAP_VERSION}.tar.gz" | awk '{print $1}')"
    if [ "$GOT_SHA" != "$ZSNAP_SHA256" ]; then
        echo "Error: sha256 mismatch for zfs-auto-snapshot-${ZSNAP_VERSION}.tar.gz ($GOT_SHA)"
        exit 1
    fi

    rm -rf zfs-auto-snapshot-master
    tar -xf "zfs-auto-snapshot-${ZSNAP_VERSION}.tar.gz" && cd zfs-auto-snapshot-master/ || exit 1

    if ! make install PREFIX=/usr; then
        echo "Error: installation failed!"
        exit 1
    fi

    cat > /usr/bin/zsnap << 'ZSNAP_EOF'
#!/bin/bash

detect_root_dataset() {
    local ds=""
    ds="$(awk '$2 == "/" && $3 == "zfs" {print $1; exit}' /proc/mounts 2>/dev/null)"
    if [ -z "$ds" ]; then
        ds="$(zfs list -H -o name,mountpoint 2>/dev/null | awk '$2 == "/" {print $1; exit}')"
    fi
    if [ -z "$ds" ]; then
        ds="$(zfs list -H -o name 2>/dev/null | head -n 1)"
    fi
    printf '%s' "$ds"
}

resolve_snapshot() {
    local arg="$1"
    if [[ "$arg" == *@* ]]; then
        printf '%s' "$arg"
        return 0
    fi
    local match=""
    match="$(zfs list -t snapshot -H -o name -s creation 2>/dev/null | awk -F@ -v s="$arg" '$2 == s {last=$0} END {print last}')"
    if [ -n "$match" ]; then
        printf '%s' "$match"
        return 0
    fi
    local root_ds
    root_ds="$(detect_root_dataset)"
    if [ -n "$root_ds" ]; then
        printf '%s@%s' "$root_ds" "$arg"
        return 0
    fi
    return 1
}

cmd="${1:-list}"
case "$cmd" in
    list|ls)
        shift 2>/dev/null || true
        zfs list -t snapshot -o name,used,refer,creation -s creation "$@"
        ;;
    save|create|snap)
        shift
        name="${1:-manual-$(date -u +%Y%m%d-%H%M%S)}"
        if [[ "$name" == *@* ]]; then
            target="$name"
        else
            ds="${2:-$(detect_root_dataset)}"
            if [ -z "$ds" ]; then
                echo "zsnap: no ZFS dataset found" >&2
                exit 1
            fi
            target="${ds}@${name}"
        fi
        zfs snapshot -r "$target" && echo "Created snapshot: $target"
        ;;
    auto)
        shift
        keep="${1:-10}"
        target="${2:-//}"
        exec /usr/sbin/zfs-auto-snapshot --verbose --label=bhl --keep="$keep" "$target"
        ;;
    back|rollback|restore)
        shift
        if [ -z "${1:-}" ]; then
            echo "Usage: zsnap back <snapshot|tag>" >&2
            exit 1
        fi
        snap="$(resolve_snapshot "$1")" || {
            echo "zsnap: snapshot '$1' not found" >&2
            exit 1
        }
        zfs rollback -r "$snap" && echo "Rolled back to: $snap"
        ;;
    del|rm|destroy)
        shift
        if [ -z "${1:-}" ]; then
            echo "Usage: zsnap del <snapshot|tag>" >&2
            exit 1
        fi
        snap="$(resolve_snapshot "$1")" || {
            echo "zsnap: snapshot '$1' not found" >&2
            exit 1
        }
        zfs destroy -r "$snap" && echo "Destroyed snapshot: $snap"
        ;;
    -h|--help|help)
        echo "Usage:"
        echo "  zsnap list [dataset]            List ZFS snapshots"
        echo "  zsnap save [tag] [dataset]      Create recursive snapshot"
        echo "  zsnap auto [keep] [dataset|//]  Run zfs-auto-snapshot with rotation"
        echo "  zsnap back <tag|dataset@tag>    Rollback dataset to snapshot"
        echo "  zsnap del  <tag|dataset@tag>    Destroy snapshot"
        echo "  zsnap <zfs-auto-snapshot args>  Forward flags to zfs-auto-snapshot"
        ;;
    -*)
        exec /usr/sbin/zfs-auto-snapshot "$@"
        ;;
    *)
        exec /usr/sbin/zfs-auto-snapshot "$@"
        ;;
esac
ZSNAP_EOF
    chmod 0755 /usr/bin/zsnap
    if [ ! -e /bin/zsnap ]; then
        ln -sfv /usr/bin/zsnap /bin/zsnap
    fi

    if ! type -p zfs-auto-snapshot zsnap &>/dev/null; then
        echo "Error: zfs-auto-snapshot or zsnap not found in PATH!"
        exit 1
    fi

    cd "$INITIAL_DIR" || exit 1
else
    echo "No archive found."
    echo "Try to re-run this script"
    exit 1
fi

rm -rf /sources/extra/zfs-auto-snapshot-master/
rm -f "/sources/extra/zfs-auto-snapshot-${ZSNAP_VERSION}.tar.gz"

echo "Successfully installed zfs-auto-snapshot-${ZSNAP_VERSION} and zsnap"
