#!/bin/sh
set -eu

: "${OMNIGENT_SERVER_URL:?OMNIGENT_SERVER_URL is required}"
: "${OMNIGENT_HOST_USERNAME:=admin}"
: "${OMNIGENT_HOST_PASSWORD:?OMNIGENT_HOST_PASSWORD is required}"

mkdir -p "${HOME}/.omnigent"

until curl -fsS "${OMNIGENT_SERVER_URL%/}/health" >/dev/null; do
  sleep 5
done

# Authenticate once in the non-interactive Render worker. The refresh grant
# persists on the worker disk for subsequent restarts.
if [ ! -f "${HOME}/.omnigent/auth_tokens.json" ]; then
  printf '%s\n%s\n' "$OMNIGENT_HOST_USERNAME" "$OMNIGENT_HOST_PASSWORD" \
    | omnigent login "$OMNIGENT_SERVER_URL"
fi

exec omnigent host --server "$OMNIGENT_SERVER_URL" --non-interactive
