#!/bin/bash
# usage: ssm_run.sh INSTANCE_ID 'shell commands'   -> prints stdout/stderr (waits up to ~10 min); bounded AWS calls
I=$1; shift
CID=$(aws ssm send-command --instance-ids $I --document-name AWS-RunShellScript --timeout-seconds 1500 --parameters "commands=[\"$*\"]" --query Command.CommandId --output text --cli-read-timeout 30 --cli-connect-timeout 10)
for k in $(seq 1 200); do
  S=$(aws ssm get-command-invocation --command-id $CID --instance-id $I --query Status --output text --cli-read-timeout 30 --cli-connect-timeout 10 2>/dev/null)
  case "$S" in Success|Failed|Cancelled|TimedOut) break;; esac; sleep 5
done
aws ssm get-command-invocation --command-id $CID --instance-id $I --query '[Status,StandardOutputContent,StandardErrorContent]' --output text --cli-read-timeout 30
