#!/usr/bin/env bash
# Local end-to-end smoke test for the BioMate vLLM HTTP-client path.
#
# Brings up infra/vllm/docker-compose.local.yml, waits for /health, asserts
# the regulatory_llm_v6 adapter is registered, POSTs a tiny chat completion,
# and (unless KEEP_UP=1) tears down. Exit 0 on full pass.
#
# Usage:
#   ./infra/vllm/smoke-test.sh              # full cycle, tears down
#   KEEP_UP=1 ./infra/vllm/smoke-test.sh    # leave compose running (for pytest)
#
# Requires: docker compose, jq, curl, an NVIDIA GPU + nvidia-container-toolkit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.local.yml"
BASE_URL="${VLLM_BASE_URL:-http://localhost:8000}"
ADAPTER="${REGULATORY_LLM_ADAPTER_NAME:-regulatory_llm_v6}"
HEALTH_TIMEOUT_S="${HEALTH_TIMEOUT_S:-600}"  # cold boot can be 5+ minutes
KEEP_UP="${KEEP_UP:-0}"

log() { printf '[smoke] %s\n' "$*"; }
die() { printf '[smoke][FAIL] %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ "$KEEP_UP" == "1" ]]; then
    log "KEEP_UP=1 — leaving compose stack running"
    return
  fi
  log "tearing down compose stack"
  docker compose -f "$COMPOSE_FILE" down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

command -v jq >/dev/null   || die "jq required"
command -v curl >/dev/null || die "curl required"

log "starting compose stack (cold boot can take 5-10 min)"
docker compose -f "$COMPOSE_FILE" up -d --build

log "waiting up to ${HEALTH_TIMEOUT_S}s for $BASE_URL/health"
deadline=$(( $(date +%s) + HEALTH_TIMEOUT_S ))
until curl -fsS "$BASE_URL/health" >/dev/null 2>&1; do
  if (( $(date +%s) > deadline )); then
    log "--- last 60 container log lines ---"
    docker compose -f "$COMPOSE_FILE" logs --tail=60 vllm || true
    die "vLLM /health did not become ready within ${HEALTH_TIMEOUT_S}s"
  fi
  sleep 5
done
log "/health OK"

log "listing /v1/models"
models_json="$(curl -fsS "$BASE_URL/v1/models")"
echo "$models_json" | jq -r '.data[].id' | sed 's/^/[smoke]   model: /'

echo "$models_json" | jq -e --arg n "$ADAPTER" '.data[] | select(.id == $n)' >/dev/null \
  || die "expected adapter '$ADAPTER' not listed in /v1/models"
log "adapter '$ADAPTER' present in /v1/models"

log "POST /v1/chat/completions against '$ADAPTER'"
resp="$(curl -fsS -X POST "$BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${VLLM_API_KEY:-EMPTY}" \
  -d "$(jq -n --arg m "$ADAPTER" '{
    model: $m,
    messages: [
      {role: "system", content: "You are a brief assistant."},
      {role: "user",   content: "/no_think\nReply with the single word: ack"}
    ],
    max_tokens: 16,
    temperature: 0.0,
    chat_template_kwargs: {enable_thinking: false}
  }')")"

content="$(echo "$resp" | jq -r '.choices[0].message.content // empty')"
[[ -n "$content" ]] || { echo "$resp" | jq . >&2; die "empty completion content"; }
log "completion: ${content:0:120}"

log "PASS — vLLM HTTP-client path is functional"
exit 0
