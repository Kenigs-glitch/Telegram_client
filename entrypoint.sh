#!/bin/bash
set -e

# If proxy is configured via env vars, set up redsocks for transparent proxying
if [ -n "${PROXY_HOST:-}" ] && [ -n "${PROXY_PORT:-}" ]; then
    # Map protocol to redsocks type: http → http-connect, socks5 → socks5
    PROTO="${PROXY_TYPE:-socks5}"
    case "$PROTO" in
        http|https)  REDSOCKS_TYPE="http-connect" ;;
        socks4)      REDSOCKS_TYPE="socks4" ;;
        *)           REDSOCKS_TYPE="socks5" ;;
    esac

    echo "Setting up transparent proxy: ${PROXY_HOST}:${PROXY_PORT} (${REDSOCKS_TYPE})"

    # Write redsocks config
    cat > /etc/redsocks.conf <<EOF
base {
    log_debug = off;
    log_info = on;
    daemon = yes;
    redirector = iptables;
}
redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = ${PROXY_HOST};
    port = ${PROXY_PORT};
    type = ${REDSOCKS_TYPE};
    login = "${PROXY_USER:-}";
    password = "${PROXY_PASS:-}";
}
EOF

    # Start redsocks
    redsocks -c /etc/redsocks.conf

    # iptables: redirect all outgoing TCP (except to proxy itself and localhost) through redsocks
    iptables -t nat -N REDSOCKS 2>/dev/null || iptables -t nat -F REDSOCKS
    iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A REDSOCKS -d "${PROXY_HOST}" -j RETURN
    iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports 12345
    iptables -t nat -A OUTPUT -p tcp -j REDSOCKS

    echo "Transparent proxy active"
else
    echo "No proxy configured, direct connection"
fi

# Launch Telegram
exec ./Telegram "$@"
