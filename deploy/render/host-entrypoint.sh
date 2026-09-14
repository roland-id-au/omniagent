#!/bin/sh
set -eu

: "${OMNIGENT_SERVER_URL:?OMNIGENT_SERVER_URL is required}"
mkdir -p "${HOME}/.omnigent"

if [ -n "${OMNIROUTE_BASE_URL:-}" ] && [ -n "${OMNIROUTE_API_KEY:-}" ] \
  && [ ! -f "${HOME}/.omnigent/config.yaml" ]; then
  cat > "${HOME}/.omnigent/config.yaml" <<EOF
providers:
  omniroute:
    kind: gateway
    default: [openai]
    openai:
      base_url: ${OMNIROUTE_BASE_URL}
      api_key_ref: env:OMNIROUTE_API_KEY
      wire_api: responses
EOF
  chmod 0600 "${HOME}/.omnigent/config.yaml"
fi

until curl -fsS "${OMNIGENT_SERVER_URL%/}/health" >/dev/null; do
  sleep 5
done

# Interactive CLI logins must happen in a Render shell. The worker remains
# alive while those credentials are written to the persistent host disk.
while [ ! -f "${HOME}/.omnigent/auth_tokens.json" ]; do
  echo "Render host waiting for interactive login. Open a shell and run:" >&2
  echo "  omnigent login ${OMNIGENT_SERVER_URL}" >&2
  echo "  claude" >&2
  echo "  codex" >&2
  echo "  agy" >&2
  sleep 30
done

exec omnigent host --server "$OMNIGENT_SERVER_URL" --non-interactive
