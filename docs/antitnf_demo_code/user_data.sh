#!/bin/bash
# anti-TNF IBD response demo — EC2 bootstrap (Amazon Linux 2023)
# Streams log to S3 every 30s, self-terminates. Dead-man switch at +120 min.
# ROBUST v2: EXIT-trap flush (survives the shutdown race), resilient pip, deps verified before run.
set -x
exec > /var/log/antitnf-boot.log 2>&1

S3=s3://biomate-test-data/antitnf-demo
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 300')
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
export AWS_DEFAULT_REGION=us-west-2
LOG=/var/log/antitnf-run.log
: > $LOG

flush() {
  aws s3 cp $LOG                      $S3/logs/antitnf-run.log  >/dev/null 2>&1 || true
  aws s3 cp /var/log/antitnf-boot.log $S3/logs/antitnf-boot.log >/dev/null 2>&1 || true
}
# EXIT trap: flush no matter how we leave (error, normal end). Runs BEFORE shutdown.
trap 'flush' EXIT

# ---- dead-man switch: hard shutdown at +120 min no matter what ----
shutdown -h +120 "antitnf dead-man switch" &

echo "=== antitnf demo start $(date -u) instance=$IID ===" | tee -a $LOG

# ---- log streamer: push logs to S3 every 30s (best-effort, non-blocking) ----
(
  while true; do flush; sleep 30; done
) &
STREAM_PID=$!

# ---- deps: install the scientific stack as PREBUILT RPMs (no pip source builds). ----
# Root-cause fix for two prior hangs: `pip install numpy pandas scikit-learn` on the
# AL2023 base with pip 21.3.1 fell back to compiling from source (no matching wheels)
# and blocked. dnf ships prebuilt python3-numpy/scipy/pandas/scikit-learn — fast, no gcc.
echo "=== installing deps via dnf $(date -u) ===" | tee -a $LOG
timeout 600 dnf install -y python3 python3-pip \
  python3-numpy python3-scipy python3-pandas python3-scikit-learn >> $LOG 2>&1
DNF_RC=$?
echo "=== dnf deps RC=$DNF_RC $(date -u) ===" | tee -a $LOG
flush
# if any RPM was unavailable, top up with pip (binary-only, timeout-guarded)
if ! python3 -c "import numpy,pandas,sklearn" >/dev/null 2>&1; then
  echo "=== dnf incomplete — pip top-up (binary-only, 600s cap) $(date -u) ===" | tee -a $LOG
  timeout 600 python3 -m pip install --quiet --only-binary=:all: --break-system-packages \
    numpy pandas scikit-learn >> $LOG 2>&1 || true
fi
echo "=== deps install returned; verifying imports $(date -u) ===" | tee -a $LOG
if ! python3 -c "import numpy,pandas,sklearn;print('DEPS_OK numpy',numpy.__version__,'pandas',pandas.__version__,'sklearn',sklearn.__version__)" >> $LOG 2>&1; then
  echo "=== FATAL: deps import failed — aborting (see log) ===" | tee -a $LOG
  flush
  kill $STREAM_PID 2>/dev/null || true
  sleep 8; flush; sleep 4
  shutdown -h now "antitnf: deps failed"
  exit 1
fi
flush

# ---- pull pipeline ----
mkdir -p /opt/antitnf && cd /opt/antitnf
aws s3 cp $S3/code/antitnf_pipeline.py ./antitnf_pipeline.py >> $LOG 2>&1
export ANTITNF_OUT=/opt/antitnf/out
mkdir -p $ANTITNF_OUT

# ---- smoke test first (label parse + data load), then real run ----
echo "=== SMOKE TEST $(date -u) ===" | tee -a $LOG
python3 antitnf_pipeline.py --smoke >> $LOG 2>&1
SMOKE_RC=$?
echo "=== SMOKE RC=$SMOKE_RC $(date -u) ===" | tee -a $LOG
flush

if [ $SMOKE_RC -eq 0 ]; then
  echo "=== REAL RUN $(date -u) ===" | tee -a $LOG
  python3 antitnf_pipeline.py >> $LOG 2>&1
  RUN_RC=$?
  echo "=== REAL RUN RC=$RUN_RC $(date -u) ===" | tee -a $LOG
  aws s3 cp $ANTITNF_OUT/ $S3/results/ --recursive >> $LOG 2>&1 || true
else
  echo "=== SMOKE FAILED — skipping real run ===" | tee -a $LOG
fi

echo "DONE_MARKER $(date -u)" >> $LOG

# ---- stop streamer, flush SYNCHRONOUSLY, then wait so S3 PUT completes before shutdown ----
kill $STREAM_PID 2>/dev/null || true
flush
sleep 10
flush
sleep 5
shutdown -h now "antitnf demo complete — self terminate"
