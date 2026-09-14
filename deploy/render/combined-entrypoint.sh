#!/bin/sh
set -eu

mkdir -p "$HOME/.omnigent" /data/artifacts /data/omniroute

python /usr/local/bin/omni-state-backup &
backup_pid=$!

PORT=8000 HOST=127.0.0.1 python /app/entrypoint.py &
server_pid=$!

PORT=20128 HOSTNAME=127.0.0.1 OMNIROUTE_BASE_PATH=/router \
  NEXT_PUBLIC_BASE_URL=https://omniroute.drksci.com/router DATA_DIR=/data/omniroute \
  omniroute &
router_pid=$!

cleanup() {
  kill "$server_pid" "$router_pid" "$backup_pid" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

until curl -fsS http://127.0.0.1:8000/health >/dev/null; do sleep 5; done

if [ -n "${OMNIROUTE_API_KEY:-}" ] && [ ! -f "$HOME/.omnigent/config.yaml" ]; then
  cat > "$HOME/.omnigent/config.yaml" <<EOF
providers:
  omniroute:
    kind: gateway
    default: [openai]
    openai:
      base_url: http://127.0.0.1:20128/router/v1
      api_key_ref: env:OMNIROUTE_API_KEY
      wire_api: responses
EOF
  chmod 0600 "$HOME/.omnigent/config.yaml"
fi

until [ -f "$HOME/.omnigent/auth_tokens.json" ]; do
  echo "Combined host waiting for interactive login. Run in the service shell:" >&2
  echo "  omnigent login http://127.0.0.1:8000" >&2
  echo "  claude" >&2
  echo "  codex" >&2
  echo "  agy" >&2
  sleep 30
done

omnigent host --server http://127.0.0.1:8000 --non-interactive &
host_pid=$!

exec nginx -g 'daemon off;'
