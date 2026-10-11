#!/bin/bash

IFACE=""
for iface in /sys/class/net/*; do
    name=$(basename "$iface")
    case "$name" in
        eth*|enp*|eno*|ens*)
            IFACE="$name"
            break
            ;;
    esac
done

if [ -z "$IFACE" ]; then
    echo "ERROR: No suitable network interface found!"
    echo "Available interfaces:"
    ls /sys/class/net/
    exit 1
fi

echo "Using interface: $IFACE"

read -p "Enter IP address with prefix (e.g. 192.168.31.210/24): " IP_ADDR

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
GATEWAY="${o1}.${o2}.${o3}.1"

echo "Network: $NETWORK"
echo "Gateway: $GATEWAY"

echo "Bringing up $IFACE..."
ip link set "$IFACE" up

echo "Assigning IP $IP_ADDR..."
ip addr add "$IP_ADDR" dev "$IFACE" 2>/dev/null || true

echo "Adding route to $NETWORK..."
ip route add "$NETWORK" dev "$IFACE" 2>/dev/null || true

echo "Adding default gateway $GATEWAY..."
ip route add default via "$GATEWAY" dev "$IFACE" 2>/dev/null || true

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
