#!/bin/sh
set -eu

: "${OMNIGENT_SERVER_URL:?OMNIGENT_SERVER_URL is required}"

phase=${1:-}
harness=${2:-}
shift 2 2>/dev/null || true

case "$phase" in
  plan) model=${OMNIROUTE_PLAN_MODEL:-auto/reasoning:pro} ;;
  work) model=${OMNIROUTE_WORK_MODEL:-auto/coding:cheap} ;;
  review) model=${OMNIROUTE_REVIEW_MODEL:-auto/coding:pro} ;;
  quick-fix) model=${OMNIROUTE_QUICK_FIX_MODEL:-auto/coding:fast} ;;
  *)
    echo "usage: omni-phase {plan|work|review|quick-fix} {claude|codex|agy|antigravity|pi} [args...]" >&2
    exit 2
    ;;
esac

case "$harness" in
  agy|antigravity) command=antigravity ;;
  claude|codex|pi) command=$harness ;;
  *)
    echo "unsupported harness: $harness" >&2
    exit 2
    ;;
esac

exec omnigent "$command" --server "$OMNIGENT_SERVER_URL" --model "$model" "$@"
