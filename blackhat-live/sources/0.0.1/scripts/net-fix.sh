#!/bin/bash

MODE=""
IFACE=""

if [ -n "${1:-}" ]; then
    case "$1" in
        eth|ethernet|1)
            MODE="eth"
            IFACE="${2:-}"
            ;;
        wifi|wlan|wireless|2)
            MODE="wifi"
            IFACE="${2:-}"
            ;;
        *)
            IFACE="$1"
            if [ -d "/sys/class/net/$IFACE/wireless" ] || [ -d "/sys/class/net/$IFACE/phy80211" ]; then
                MODE="wifi"
            else
                case "$IFACE" in
                    wl*) MODE="wifi" ;;
                    *) MODE="eth" ;;
                esac
            fi
            ;;
    esac
fi

if [ -z "$MODE" ]; then
    echo "Select connection type:"
    echo "  1) Ethernet"
    echo "  2) Wi-Fi"
    read -r -p "Choice [1/2]: " MODE_ANS
    case "$MODE_ANS" in
        2|wifi|wlan|w|W)
            MODE="wifi"
            ;;
        *)
            MODE="eth"
            ;;
    esac
fi

if [ -z "$IFACE" ]; then
    for path in /sys/class/net/*; do
        name=$(basename "$path")
        [ "$name" = "lo" ] && continue
        if [ "$MODE" = "wifi" ]; then
            if [ -d "$path/wireless" ] || [ -d "$path/phy80211" ]; then
                IFACE="$name"
                break
            fi
            case "$name" in
                wlan*|wlp*|wlo*|wlx*)
                    IFACE="$name"
                    break
                    ;;
            esac
        else
            case "$name" in
                eth*|enp*|eno*|ens*)
                    IFACE="$name"
                    break
                    ;;
            esac
        fi
    done
fi

if [ -z "$IFACE" ]; then
    echo "Available interfaces:"
    ls /sys/class/net/
    read -r -p "Enter interface name: " IFACE
fi

if [ -z "$IFACE" ] || [ ! -d "/sys/class/net/$IFACE" ]; then
    echo "ERROR: No suitable network interface found!"
    echo "Available interfaces:"
    ls /sys/class/net/
    exit 1
fi

echo "Using interface: $IFACE ($MODE)"

if [ "$MODE" = "wifi" ]; then
    if ! command -v wpa_supplicant >/dev/null 2>&1; then
        echo "ERROR: wpa_supplicant is not installed!"
        exit 1
    fi

    if command -v rfkill >/dev/null 2>&1; then
        rfkill unblock wifi 2>/dev/null || true
    fi

    ip link set "$IFACE" up 2>/dev/null || true

    read -r -p "Enter Wi-Fi SSID: " WIFI_SSID
    if [ -z "$WIFI_SSID" ]; then
        echo "ERROR: SSID cannot be empty!"
        exit 1
    fi

    read -r -p "Enter Wi-Fi Password (leave empty for open network): " WIFI_PASS

    mkdir -p /etc/wpa_supplicant /run/wpa_supplicant
    WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
    WPA_IFACE_CONF="/etc/wpa_supplicant/wpa_supplicant-${IFACE}.conf"

    if [ -z "$WIFI_PASS" ]; then
        cat > "$WPA_CONF" << EOF
ctrl_interface=/run/wpa_supplicant
update_config=1

network={
    ssid="${WIFI_SSID}"
    key_mgmt=NONE
}
EOF
    else
        if [ "${#WIFI_PASS}" -lt 8 ] || [ "${#WIFI_PASS}" -gt 63 ]; then
            echo "ERROR: WPA password must be between 8 and 63 characters!"
            exit 1
        fi
        if command -v wpa_passphrase >/dev/null 2>&1; then
            {
                echo "ctrl_interface=/run/wpa_supplicant"
                echo "update_config=1"
                echo ""
                wpa_passphrase "$WIFI_SSID" "$WIFI_PASS" | grep -v '^[[:space:]]*#psk='
            } > "$WPA_CONF"
        else
            cat > "$WPA_CONF" << EOF
ctrl_interface=/run/wpa_supplicant
update_config=1

network={
    ssid="${WIFI_SSID}"
    psk="${WIFI_PASS}"
}
EOF
        fi
    fi

    chmod 600 "$WPA_CONF"
    cp "$WPA_CONF" "$WPA_IFACE_CONF"
    chmod 600 "$WPA_IFACE_CONF"

    pkill -f "wpa_supplicant.*${IFACE}" 2>/dev/null || true
    rm -f "/run/wpa_supplicant/${IFACE}" 2>/dev/null || true

    echo "Starting wpa_supplicant on $IFACE..."
    if ! wpa_supplicant -B -i "$IFACE" -c "$WPA_CONF"; then
        echo "ERROR: Failed to start wpa_supplicant on $IFACE!"
        exit 1
    fi

    echo "Waiting for Wi-Fi connection to '$WIFI_SSID'..."
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if command -v wpa_cli >/dev/null 2>&1; then
            if wpa_cli -i "$IFACE" status 2>/dev/null | grep -q "^wpa_state=COMPLETED"; then
                echo "Wi-Fi connected!"
                break
            fi
        elif [ "$(cat "/sys/class/net/$IFACE/carrier" 2>/dev/null || echo 0)" = "1" ]; then
            echo "Wi-Fi carrier detected!"
            break
        fi
        sleep 1
    done
fi

read -r -p "Enter IP address with prefix (e.g. 192.168.31.210/24): " IP_ADDR

if [ -z "$IP_ADDR" ]; then
    echo "ERROR: No IP address provided!"
    exit 1
fi

IP="${IP_ADDR%/*}"
PREFIX="${IP_ADDR#*/}"

if [ "$IP" = "$IP_ADDR" ]; then
    echo "ERROR: Invalid format. Use IP/prefix (e.g. 192.168.31.210/24)"
    exit 1
fi

IFS='.' read -r o1 o2 o3 o4 <<< "$IP"
NETWORK="${o1}.${o2}.${o3}.0/${PREFIX}"
DEFAULT_GW="${o1}.${o2}.${o3}.1"

read -r -p "Enter Gateway [${DEFAULT_GW}]: " GATEWAY
GATEWAY="${GATEWAY:-$DEFAULT_GW}"

read -r -p "Enter DNS servers [1.1.1.1 8.8.8.8]: " DNS_SERVERS
DNS_SERVERS="${DNS_SERVERS:-1.1.1.1 8.8.8.8}"

echo "Network: $NETWORK"
echo "Gateway: $GATEWAY"

echo "Bringing up $IFACE..."
ip link set "$IFACE" up

echo "Assigning IP $IP_ADDR..."
ip addr flush dev "$IFACE" 2>/dev/null || true
ip addr add "$IP_ADDR" dev "$IFACE" 2>/dev/null || true

echo "Adding route to $NETWORK..."
ip route replace "$NETWORK" dev "$IFACE" 2>/dev/null || true

echo "Adding default gateway $GATEWAY..."
ip route replace default via "$GATEWAY" dev "$IFACE" 2>/dev/null || true

: > /etc/resolv.conf
for ns in $DNS_SERVERS; do
    echo "nameserver $ns" >> /etc/resolv.conf
done

echo ""
echo "=== Network configuration ==="
ip a show "$IFACE"
echo ""
echo "=== Routes ==="
ip route
echo ""
echo "=== DNS ==="
cat /etc/resolv.conf
echo ""
echo "Done."
