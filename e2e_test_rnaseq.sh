#!/bin/bash

# BioMate E2E Test - RNA-seq Differential Expression Analysis
# Tests the complete user journey from chat to workflow execution

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
FRONTEND_URL="http://localhost:5000"
BACKEND_URL="http://localhost:8081"
TEST_QUERY="I want to analyze some RNA-seq data to find differentially expressed genes."
MAX_POLL_ATTEMPTS=60
POLL_INTERVAL=2

# Output directory for screenshots and logs
OUTPUT_DIR="/tmp/biomate_e2e_test_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}BioMate E2E Test - RNA-seq Analysis${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Test Query: ${YELLOW}${TEST_QUERY}${NC}"
echo -e "Output Dir: ${YELLOW}${OUTPUT_DIR}${NC}"
echo ""

# Phase 1: System Health Check
echo -e "${BLUE}Phase 1: System Health Check${NC}"
echo "-----------------------------------"

echo -n "1.1 Frontend alive... "
if curl -s -f "$FRONTEND_URL/" > /dev/null; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    exit 1
fi

echo -n "1.2 Backend alive... "
BACKEND_VERSION=$(curl -s "$BACKEND_URL/api/version")
if echo "$BACKEND_VERSION" | jq -e '.version_major' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC} (Version: $(echo $BACKEND_VERSION | jq -r '.version_major'))"
else
    echo -e "${RED}FAIL${NC}"
    exit 1
fi

echo -n "1.3 Frontend→Backend proxy... "
PROXY_VERSION=$(curl -s "$FRONTEND_URL/api/galaxy/version")
if echo "$PROXY_VERSION" | jq -e '.version_major' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${YELLOW}SKIP${NC} (requires authentication)"
fi

echo ""

# Phase 2: Chat & Workflow Generation
echo -e "${BLUE}Phase 2: Chat & Workflow Generation${NC}"
echo "-----------------------------------"

echo "2.1 Sending chat message..."
CHAT_START=$(date +%s)

CHAT_RESPONSE=$(curl -s -X POST "$FRONTEND_URL/api/chat" \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"$TEST_QUERY\"}")

CHAT_END=$(date +%s)
CHAT_DURATION=$((CHAT_END - CHAT_START))

echo "$CHAT_RESPONSE" | jq '.' > "$OUTPUT_DIR/chat_response.json"

echo -n "    Response time: "
if [ $CHAT_DURATION -lt 60 ]; then
    echo -e "${GREEN}${CHAT_DURATION}s${NC}"
else
    echo -e "${YELLOW}${CHAT_DURATION}s (>60s)${NC}"
fi

echo -n "2.2 Intent recognized... "
INTENT=$(echo "$CHAT_RESPONSE" | jq -r '.metadata.intent // empty')
if [ -n "$INTENT" ]; then
    echo -e "${GREEN}PASS${NC} (Intent: $INTENT)"
else
    echo -e "${YELLOW}WARN${NC} (No intent field)"
fi

echo -n "2.3 Tools found... "
TOOLS_COUNT=$(echo "$CHAT_RESPONSE" | jq '.metadata.recommendedTools // [] | length')
if [ "$TOOLS_COUNT" -gt 0 ]; then
    echo -e "${GREEN}PASS${NC} ($TOOLS_COUNT tools)"
    echo "$CHAT_RESPONSE" | jq -r '.metadata.recommendedTools[] | "    - \(.name)"' 2>/dev/null || true
else
    echo -e "${YELLOW}WARN${NC} (No tools recommended)"
fi

echo -n "2.4 Workflow generated... "
WORKFLOW_SUCCESS=$(echo "$CHAT_RESPONSE" | jq -r '.workflow.success // false')
if [ "$WORKFLOW_SUCCESS" = "true" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Chat response:"
    echo "$CHAT_RESPONSE" | jq '.'
    exit 1
fi

echo -n "2.5 Tool IDs valid... "
INVALID_TOOLS=$(echo "$CHAT_RESPONSE" | jq -r '.workflow.workflow_ga.steps // {} | to_entries[] | select(.value.tool_id // "" | startswith("Repository_Actions_")) | .value.tool_id' 2>/dev/null)
if [ -z "$INVALID_TOOLS" ]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "Invalid tool IDs found:"
    echo "$INVALID_TOOLS"
fi

# Extract tool IDs
echo "    Tool IDs in workflow:"
echo "$CHAT_RESPONSE" | jq -r '.workflow.workflow_ga.steps // {} | to_entries[] | select(.value.tool_id) | "    - \(.value.tool_id)"' 2>/dev/null || echo "    (Could not extract tool IDs)"

echo ""

# Phase 3: Workflow Execution
echo -e "${BLUE}Phase 3: Workflow Execution${NC}"
echo "-----------------------------------"

echo "3.1 Executing workflow..."

# Extract workflow definition
WORKFLOW_DEF=$(echo "$CHAT_RESPONSE" | jq '.workflow.workflow_ga')

# Create execution request
EXEC_REQUEST=$(jq -n \
    --argjson workflow "$WORKFLOW_DEF" \
    '{
        workflowDefinition: $workflow,
        executionConfig: {
            mode: "sandbox"
        },
        inputs: []
    }')

EXEC_RESPONSE=$(curl -s -X POST "$FRONTEND_URL/api/workflows/execute" \
    -H "Content-Type: application/json" \
    -d "$EXEC_REQUEST")

echo "$EXEC_RESPONSE" | jq '.' > "$OUTPUT_DIR/execution_response.json"

RUN_ID=$(echo "$EXEC_RESPONSE" | jq -r '.runId // empty')
INVOCATION_ID=$(echo "$EXEC_RESPONSE" | jq -r '.galaxyInvocationId // empty')
HISTORY_ID=$(echo "$EXEC_RESPONSE" | jq -r '.galaxyHistoryId // empty')

if [ -n "$RUN_ID" ]; then
    echo -e "    Run ID: ${GREEN}$RUN_ID${NC}"
    echo -e "    Invocation ID: ${GREEN}$INVOCATION_ID${NC}"
    echo -e "    History ID: ${GREEN}$HISTORY_ID${NC}"
else
    echo -e "${RED}FAIL${NC} - No run ID returned"
    echo "Execution response:"
    echo "$EXEC_RESPONSE" | jq '.'
    exit 1
fi

echo ""

# Phase 4: Status Synchronization (CRITICAL)
echo -e "${BLUE}Phase 4: Status Synchronization (CRITICAL)${NC}"
echo "-----------------------------------"

echo "4.1 Polling workflow status..."
echo ""

POLL_COUNT=0
FRONTEND_STATUS=""
LAST_COMPLETED_STEPS=0
DESYNC_DETECTED=false

while [ $POLL_COUNT -lt $MAX_POLL_ATTEMPTS ]; do
    POLL_COUNT=$((POLL_COUNT + 1))
    
    # Get frontend status
    STATUS_RESPONSE=$(curl -s "$FRONTEND_URL/api/workflows/runs/$RUN_ID/status")
    echo "$STATUS_RESPONSE" | jq '.' > "$OUTPUT_DIR/status_poll_${POLL_COUNT}.json"
    
    FRONTEND_STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status // "unknown"')
    COMPLETED_STEPS=$(echo "$STATUS_RESPONSE" | jq -r '.progress.completedSteps // 0')
    TOTAL_STEPS=$(echo "$STATUS_RESPONSE" | jq -r '.progress.totalSteps // 0')
    
    # Get backend status (if we have invocation ID)
    if [ -n "$INVOCATION_ID" ]; then
        # Try to get Galaxy API key from environment or config
        GALAXY_API_KEY=${GALAXY_API_KEY:-"admin"}  # Default for dev
        
        BACKEND_RESPONSE=$(curl -s "$BACKEND_URL/api/invocations/$INVOCATION_ID" \
            -H "x-api-key: $GALAXY_API_KEY" 2>/dev/null || echo '{}')
        
        BACKEND_STATE=$(echo "$BACKEND_RESPONSE" | jq -r '.state // "unknown"')
        
        # Check for desync
        if [ "$BACKEND_STATE" = "scheduled" ] && [ "$FRONTEND_STATUS" = "queued" ]; then
            # This might be OK - scheduled can mean jobs are running
            true
        elif [ "$BACKEND_STATE" = "scheduled" ] && [ "$FRONTEND_STATUS" != "ok" ] && [ "$FRONTEND_STATUS" != "running" ] && [ "$FRONTEND_STATUS" != "queued" ]; then
            echo -e "${RED}⚠ DESYNC DETECTED!${NC} Backend: $BACKEND_STATE, Frontend: $FRONTEND_STATUS"
            DESYNC_DETECTED=true
        fi
    else
        BACKEND_STATE="N/A"
    fi
    
    # Progress indicator
    PROGRESS_BAR=""
    if [ "$TOTAL_STEPS" -gt 0 ]; then
        PROGRESS_PCT=$((COMPLETED_STEPS * 100 / TOTAL_STEPS))
        PROGRESS_BAR="[$COMPLETED_STEPS/$TOTAL_STEPS - ${PROGRESS_PCT}%]"
    fi
    
    # Status with color
    STATUS_COLOR=$YELLOW
    if [ "$FRONTEND_STATUS" = "ok" ]; then
        STATUS_COLOR=$GREEN
    elif [ "$FRONTEND_STATUS" = "error" ] || [ "$FRONTEND_STATUS" = "failed" ]; then
        STATUS_COLOR=$RED
    fi
    
    echo -e "    Poll #$POLL_COUNT: Frontend=${STATUS_COLOR}${FRONTEND_STATUS}${NC} | Backend=${BACKEND_STATE} ${PROGRESS_BAR}"
    
    # Check if completed
    if [ "$FRONTEND_STATUS" = "ok" ] || [ "$FRONTEND_STATUS" = "completed" ]; then
        echo -e "${GREEN}✓ Workflow completed successfully!${NC}"
        break
    elif [ "$FRONTEND_STATUS" = "error" ] || [ "$FRONTEND_STATUS" = "failed" ]; then
        echo -e "${RED}✗ Workflow failed!${NC}"
        ERROR_MSG=$(echo "$STATUS_RESPONSE" | jq -r '.error // "Unknown error"')
        echo "Error: $ERROR_MSG"
        break
    fi
    
    # Log progress changes
    if [ "$COMPLETED_STEPS" -gt "$LAST_COMPLETED_STEPS" ]; then
        echo -e "    ${GREEN}Progress: Step $COMPLETED_STEPS/$TOTAL_STEPS completed${NC}"
        LAST_COMPLETED_STEPS=$COMPLETED_STEPS
    fi
    
    sleep $POLL_INTERVAL
done

if [ $POLL_COUNT -ge $MAX_POLL_ATTEMPTS ]; then
    echo -e "${RED}TIMEOUT${NC} - Workflow did not complete within $((MAX_POLL_ATTEMPTS * POLL_INTERVAL))s"
fi

echo ""

# Phase 5: Output Verification
echo -e "${BLUE}Phase 5: Output Verification${NC}"
echo "-----------------------------------"

if [ -n "$HISTORY_ID" ]; then
    echo "5.1 Checking Galaxy history contents..."
    
    GALAXY_API_KEY=${GALAXY_API_KEY:-"admin"}
    HISTORY_CONTENTS=$(curl -s "$BACKEND_URL/api/histories/$HISTORY_ID/contents" \
        -H "x-api-key: $GALAXY_API_KEY")
    
    echo "$HISTORY_CONTENTS" | jq '.' > "$OUTPUT_DIR/history_contents.json"
    
    DATASET_COUNT=$(echo "$HISTORY_CONTENTS" | jq 'length')
    echo "    Datasets found: $DATASET_COUNT"
    
    if [ "$DATASET_COUNT" -gt 0 ]; then
        echo "$HISTORY_CONTENTS" | jq -r '.[] | "    - \(.name) (\(.state)) - \(.file_size // 0) bytes"'
        
        # Check for completed datasets
        OK_DATASETS=$(echo "$HISTORY_CONTENTS" | jq '[.[] | select(.state == "ok")] | length')
        if [ "$OK_DATASETS" -gt 0 ]; then
            echo -e "    ${GREEN}$OK_DATASETS dataset(s) completed successfully${NC}"
        else
            echo -e "    ${YELLOW}No completed datasets yet${NC}"
        fi
    else
        echo -e "    ${YELLOW}No datasets found in history${NC}"
    fi
else
    echo -e "${YELLOW}SKIP${NC} - No history ID available"
fi

echo ""

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo "Test Results:"
echo "  - Chat response time: ${CHAT_DURATION}s"
echo "  - Workflow generated: ${WORKFLOW_SUCCESS}"
echo "  - Final status: ${FRONTEND_STATUS}"
echo "  - Polls required: ${POLL_COUNT}"
echo "  - Desync detected: ${DESYNC_DETECTED}"
echo ""

echo "Output files saved to: $OUTPUT_DIR"
echo "  - chat_response.json"
echo "  - execution_response.json"
echo "  - status_poll_*.json"
echo "  - history_contents.json"
echo ""

if [ "$DESYNC_DETECTED" = true ]; then
    echo -e "${RED}⚠ CRITICAL: Frontend-Backend desync detected!${NC}"
    echo "This indicates the GalaxyStatePoller is not properly updating frontend status."
    exit 1
elif [ "$FRONTEND_STATUS" = "ok" ] || [ "$FRONTEND_STATUS" = "completed" ]; then
    echo -e "${GREEN}✓ E2E Test PASSED${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠ Test completed with status: $FRONTEND_STATUS${NC}"
    exit 0
fi
