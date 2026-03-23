#!/bin/bash
set -e
BACKEND="http://127.0.0.1:8081"
FRONTEND="http://localhost:5000"
PASS=0; FAIL=0

check() {
  local name="$1"; local url="$2"; local expect="$3"; local data="$4"
  if [ -n "$data" ]; then
    resp=$(curl -s --max-time 10 -X POST "$url" -H 'Content-Type: application/json' -d "$data" 2>/dev/null)
  else
    resp=$(curl -s --max-time 10 "$url" 2>/dev/null)
  fi
  if echo "$resp" | grep -q "$expect" 2>/dev/null; then
    echo "  ✓ $name"
    PASS=$((PASS+1))
  else
    echo "  ✗ $name (expected '$expect', got: ${resp:0:80})"
    FAIL=$((FAIL+1))
  fi
}

echo "=== Backend API tests ==="
check "version endpoint" "$BACKEND/api/version" "version_major"
check "search_nextflow_workflow (RNA-seq)" \
  "$BACKEND/api/ai_assistant/search_nextflow_workflow" \
  "success" \
  '{"user_intent":"RNA-seq differential expression"}'
check "search returns chain for multi-step" \
  "$BACKEND/api/ai_assistant/search_nextflow_workflow" \
  "chain" \
  '{"user_intent":"complete germline variant calling pipeline with QC"}'
check "domain-profile GET (anon)" \
  "$BACKEND/api/user/domain-profile" \
  "domains"
check "workflow catalog stats" \
  "$BACKEND/api/ai_assistant/workflow_catalog" \
  "total_workflows"

echo ""
echo "=== Frontend / Proxy tests ==="
check "frontend serves HTML" "$FRONTEND" "<!DOCTYPE html"
check "preflight endpoint" \
  "$FRONTEND/api/workflows/preflight" \
  "phases" \
  '{"workflowDefinition":{"parameters":[{"id":"genome","required":true}]},"parameters":{"genome":"GRCh38"}}'
check "preflight fails on missing required param" \
  "$FRONTEND/api/workflows/preflight" \
  "fail" \
  '{"workflowDefinition":{"parameters":[{"id":"genome","required":true}]},"parameters":{}}'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
