#!/usr/bin/env bash
# Bootstrap for the RealBio LLM+HARNESS eval box. Same proven transformers env as
# spot_cpt800_bootstrap.sh (torch 2.14.1 / transformers 5.18.0 / peft 0.21.2 so Qwen3.5 + the
# cpt1200/sft adapters load exactly as trained), PLUS the OpenAI-shim serving deps
# (fastapi/uvicorn/pydantic) and the openai client the harness runner uses.
set -uo pipefail

echo "=== AWS CLI check ==="
command -v aws >/dev/null || {
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  (cd /tmp && unzip -q awscliv2.zip && ./aws/install) || sudo /tmp/aws/install
}

if ! python3 -c 'import ensurepip' 2>/dev/null; then
  # On the DL AMI, cloud-init/unattended-upgrades holds the dpkg/apt lock for the first
  # minute(s) of boot. Installing python3-venv while the lock is held fails silently (no set -e),
  # which previously cascaded into a venv-creation failure. Wait for the lock, then install.
  echo "=== waiting for apt/dpkg lock before installing python3-venv ==="
  for i in $(seq 1 60); do   # up to 10 min
    if ! fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
                /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; then
      break
    fi
    echo "[bootstrap] apt/dpkg lock held (unattended-upgrades?), waiting ($i)"; sleep 10
  done
  for attempt in 1 2 3; do
    apt-get update -qq || true
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-venv; then break; fi
    echo "[bootstrap] python3-venv install attempt $attempt failed; retrying after lock wait"
    for i in $(seq 1 30); do
      fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1 || break
      sleep 10
    done
  done
  python3 -c 'import ensurepip' 2>/dev/null || { echo "VENV_PKG_INSTALL_FAILED"; exit 18; }
fi

echo "=== transformers venv (reference engine + shim + harness client) ==="
python3 -m venv --system-site-packages /opt/eval-tf || { echo "VENV_CREATE_FAILED"; exit 18; }
[ -x /opt/eval-tf/bin/pip ] || { echo "VENV_CREATE_FAILED_NO_PIP"; exit 18; }
/opt/eval-tf/bin/pip install -q --disable-pip-version-check -U pip setuptools wheel || { echo "TF_PIP_UPGRADE_FAILED"; exit 19; }
/opt/eval-tf/bin/pip install -q --disable-pip-version-check \
  torch==2.14.1 transformers==5.18.0 peft==0.21.2 accelerate==1.15.0 datasets safetensors "huggingface_hub>=0.25" \
  fastapi "uvicorn[standard]" pydantic openai || { echo "TF_VENV_PIP_FAILED"; exit 20; }
/opt/eval-tf/bin/pip freeze > /opt/eval-tf-requirements.txt
echo "TF_VENV_OK"
echo "BOOTSTRAP_DONE"
