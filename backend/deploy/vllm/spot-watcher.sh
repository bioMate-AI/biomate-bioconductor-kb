#!/usr/bin/env bash
# Spot-interruption watcher for vLLM nodes on AWS spot instances.
# Polls IMDSv2 every 5s for the spot termination notice (delivered 120s
# before reclamation). On notice:
#   1. Deregister from the ALB target group (stops new requests)
#   2. Wait for in-flight requests to drain
#   3. SIGTERM vLLM at T-30s (gives ~30s for cleanup)
#
# Deploy this as a sibling systemd service to vLLM on every ASG instance.
# See docs/20260520_VLLM_SPOT_ONDEMAND_INFRA.md for the full architecture.

set -euo pipefail

# Configuration (overridable by env / systemd unit)
TARGET_GROUP_ARN=${TARGET_GROUP_ARN:?missing TARGET_GROUP_ARN}
VLLM_CONTAINER=${VLLM_CONTAINER:-biomate-vllm}
VLLM_HEALTH_URL=${VLLM_HEALTH_URL:-http://localhost:8000/health}
VLLM_METRICS_URL=${VLLM_METRICS_URL:-http://localhost:8000/metrics}
DRAIN_GRACE_SECONDS=${DRAIN_GRACE_SECONDS:-90}
POLL_INTERVAL=${POLL_INTERVAL:-5}

# IMDSv2 token
get_token() {
  curl -sX PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"
}

# Returns 0 (true) if a spot termination is pending.
check_spot_termination() {
  local token
  token=$(get_token)
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-aws-ec2-metadata-token: $token" \
    "http://169.254.169.254/latest/meta-data/spot/instance-action")
  [ "$code" = "200" ]
}

get_instance_id() {
  local token
  token=$(get_token)
  curl -sH "X-aws-ec2-metadata-token: $token" \
    "http://169.254.169.254/latest/meta-data/instance-id"
}

# Drain logic: deregister from ALB → wait until vLLM reports 0 running
# requests OR drain grace expires → SIGTERM vLLM.
do_drain() {
  local instance_id
  instance_id=$(get_instance_id)
  echo "[spot-watcher] termination notice received for $instance_id"

  echo "[spot-watcher] deregistering from target group"
  aws elbv2 deregister-targets \
    --target-group-arn "$TARGET_GROUP_ARN" \
    --targets "Id=$instance_id" || true

  local deadline=$((SECONDS + DRAIN_GRACE_SECONDS))
  while [ $SECONDS -lt $deadline ]; do
    # vLLM exposes `vllm:num_requests_running` as a Prometheus gauge
    local running
    running=$(curl -s "$VLLM_METRICS_URL" 2>/dev/null \
      | awk '/^vllm:num_requests_running/ { gsub("[^0-9.]",""); print int($NF); exit }')
    running=${running:-0}
    if [ "$running" -le 0 ]; then
      echo "[spot-watcher] drained ($running in-flight) — terminating vLLM"
      docker kill --signal=SIGTERM "$VLLM_CONTAINER" || true
      return 0
    fi
    echo "[spot-watcher] $running in-flight requests, waiting…"
    sleep 5
  done
  echo "[spot-watcher] grace expired — SIGTERMing vLLM anyway"
  docker kill --signal=SIGTERM "$VLLM_CONTAINER" || true
}

echo "[spot-watcher] watching $VLLM_CONTAINER on $(get_instance_id)"
while :; do
  if check_spot_termination; then
    do_drain
    exit 0
  fi
  sleep "$POLL_INTERVAL"
done
