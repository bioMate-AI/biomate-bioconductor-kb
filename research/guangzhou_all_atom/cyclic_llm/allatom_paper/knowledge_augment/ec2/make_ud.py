#!/usr/bin/env python3
"""EC2 user-data for workstream KA (spot). usage: make_ud.py tests|measure|all OUT.sh RUN_ID [N] [SEEDS]
tests: unit tests of knowledge_augment (+ train-example smoke). measure: DEV measurement L0-L3 (ChemFM-1B, TRAIN verifiers only). all: tests, then measure only if tests pass.
Single writer per prefix s3://biomate-nextflow-work/cyclic_peptide/allatom/ka/<RUN_ID>/. No bare wait; sync loop killed explicitly; wall-clock cap via shutdown -h."""
import sys
stage, out, run = sys.argv[1:4]
N = sys.argv[4] if len(sys.argv) > 4 else "150"
SEEDS = sys.argv[5] if len(sys.argv) > 5 else "0,1,2,3,4"
B = f"s3://biomate-nextflow-work/cyclic_peptide/allatom/ka/{run}"
CAP = {"tests": 45, "measure": 110, "all": 115}[stage]
TESTS = '''run -m pytest -x -q -s -p no:cacheprovider allatom_paper/knowledge_augment/test_knowledge_augment.py
TESTRC=$?
run allatom_paper/knowledge_augment/smoke_examples.py /w/out/examples'''
MEAS = f'''run allatom_paper/knowledge_augment/dev_measure.py /w/out/dev --levels L0,L1,L2,L3 --seeds {SEEDS} --n {N} --frac 0.5 --batch 32'''
BODY = {"tests": TESTS, "measure": MEAS, "all": TESTS + '\nif [ "$TESTRC" = "0" ]; then\n' + MEAS + '\nelse echo TESTS_FAILED >> /w/steps.log; fi'}[stage]
sh = f'''#!/bin/bash
B={B}
exec > /var/log/ud.log 2>&1; set -x
shutdown -h +{CAP}
mkdir -p /w/out && touch /w/steps.log
( while true; do aws s3 cp /var/log/ud.log $B/boot.log --only-show-errors; aws s3 sync /w/out $B/out/ --only-show-errors; aws s3 cp /w/steps.log $B/steps.log --only-show-errors; sleep 30; done ) &
SYNC=$!
mkdir -p /w/data /w/chemfm && cd /w
PY=""; for p in /opt/pytorch/bin/python /usr/bin/python3 python3.11; do if $p -c "import torch" 2>/dev/null; then PY=$p; break; fi; done
if [ -z "$PY" ]; then
  dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1; PY=python3.11
  $PY -m pip install -q "torch==2.13.0+cpu" --extra-index-url https://download.pytorch.org/whl/cpu 2>&1 | tail -2
fi
$PY -m pip install -q numpy scipy scikit-learn pandas rdkit pytest transformers safetensors peft accelerate 2>&1 | tail -2
$PY -c "import torch;print(torch.__version__, torch.cuda.is_available())"
aws s3 cp $B/code.tgz /w/code.tgz --only-show-errors && mkdir -p /w/code && tar xzf /w/code.tgz -C /w/code
aws s3 cp s3://biomate-nextflow-work/cyclic_peptide/loop_retro/data/CycPeptMPDB_Peptide_All.csv /w/data/ --only-show-errors
cd /w/chemfm; for f in config.json generation_config.json special_tokens_map.json tokenizer.json tokenizer_config.json model.safetensors; do curl -sL -o $f https://huggingface.co/ChemFM/ChemFM-1B/resolve/main/$f; done
echo "24686705d779db6876acc09c81d64d432262ef8b5dbfccc385212587079ce419  model.safetensors" | sha256sum -c - || {{ echo CHEMFM_SHA_MISMATCH; aws s3 cp /var/log/ud.log $B/FAILED.log --only-show-errors; shutdown -h now; exit 3; }}
cd /w/code
export OMP_NUM_THREADS=$(nproc) CHEMFM_DIR=/w/chemfm CHEMFM_TOK=/w/chemfm/tokenizer.json CPM_CSV=/w/data/CycPeptMPDB_Peptide_All.csv PYTHONHASHSEED=0 MONO_JSON=/w/code/v4_eval/monomer_dictionary_v5.json PYTHONPATH=/w/code/allatom_paper
run() {{ n=$(echo "$*" | tr ' /' '__' | cut -c1-60); echo "START $* $(date +%T)" >> /w/steps.log; $PY "$@" > /w/log_$n.txt 2>&1; rc=$?; echo "END rc=$rc $* $(date +%T)" >> /w/steps.log; aws s3 cp /w/log_$n.txt $B/logs/log_$n.txt --only-show-errors; return $rc; }}
{BODY}
echo DONE >> /w/steps.log; aws s3 cp /w/steps.log $B/steps.log --only-show-errors
aws s3 sync /w/out $B/out/ --only-show-errors
echo DONE > /w/done.flag; aws s3 cp /w/done.flag $B/done.flag --only-show-errors
kill $SYNC; aws s3 cp /var/log/ud.log $B/boot_final.log --only-show-errors; shutdown -h now
'''
open(out, "w").write(sh)
print("wrote", out, stage, "cap_min", CAP)
