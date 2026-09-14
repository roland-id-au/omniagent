#!/bin/sh
set -eu

: "${OMNIGENT_SERVER_URL:?OMNIGENT_SERVER_URL is required}"
mkdir -p "${HOME}/.omnigent"

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
