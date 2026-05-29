#!/bin/bash
# Spot interruption monitor for BioMate vLLM nodes.
#
# AWS gives 120s notice on Spot Instance reclamation via IMDSv2 metadata.
# On notice:
#   1. Deregister this instance from the ALB target group immediately
#      (so no new requests arrive)
#   2. Poll vLLM /metrics for vllm_running_requests until 0 (in-flight drain)
#   3. SIGTERM the vLLM process at T-30s (worst-case fallback if drain stalls)
#
# Total in-flight loss: ≤ 30s. A customer-facing single failed regenerate
# is the only impact; their retry hits the ASG's on-demand replacement.

set -uo pipefail

# Config
IMDS="http://169.254.169.254/latest/meta-data"
SPOT_ACTION_URL="$IMDS/spot/instance-action"
INSTANCE_ID_URL="$IMDS/instance-id"
LOCAL_VLLM="http://localhost:${VLLM_PORT:-8000}"
POLL_INTERVAL_S=5
DRAIN_GRACE_S=90       # max wait for in-flight drain before SIGTERM
SIGTERM_LEAD_S=30      # SIGTERM this many seconds before the AWS reclamation

# IMDSv2 requires a token
get_token() {
  curl -sf -X PUT "$IMDS/../api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null
}

get_instance_id() {
  local tok="$1"
  curl -sf -H "X-aws-ec2-metadata-token: $tok" "$INSTANCE_ID_URL"
}

# Check if there's a pending spot-action. Returns 0 if action queued, 1 otherwise.
check_spot_action() {
  local tok="$1"
  curl -sf -H "X-aws-ec2-metadata-token: $tok" "$SPOT_ACTION_URL" >/dev/null 2>&1
}

# Try to deregister from the ALB target group. ASG_TARGET_GROUP_ARN comes
# from the launch template's UserData env. Best-effort; failures don't block.
deregister_from_alb() {
  local instance_id="$1"
  if [[ -z "${ASG_TARGET_GROUP_ARN:-}" ]]; then
    echo "[spot-monitor] ASG_TARGET_GROUP_ARN unset; skipping ALB deregister"
    return 0
  fi
  echo "[spot-monitor] deregistering $instance_id from $ASG_TARGET_GROUP_ARN"
  aws elbv2 deregister-targets \
    --target-group-arn "$ASG_TARGET_GROUP_ARN" \
    --targets "Id=$instance_id" 2>&1 || true
}

# Poll vLLM /metrics for vllm_running_requests until 0 or timeout.
drain_inflight() {
  local deadline=$(($(date +%s) + DRAIN_GRACE_S))
  while [[ $(date +%s) -lt $deadline ]]; do
    local running
    running=$(curl -sf "$LOCAL_VLLM/metrics" 2>/dev/null \
      | grep '^vllm:num_requests_running' \
      | awk '{print $2}' | head -1)
    if [[ -z "$running" ]] || [[ "$running" == "0" ]] || [[ "$running" == "0.0" ]]; then
      echo "[spot-monitor] in-flight drained (running=$running)"
      return 0
    fi
    echo "[spot-monitor] drain wait: vllm_running_requests=$running"
    sleep 2
  done
  echo "[spot-monitor] drain timed out; proceeding with SIGTERM anyway"
}

# Send SIGTERM to vLLM. The container ENTRYPOINT propagates this to the
# Python process and the container exits, which the ASG sees as unhealthy.
sigterm_vllm() {
  echo "[spot-monitor] SIGTERM vLLM"
  pkill -TERM -f "vllm.entrypoints.openai.api_server" || true
}

main() {
  echo "[spot-monitor] starting (poll every ${POLL_INTERVAL_S}s)"
  local tok
  tok=$(get_token) || true
  local instance_id
  instance_id=$(get_instance_id "$tok" 2>/dev/null) || instance_id="unknown"
  echo "[spot-monitor] instance=$instance_id"

  while true; do
    # Refresh token (60s TTL)
    tok=$(get_token) || true
    if [[ -z "$tok" ]]; then
      sleep "$POLL_INTERVAL_S"
      continue
    fi

    if check_spot_action "$tok"; then
      echo "[spot-monitor] SPOT INSTANCE ACTION DETECTED"
      deregister_from_alb "$instance_id"
      drain_inflight
      sigterm_vllm
      # Stay alive long enough for the SIGTERM to propagate; the container
      # entrypoint will exit when vLLM does.
      sleep "$SIGTERM_LEAD_S"
      exit 0
    fi

    sleep "$POLL_INTERVAL_S"
  done
}

main "$@"
