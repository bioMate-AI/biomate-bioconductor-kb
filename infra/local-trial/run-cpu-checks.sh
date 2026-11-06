#!/bin/bash
set -u
cd /opt/biomate-trial
until curl -fsS http://127.0.0.1:8000/health >/dev/null; do
  if systemctl is-failed --quiet biomate-cpu-prepare || systemctl is-failed --quiet biomate-local-llm; then exit 1; fi
  sleep 15
done
venv/bin/python smoke.py --output live-smoke.json
smoke_status=$?
venv/bin/python evaluate_core.py --output core-evaluation.json
core_status=$?
printf '{"smoke_exit":%s,"core_exit":%s}\n' "$smoke_status" "$core_status" > evaluation-exit-status.json
venv/bin/python scripts/backup_status.py
if [ "$smoke_status" -ne 0 ] || [ "$core_status" -ne 0 ]; then exit 1; fi
