#!/usr/bin/env bash

set -euxo pipefail

# Find the server IP directory
SERVER_IP=""
shopt -s nullglob
for dir in configs/*/; do
    if [[ -d "$dir" ]]; then
        dir=${dir%/}
        dir=${dir##*/}
        if [[ "$dir" != "localhost" ]]; then
            SERVER_IP="$dir"
            break
        fi
    fi
done
shopt -u nullglob

if [[ -z "$SERVER_IP" ]]; then
    echo "Error: No server IP directory found in configs/"
    exit 1
fi

echo "Using server IP: $SERVER_IP"

# Check if Apple mobile config files exist before validating
if ls ./configs/$SERVER_IP/wireguard/apple/*/*.mobileconfig 1> /dev/null 2>&1; then
    xmllint --noout ./configs/$SERVER_IP/wireguard/apple/*/*.mobileconfig
else
    echo "No Apple mobile config files found, skipping xmllint validation"
fi

crudini --set configs/$SERVER_IP/wireguard/user1.conf Interface Table off

wg-quick up configs/$SERVER_IP/wireguard/user1.conf

wg

ifconfig user1

ip route add 172.16.0.1/32 dev user1

fping -t 900 -c3 -r3 -Dse $SERVER_IP 172.16.0.1

wg | grep "latest handshake"

host google.com 172.16.0.1

echo "WireGuard tests passed"

wg-quick down configs/$SERVER_IP/wireguard/user1.conf
