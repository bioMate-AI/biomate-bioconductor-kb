#!/usr/bin/env bash
# test_smart_file_detection.sh — verify the smart file input detection fix works
# on a deployed environment. Run after sync_to_dev.sh / deploy.sh.
#
# Usage:
#   BIOMATE_URL=https://test.stage-public.biomate.ai \
#   E2E_FIXTURE_PASSWORD=BioMate2026! \
#   E2E_TEST_TOKEN=test-e2e-token-12345 \
#   bash scripts/test_smart_file_detection.sh

set -euo pipefail

BIOMATE_URL="${BIOMATE_URL:-https://dev-public.biomate.ai}"
EMAIL="lifeifei163361@163.com"
PASSWORD="${E2E_FIXTURE_PASSWORD:-WpmFixture!2026}"
E2E_TOKEN="${E2E_TEST_TOKEN:-biomate-e2e-bypass-token-dev-only}"

echo "=== Smart File Input Detection Test ==="
echo "Target: $BIOMATE_URL"
echo ""

# 1. Login
echo "[1/4] Logging in..."
TOKEN=$(curl -s -X POST "$BIOMATE_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -H "x-e2e-test-token: $E2E_TOKEN" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
echo "      ✅ Login OK (token: ${TOKEN:0:20}...)"

# 2. Call generate_workflow for differentialabundance (no file params provided)
echo "[2/4] Calling generate_workflow for DESeq2 (no files)..."
RESPONSE=$(curl -s -X POST "$BIOMATE_URL/api/ai_assistant/generate_workflow" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-e2e-test-token: $E2E_TOKEN" \
  -d '{"request_text": "Run differential expression analysis using DESeq2 with nf-core/differentialabundance"}')

WF_NAME=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('workflow_name','?'))")
IS_VALID=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('validation',{}).get('is_valid','?'))")
MISSING=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('missing_file_inputs','NOT_PRESENT'))")
ISSUES=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('validation',{}).get('issues',[])))")

echo "      Workflow:         $WF_NAME"
echo "      is_valid:         $IS_VALID"
echo "      missing_file_inputs: $MISSING"
echo "      blocking issues:  $ISSUES"
echo ""

# 3. Assertions
PASS=true

if echo "$MISSING" | grep -q "NOT_PRESENT"; then
  echo "❌ FAIL: missing_file_inputs not in response — fix not deployed?"
  PASS=false
elif [ "$MISSING" = "[]" ]; then
  echo "❌ FAIL: missing_file_inputs is empty — should have detected samplesheet/matrix"
  PASS=false
else
  echo "✅ PASS: missing_file_inputs detected: $MISSING"
fi

if [ "$IS_VALID" = "True" ] || [ "$IS_VALID" = "true" ]; then
  echo "❌ FAIL: validation.is_valid should be False when file inputs are missing"
  PASS=false
elif [ "$IS_VALID" = "False" ] || [ "$IS_VALID" = "false" ]; then
  echo "✅ PASS: validation.is_valid=False (Run button will be blocked)"
else
  echo "⚠️  WARN: unexpected is_valid value: $IS_VALID"
fi

if [ "$ISSUES" = "0" ]; then
  echo "❌ FAIL: no blocking issues found in validation.issues"
  PASS=false
else
  echo "✅ PASS: $ISSUES blocking issue(s) in validation.issues"
fi

# 4. ADMET should NOT be blocked (no file params)
echo "[3/4] Calling generate_workflow for ADMET (SMILES inline — should NOT be blocked)..."
ADMET=$(curl -s -X POST "$BIOMATE_URL/api/ai_assistant/generate_workflow" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-e2e-test-token: $E2E_TOKEN" \
  -d '{"request_text": "Run ADMET profiling for CC(=O)Oc1ccccc1C(=O)O"}')

ADMET_MISSING=$(echo "$ADMET" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('missing_file_inputs','NOT_PRESENT'))")
ADMET_VALID=$(echo "$ADMET" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('validation',{}).get('is_valid','?'))")

echo "      missing_file_inputs: $ADMET_MISSING"
echo "      is_valid: $ADMET_VALID"

if [ "$ADMET_MISSING" = "[]" ] && { [ "$ADMET_VALID" = "True" ] || [ "$ADMET_VALID" = "true" ]; }; then
  echo "✅ PASS: ADMET not blocked (SMILES provided, no file params missing)"
else
  echo "⚠️  WARN: ADMET result unexpected — missing=$ADMET_MISSING valid=$ADMET_VALID"
fi

echo ""
echo "[4/4] Summary:"
if [ "$PASS" = "true" ]; then
  echo "🎉 ALL ASSERTIONS PASSED — smart file detection is working correctly"
else
  echo "❌ SOME ASSERTIONS FAILED — check above output"
  exit 1
fi
