#!/usr/bin/env python3
"""EC2 user-data for the U1 model stage (spot). CPU variant (no GPU spot capacity on 2026-10-29): AL2023 + torch CPU. usage: make_ud_gpu.py smoke|sampA|lora OUT.sh RUN_ID
smoke: n=64 masked+unmasked at frac 0.85 and a 20-step LoRA-under-mask run (debug, ~15 min). full: 5,000 / 1,000 / 300 samples + 200-step LoRA + masked sampling with the adapter.
Single writer per prefix s3://.../allatom/u1/<RUN_ID>/. No bare wait; sync loop is killed explicitly; hard wall-clock cap."""
import sys
stage, out, run = sys.argv[1:4]
SEEDS = sys.argv[4] if len(sys.argv) > 4 else "3"
B = f"s3://biomate-nextflow-work/cyclic_peptide/allatom/u1/{run}"
CAP = {"smoke": 90, "sampA": 260, "lora": 200, "diag": 90, "diag3": 60, "sampB": 170, "multi": 150, "lora2": 240}[stage]
RUNS = {
 "smoke": '''run masked_sampling.py /w/out --frac 0.85 --n 32 --seed 0 --batch 16
run lora_mask_smoke.py /w/out_lora --prep /w/prep --steps 6 --bs 2
run masked_sampling.py /w/out --frac 0.5 --n 16 --seed 0 --batch 16 --modes masked --lora /w/out_lora/lora''',
 "sampA": '''run masked_sampling.py /w/out --frac 0.85 --n 5000 --seed 0
run masked_sampling.py /w/out --frac 0.5 --n 1000 --seed 0
run masked_sampling.py /w/out --frac 0.2 --n 300 --seed 0''',
 "diag": '''run masked_sampling.py /w/out --frac 0.85 --n 64 --seed 1 --batch 32 --modes masked
run masked_sampling.py /w/out --frac 0.5 --n 64 --seed 1 --batch 32 --modes masked''',
 "diag3": '''run masked_sampling.py /w/out --frac 0.85 --n 48 --seed 2 --batch 48 --modes masked''',
 "sampB": '''run masked_sampling.py /w/out --frac 0.5 --n 400 --seed 3 --batch 32
run masked_sampling.py /w/out --frac 0.2 --n 160 --seed 3 --batch 32''',
 "multi": f'''run masked_sampling.py /w/out --frac 0.5 --n 200 --seeds {SEEDS} --batch 32
run masked_sampling.py /w/out --frac 0.5 --n 200 --seeds {SEEDS} --batch 32 --modes masked --soft literature_uniform --lam 1.0 --tag _soft
run masked_sampling.py /w/out --frac 0.5 --n 200 --seeds {SEEDS} --batch 32 --modes masked --no-lookahead --tag _nolook
run masked_sampling.py /w/out --frac 0.2 --n 80 --seeds {SEEDS} --batch 32''',
 "lora2": f'''BS=$($PY -c "import torch;print(8 if torch.cuda.is_available() else 2)")
run lora_mask_smoke.py /w/out_lora --prep /w/prep --steps 200 --bs $BS
run masked_sampling.py /w/out_lora_samples --frac 0.5 --n 200 --seeds 3,4,5 --batch 32 --modes masked --lora /w/out_lora/lora --tag _lora''',
 "lora": '''run lora_mask_smoke.py /w/out_lora --prep /w/prep --steps 200 --bs 8
run masked_sampling.py /w/out_lora_samples --frac 0.5 --n 300 --seed 0 --modes masked --lora /w/out_lora/lora''',
}[stage]
sh = f'''#!/bin/bash
B={B}
exec > /var/log/ud.log 2>&1; set -x
shutdown -h +{CAP}
( while true; do aws s3 cp /var/log/ud.log $B/boot.log --only-show-errors; aws s3 sync /w/out $B/out/ --only-show-errors; aws s3 sync /w/out_lora $B/out_lora/ --only-show-errors; aws s3 sync /w/out_lora_samples $B/out_lora_samples/ --only-show-errors; aws s3 cp /w/steps.log $B/steps.log --only-show-errors; sleep 30; done ) &
SYNC=$!
mkdir -p /w/out /w/out_lora /w/out_lora_samples /w/data /w/chemfm && cd /w && touch /w/steps.log
PY=""; for p in /opt/pytorch/bin/python /usr/bin/python3 python3.11; do if $p -c "import torch" 2>/dev/null; then PY=$p; break; fi; done
if [ -z "$PY" ]; then
  dnf install -y python3.11 python3.11-pip python3.11-devel gcc >/dev/null 2>&1; PY=python3.11
  $PY -m pip install -q "torch==2.13.0+cpu" --extra-index-url https://download.pytorch.org/whl/cpu 2>&1 | tail -2
fi
$PY -m pip install -q numpy scipy scikit-learn rdkit pytest transformers safetensors peft accelerate 2>&1 | tail -2
$PY -c "import torch;print(torch.__version__, torch.cuda.is_available())"
aws s3 cp $B/code.tgz /w/code.tgz --only-show-errors && mkdir -p /w/code && tar xzf /w/code.tgz -C /w/code 2>/dev/null
aws s3 cp $B/prep/ /w/prep/ --recursive --only-show-errors
aws s3 cp s3://biomate-nextflow-work/cyclic_peptide/loop_retro/data/CycPeptMPDB_Peptide_All.csv /w/data/ --only-show-errors
cd /w/chemfm; for f in config.json generation_config.json special_tokens_map.json tokenizer.json tokenizer_config.json model.safetensors; do curl -sL -o $f https://huggingface.co/ChemFM/ChemFM-1B/resolve/main/$f; done
echo "24686705d779db6876acc09c81d64d432262ef8b5dbfccc385212587079ce419  model.safetensors" | sha256sum -c - || {{ echo CHEMFM_SHA_MISMATCH; aws s3 cp /var/log/ud.log $B/FAILED.log --only-show-errors; shutdown -h now; exit 3; }}
cd /w/code/allatom_paper/rules
export OMP_NUM_THREADS=$(nproc) CHEMFM_DIR=/w/chemfm CHEMFM_TOK=/w/chemfm/tokenizer.json CPM_CSV=/w/data/CycPeptMPDB_Peptide_All.csv PYTHONHASHSEED=0 MONO_JSON=/w/code/v4_eval/monomer_dictionary_v5.json
run() {{ n=$(echo "$*" | tr ' /' '__' | cut -c1-60); echo "START $* $(date +%T)" >> /w/steps.log; $PY "$@" > /w/log_$n.txt 2>&1; echo "END rc=$? $* $(date +%T)" >> /w/steps.log; aws s3 cp /w/log_$n.txt $B/logs/log_$n.txt --only-show-errors; }}
{RUNS}
echo DONE >> /w/steps.log; aws s3 cp /w/steps.log $B/steps.log --only-show-errors
aws s3 sync /w/out $B/out/ --only-show-errors; aws s3 sync /w/out_lora $B/out_lora/ --only-show-errors; aws s3 sync /w/out_lora_samples $B/out_lora_samples/ --only-show-errors
echo DONE > /w/done.flag; aws s3 cp /w/done.flag $B/done.flag --only-show-errors
kill $SYNC; aws s3 cp /var/log/ud.log $B/boot_final.log --only-show-errors; shutdown -h now
'''
open(out, "w").write(sh); print("wrote", out, stage, "cap_min", CAP)
