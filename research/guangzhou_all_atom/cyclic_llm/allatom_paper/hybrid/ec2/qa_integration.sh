#!/usr/bin/env bash
# Prepared runner only. Provisioning, S3 transfer and independent shutdown are
# owned by the approved launch wrapper. Never run on a laptop or non-Spot host.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo 'usage: qa_integration.sh CYCLIC_LLM_SOURCE_DIR NEW_OUTPUT_DIR' >&2
  exit 2
fi

# Enforce EC2 Spot before dependency installs, Python imports or tests.
meta_token=$(curl --fail --silent --show-error --max-time 3 --noproxy '*' \
  -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' \
  http://169.254.169.254/latest/api/token) || exit 3
lifecycle=$(curl --fail --silent --show-error --max-time 3 --noproxy '*' \
  -H "X-aws-ec2-metadata-token: $meta_token" \
  http://169.254.169.254/latest/meta-data/instance-life-cycle) || exit 3
[[ "$lifecycle" == spot ]] || { echo 'EC2 Spot required' >&2; exit 3; }
unset meta_token

if [[ ${METHOD_QA_TIMEOUT_ACTIVE:-0} != 1 ]]; then
  exec env METHOD_QA_TIMEOUT_ACTIVE=1 timeout --signal=TERM --kill-after=30s \
    1200 bash "$0" "$@"
fi

source_root=$(cd "$1" && pwd)
out=$2
[[ ! -e "$out" ]] || { echo 'output directory already exists' >&2; exit 4; }
mkdir -p "$out"
out=$(cd "$out" && pwd)
finish() {
  rc=$?
  printf '%s\n' "$rc" > "$out/exit_code.txt"
  exit "$rc"
}
trap finish EXIT
trap 'exit 124' TERM
trap 'exit 130' INT

export CUDA_VISIBLE_DEVICES='' OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export PYTHONNOUSERSITE=1 PYTHONHASHSEED=0
unset PYTHONPATH
python_bin=${METHOD_QA_PYTHON:-python3.11}
"$python_bin" -m venv "$out/venv"
qa_python="$out/venv/bin/python"
# This first resolver run is a candidate environment, not an asserted prior
# tested lock. Preserve the complete freeze for subsequent exact reproduction.
"$qa_python" -m pip install --disable-pip-version-check 'pip==25.1.1' \
  > "$out/dependencies.log" 2>&1
"$qa_python" -m pip install --disable-pip-version-check --extra-index-url https://download.pytorch.org/whl/cpu \
  'torch==2.6.0+cpu' >> "$out/dependencies.log" 2>&1
"$qa_python" -m pip install --disable-pip-version-check \
  'transformers==4.51.3' 'peft==0.15.2' 'accelerate==1.6.0' \
  'numpy==2.2.6' 'scipy==1.15.3' 'rdkit==2025.3.2' 'pytest==8.3.5' \
  >> "$out/dependencies.log" 2>&1
"$qa_python" -m pip freeze > "$out/pip-freeze.txt"
"$qa_python" -m pip check > "$out/pip-check.txt"

export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 HF_DATASETS_OFFLINE=1
export PYTHONPATH="$source_root/allatom_paper:$source_root"
"$qa_python" - <<'PY' > "$out/environment.txt"
import sys, torch, transformers, peft, rdkit, scipy, numpy
print(sys.version)
for module in (torch, transformers, peft, rdkit, scipy, numpy):
    print(module.__name__, module.__version__)
assert not torch.cuda.is_available(), 'CPU-only QA required'
PY

cd "$source_root/allatom_paper"
# Whole hybrid directory includes changed hand-off, source-policy, checkpoint,
# stall-control and parent-selection suites present in the final bundle.
nice -n 10 "$qa_python" -m pytest -q -ra \
  hybrid/ test_orchestrator_ia.py test_pmo_harness.py \
  retrieval/test_retrieval.py feedback/test_preference_updater.py \
  feedback/test_stop_monitor.py \
  --junitxml="$out/junit.xml" > "$out/tests.txt" 2>&1
# Separate processes prevent the legacy top-level config/verify module names
# in the literature and patent packages from colliding during collection.
for package in knowledge_scale patent_mining; do
  (
    cd "$source_root/allatom_paper/$package"
    if [[ "$package" == knowledge_scale ]]; then
      suites=(test_k2.py test_semantic_eligibility.py)
    else
      suites=(test_k4.py test_sequence_repairs.py)
    fi
    nice -n 10 "$qa_python" -m pytest -q -ra "${suites[@]}" \
      --junitxml="$out/$package-junit.xml" > "$out/$package-tests.txt" 2>&1
  )
done
"$qa_python" - "$out/junit.xml" "$out/knowledge_scale-junit.xml" "$out/patent_mining-junit.xml" <<'PY' > "$out/acceptance.txt"
import sys
import xml.etree.ElementTree as ET
for path in sys.argv[1:]:
    root = ET.parse(path).getroot()
    suites = list(root.iter('testsuite'))
    counts = {k: sum(int(s.get(k, 0)) for s in suites)
              for k in ('tests', 'failures', 'errors', 'skipped')}
    print(path, counts)
    assert counts['tests'] > 0
    assert not any(counts[k] for k in ('failures', 'errors', 'skipped'))
print('SYNTHETIC_CPU_QA_PASS; not real-model M1 or study acceptance')
PY
printf '%s\n' 'synthetic CPU QA completed' > "$out/done.flag"
