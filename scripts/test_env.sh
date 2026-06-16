#!/usr/bin/env bash
#
# test_env.sh — start / stop / status the dedicated next-phase TEST environment.
#
# Why: the test stack (EC2 t3.medium + RDS db.t3.micro + public IPv4) costs
# ~$50/mo if left running 24/7. STOPPING it (not terminating) drops idle cost to
# ~$6-8/mo (storage only) while preserving everything that's expensive to rebuild:
# the RDS databases (galaxy model DB `galaxymodel` + the Node app DB), the
# drizzle-created frontend schema, /opt/biomate/.env, and the docker containers
# (they have restart: unless-stopped, so they come back on boot).
#
# Usage (run with an admin identity that can start/stop EC2 + RDS):
#   AWS_PROFILE=biomate-admin bash scripts/test_env.sh start
#   AWS_PROFILE=biomate-admin bash scripts/test_env.sh stop
#   AWS_PROFILE=biomate-admin bash scripts/test_env.sh status
#
# CAVEAT — the public IP is NOT an Elastic IP, so it CHANGES on every stop/start.
# `start` prints the new IP and the exact hosts-file line to use. (Or run
# `test_env.sh dns` once to repoint Route53 and never touch /etc/hosts again.)

set -euo pipefail

INSTANCE_ID="i-0482a6fa98c6f301a"
RDS_ID="biomate-test-galaxy"
REGION="${AWS_REGION:-us-west-2}"
DOMAIN="test.stage-public.biomate.ai"
PROFILE_ARGS=()
[[ -n "${AWS_PROFILE:-}" ]] && PROFILE_ARGS=(--profile "$AWS_PROFILE")

ec2() { aws ec2 "${PROFILE_ARGS[@]}" --region "$REGION" "$@"; }
rds() { aws rds "${PROFILE_ARGS[@]}" --region "$REGION" "$@"; }

ec2_state() { ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo unknown; }
rds_state() { rds describe-db-instances --db-instance-identifier "$RDS_ID" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo unknown; }
public_ip() { ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null; }

case "${1:-status}" in
  start)
    echo "=== Starting TEST env ==="
    # RDS first (galaxy connects to it at boot); RDS takes longer to be ready.
    if [[ "$(rds_state)" != "available" ]]; then
      echo "RDS $RDS_ID: $(rds_state) → starting..."
      rds start-db-instance --db-instance-identifier "$RDS_ID" >/dev/null 2>&1 || true
      echo "waiting for RDS available (a few minutes)..."
      rds wait db-instance-available --db-instance-identifier "$RDS_ID"
    fi
    echo "RDS: available ✓"

    if [[ "$(ec2_state)" != "running" ]]; then
      echo "EC2 $INSTANCE_ID: $(ec2_state) → starting..."
      ec2 start-instances --instance-ids "$INSTANCE_ID" >/dev/null
      ec2 wait instance-running --instance-ids "$INSTANCE_ID"
    fi
    echo "EC2: running ✓"

    IP="$(public_ip)"
    echo ""
    echo "=== TEST env is up. New public IP: $IP ==="
    echo "Containers (restart: unless-stopped) come back on boot — give them ~2 min,"
    echo "then check:  AWS_PROFILE=$AWS_PROFILE bash scripts/test_env.sh status"
    echo ""
    echo "Update your hosts file to the NEW IP (the old line is now stale):"
    echo "  sudo sed -i '' '/$DOMAIN/d' /etc/hosts"
    echo "  echo \"$IP $DOMAIN\" | sudo tee -a /etc/hosts"
    echo "  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
    echo "Then open: https://$DOMAIN"
    ;;

  stop)
    echo "=== Stopping TEST env (preserves all data/config) ==="
    if [[ "$(ec2_state)" == "running" ]]; then
      ec2 stop-instances --instance-ids "$INSTANCE_ID" >/dev/null
      echo "EC2 $INSTANCE_ID → stopping"
    else
      echo "EC2 already $(ec2_state)"
    fi
    if [[ "$(rds_state)" == "available" ]]; then
      rds stop-db-instance --db-instance-identifier "$RDS_ID" >/dev/null 2>&1 || true
      echo "RDS $RDS_ID → stopping (note: AWS auto-starts a stopped RDS after 7 days)"
    else
      echo "RDS already $(rds_state)"
    fi
    echo "Idle cost now ~storage only. Re-enable with: test_env.sh start"
    ;;

  status)
    echo "EC2 $INSTANCE_ID : $(ec2_state)   IP: $(public_ip)"
    echo "RDS $RDS_ID : $(rds_state)"
    ;;

  *)
    echo "Usage: AWS_PROFILE=biomate-admin bash $0 {start|stop|status}" >&2
    exit 1
    ;;
esac
