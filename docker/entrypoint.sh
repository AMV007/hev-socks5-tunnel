#!/bin/sh

TUN="${TUN:-tun0}"
MTU="${MTU:-8500}"
IPV4="${IPV4:-198.18.0.1}"
IPV6="${IPV6:-}"

CONFIG_ROUTES="${CONFIG_ROUTES:-1}"

TABLE="${TABLE:-20}"
if [ "${CONFIG_ROUTES}" = "0" ]; then
  MARK="${MARK:-0}"
else
  MARK="${MARK:-438}"
fi

SOCKS5_ADDR="${SOCKS5_ADDR:-172.17.0.1}"
SOCKS5_PORT="${SOCKS5_PORT:-1080}"
SOCKS5_USERNAME="${SOCKS5_USERNAME:-}"
SOCKS5_PASSWORD="${SOCKS5_PASSWORD:-}"
SOCKS5_UDP_MODE="${SOCKS5_UDP_MODE:-udp}"
SOCKS5_UDP_ADDR="${SOCKS5_UDP_ADDR:-}"

IPV4_INCLUDED_ROUTES="${IPV4_INCLUDED_ROUTES:-0.0.0.0/0}"
IPV4_EXCLUDED_ROUTES="${IPV4_EXCLUDED_ROUTES:-}"

LOG_LEVEL="${LOG_LEVEL:-warn}"

LOCAL_ROUTE="${LOCAL_ROUTE:-}"

trap '' SIGTERM SIGINT

config_file() {
  cat > /hs5t.yml << EOF
misc:
  log-level: '${LOG_LEVEL}'
tunnel:
  name: '${TUN}'
  mtu: ${MTU}
  ipv4: '${IPV4}'
  ipv6: '${IPV6}'
  post-up-script: '/route.sh'
socks5:
  address: '${SOCKS5_ADDR}'
  port: ${SOCKS5_PORT}
  udp: '${SOCKS5_UDP_MODE}'
  mark: ${MARK}
EOF

  if [ -n "${SOCKS5_USERNAME}" ]; then
      echo "  username: '${SOCKS5_USERNAME}'" >> /hs5t.yml
  fi

  if [ -n "${SOCKS5_PASSWORD}" ]; then
      echo "  password: '${SOCKS5_PASSWORD}'" >> /hs5t.yml
  fi

  if [ -n "${SOCKS5_UDP_ADDR}" ]; then
      echo "  udp-address: '${SOCKS5_UDP_ADDR}'" >> /hs5t.yml
  fi
}

config_route() {
  echo "#!/bin/sh" > /route.sh
  chmod +x /route.sh

  if [ "${CONFIG_ROUTES}" = "0" ]; then
    echo "config routes 0"
    return
  fi

  echo "ip route del default" >> /route.sh
  echo "ip route add default via ${IPV4} dev ${TUN} metric 1" >> /route.sh
  if [ -n "$LOCAL_ROUTE" ]; then
    echo "$LOCAL_ROUTE" >> /route.sh
  fi
}

NUM_CORES=$(nproc)
if [ "$NUM_CORES" -gt 2 ]; then
  # because core 0 is overloaded by other processes, and this is single process app, let's try use less busy core
  VPN_CORE=1
else
  VPN_CORE=0
fi

run() {
  echo "selected VPN core: $VPN_CORE"
  config_file
  config_route
  echo "echo 1 > /success" >> /route.sh

  echo "[DEBUG] IP addresses:"
  ip addr show

  echo "[DEBUG] Routes:"
  ip route show

  echo "[DEBUG] Rules (ip rule):"
  ip rule show

  echo "[DEBUG] Interfaces:"
  ip link show

  echo "$(cat /route.sh)"

  taskset -c "$VPN_CORE" hev-socks5-tunnel /hs5t.yml &
  TUNNEL_PID=$!
  trap "echo 'Stopping...'; kill -TERM $TUNNEL_PID 2>/dev/null; wait $TUNNEL_PID 2>/dev/null; exit 0" SIGTERM SIGINT
  wait $TUNNEL_PID
}

run || exit 1
