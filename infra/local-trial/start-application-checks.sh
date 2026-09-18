#!/bin/bash
set -euo pipefail
cd /opt/biomate-trial
until test -f APP_DEPENDENCIES_READY; do
  if systemctl is-failed --quiet biomate-app-prepare; then exit 1; fi
  sleep 5
done
sudo apt-get install -y -qq fastqc
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='ubuntu'" | grep -q 1; then
  sudo -u postgres createuser ubuntu
fi
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='biomate_trial'" | grep -q 1; then
  sudo -u postgres createdb --owner=ubuntu biomate_trial
fi
cp scripts/start-worker-*.py scripts/evaluate-application.py scripts/evaluate_fastqc.py scripts/verify_fastqc.py .
sudo cp scripts/biomate-trial-backend.service scripts/biomate-trial-frontend.service scripts/biomate-application-check.service scripts/biomate-fastqc-check.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now biomate-trial-backend biomate-trial-frontend
sudo systemctl start --no-block biomate-fastqc-check biomate-application-check
