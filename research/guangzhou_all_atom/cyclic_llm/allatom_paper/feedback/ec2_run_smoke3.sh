#!/bin/bash
# U3 LoRA/DPO smoke on a throwaway spot CPU instance (owner rule: no laptop compute). Reads code from S3, writes results to S3.
B=s3://biomate-nextflow-work/cyclic_peptide/allatom/u23/smoke3
shutdown -h +100
exec > /var/log/u23S.log 2>&1
set -x
( while true; do aws s3 cp /var/log/u23S.log $B/boot.log --only-show-errors; [ -f /w/smoke.json ] && aws s3 cp /w/smoke.json $B/smoke.json --only-show-errors; sleep 20; done ) &
SYNC=$!
dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1
python3.11 -m pip install -q numpy scipy rdkit
python3.11 -m pip install -q "torch==2.13.0+cpu" --extra-index-url https://download.pytorch.org/whl/cpu
python3.11 -m pip install -q transformers safetensors peft accelerate
mkdir -p /w/chemfm && cd /w/chemfm
SHA=f99dc2e89726539bb9cf31b2e2b4360650bac6a8
for f in config.json generation_config.json special_tokens_map.json tokenizer.json tokenizer_config.json model.safetensors; do curl -sL -o $f https://huggingface.co/ChemFM/ChemFM-1B/resolve/$SHA/$f; done
echo "24686705d779db6876acc09c81d64d432262ef8b5dbfccc385212587079ce419  model.safetensors" | sha256sum -c - || { echo CHEMFM_SHA_MISMATCH; aws s3 cp /var/log/u23S.log $B/FAILED.log --only-show-errors; shutdown -h now; exit 3; }
cd /w && aws s3 cp $B/code.tgz . --only-show-errors && tar xzf code.tgz -C /w
cd /w/allatom_paper
export CHEMFM_DIR=/w/chemfm OMP_NUM_THREADS=16 OUT=/w/smoke.json PYTHONHASHSEED=0
python3.11 -m feedback.smoke_lora_dpo > /w/smoke.log 2>&1
echo "smoke rc=$?" >> /w/smoke.log
aws s3 cp /w/smoke.log $B/smoke.log --only-show-errors
[ -f /w/smoke.json ] && aws s3 cp /w/smoke.json $B/smoke.json --only-show-errors
kill $SYNC
aws s3 cp /var/log/u23S.log $B/boot.log --only-show-errors
shutdown -h now
