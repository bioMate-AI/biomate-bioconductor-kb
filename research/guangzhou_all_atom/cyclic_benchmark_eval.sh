#!/bin/bash
# =====================================================================================================
# cyclic_benchmark_eval.sh — PARAMETERIZED apples-to-apples PepGLAD cyclic benchmark eval.
#
# This is cyclic_official_eval.sh with EXACTLY ONE thing made a parameter: the checkpoint source
# (CKPT_S3), so ANY checkpoint can be scored on the SAME standard benchmark PepGLAD reports on.
# Everything that makes the 0.506/0.403 number comparable is preserved verbatim:
#   * CYCLIC_DATA = the PepBDB-cyclic processed test set (pepglad-cyclicprep-20260914/.../pepbdb_cyclic_processed)
#   * abs_position capacity filtering of the test set to the model's position-encoding size
#   * setup_latent_guidance -> generate.py -> cal_metrics.py  (DockQ + Consistency + Diversity + AAR + RMSD(CA))
#   * PepGLAD pinned to commit bad015ca50c312a89482adb5220c3d907f13df5c (same code the 0.506 run used)
#
# vs cyclic_official_eval.sh, the ONLY deltas are:
#   (1) CHECKPOINT: CKPT_S3 (a single whole-model .ckpt on S3) -> cyclic_model.ckpt, instead of the
#       hardcoded FT_RUN directory sync + topk_map.txt best-of selection. Works for BOTH a raw LDM
#       warm-start pickle (epoch-221) and a trained M2c pickle — both are whole-model LDMPepDesign
#       pickles that carry their OWN .autoencoder and .abs_position_encoding (see CAVEAT below).
#   (2) ENV: `source /opt/pepglad-venv` (the BAKED AMI's M2c stack) instead of building a venv from
#       scratch. A missing-dep guard pip-installs only what the baked venv lacks (requests) — NOT a
#       reinstall of the torch/torch-scatter stack the AMI exists to save.
#   (3) LIFECYCLE: this script does NOT self-terminate and does NOT arm a deadline — it is designed to
#       be called in a LOOP (one call per checkpoint) by launch_cyclic_benchmark_eval.sh, which owns
#       the instance lifecycle (dead-man's-switch + shutdown after the whole list is done). A per-run
#       fresh working copy of the processed test set keeps the in-place test_index.txt filtering from
#       leaking across checkpoints in the loop.
#   (4) OUTPUT: writes a machine-readable result JSON (DockQ etc.) to $OUT_S3/result.json in addition
#       to the raw cal_metrics text, so the base-vs-current comparison is a one-line diff.
#
# CAVEAT — is the raw base (epoch-221) fairly evaluable on cyclic?
#   epoch-221 is the released general-peptide PepGLAD LDM (NOT cyclic-trained). Evaluating it on the
#   cyclic test set is a FAIR, honest LOWER-BOUND baseline: SAME test set, SAME metric, SAME code. It
#   runs because (a) the cyclic test "targets" are ordinary receptor+peptide complexes — the peptide
#   merely happens to be cyclic — so generate.py can sample on them; (b) epoch-221 carries its own
#   .autoencoder and .abs_position_encoding, so setup_latent_guidance (which re-derives the latent
#   guidance stats from the cyclic TRAIN split through THIS model's AE) is self-consistent, and the
#   capacity filter reads THIS model's position size. The number will be lower than a cyclic-trained
#   model's — that is exactly the "where do we actually stand" baseline, not a bug. The capacity filter
#   yields the SAME kept-test subset across epoch-221, the original cyclic-FT, and M2c because all three
#   inherit the identical abs_position_encoding size from the epoch-221 warm-start, so the comparison
#   (and the lineage to the 0.506/0.403 number) is preserved.
#
# Required env:  CKPT_S3  OUT_S3
# Optional env:  CYCLIC_DATA (default = PepBDB-cyclic processed)  N_SAMPLES(=10)  ROOT  PEPGLAD_COMMIT
#                CKPT_LABEL (a short tag for logs/result JSON)
# =====================================================================================================
set -Eeuo pipefail
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-west-2} DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 OMP_NUM_THREADS=4
ROOT=${ROOT:-/opt/guangzhou-peptide}
BUCKET=${BUCKET:-knowledge-datasets-1759951976}
OUT_S3=${OUT_S3:?set OUT_S3 (per-checkpoint result dir on S3)}
CKPT_S3=${CKPT_S3:?set CKPT_S3 (the single whole-model .ckpt on S3 to evaluate)}
CKPT_LABEL=${CKPT_LABEL:-$(basename "$CKPT_S3")}
# The SAME PepBDB-cyclic test set the 0.506 number was produced on (keeps the 0.403-comparable lineage).
CYCLIC_DATA=${CYCLIC_DATA:-s3://$BUCKET/cyclic_peptide/runs/pepglad-cyclicprep-20260914T194504Z/pepbdb_cyclic_processed}
PEPGLAD_COMMIT=${PEPGLAD_COMMIT:-bad015ca50c312a89482adb5220c3d907f13df5c}
N_SAMPLES=${N_SAMPLES:-10}
# OPTIONAL AE shim: some checkpoints pickle a non-stock autoencoder class (e.g. the M2c ckpt's
# ClosureAwareAutoEncoder, defined in m1_closure_ae.py). torch.load then raises
# "ModuleNotFoundError: No module named 'm1_closure_ae'" unless that module is importable + imported
# BEFORE the load. Set AE_SHIM_S3 to the S3 uri of m1_closure_ae.py; it is dropped INTO the PepGLAD
# clone (so its own `from utils/models/trainer import ...` resolve against the stock repo — the fork
# that produced the M2c ckpt is the SAME commit bad015ca, so the stock repo's model classes are a 1:1
# match: ClosureAwareAutoEncoder only ADDS two float attrs to the stock AutoEncoder). Stock-AE
# checkpoints (epoch-221 base, cyclic-FT) don't need it and importing it is a harmless no-op for them.
AE_SHIM_S3=${AE_SHIM_S3:-}
mkdir -p "$ROOT/status" "$ROOT/code"
exec > >(tee -a "$ROOT/status/cyclic_benchmark_eval.log") 2>&1
echo "=== cyclic_benchmark_eval: CKPT_LABEL=$CKPT_LABEL CKPT_S3=$CKPT_S3 OUT_S3=$OUT_S3 N_SAMPLES=$N_SAMPLES ==="

stage(){ printf '{"ckpt":"%s","stage":"%s","time":"%s"}\n' "$CKPT_LABEL" "$1" "$(date -u +%FT%TZ)" > "$ROOT/status/status.json"; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; }
# NOTE: no shutdown here — the launcher owns the instance lifecycle (loop over many checkpoints).
# On failure, record a machine-readable error result so the loop can continue and nothing is silently skipped.
on_err(){ rc=$?; stage failed; printf '{"ckpt":"%s","ckpt_s3":"%s","status":"error","rc":%d,"benchmark":"PepBDB-cyclic","note":"see cyclic_benchmark_eval.log"}\n' "$CKPT_LABEL" "$CKPT_S3" "$rc" > "$ROOT/status/result.json"; aws s3 cp "$ROOT/status/result.json" "$OUT_S3/result.json" --only-show-errors || true; aws s3 sync "$ROOT/status" "$OUT_S3/status/" --only-show-errors || true; exit $rc; }
trap on_err ERR

stage activating
# BAKED AMI: activate the pre-built M2c/PepGLAD venv (torch 2.5.1 cu121 + torch-scatter + rdkit + biopython
# + scipy + PyYAML + tqdm + networkx + sympy + tensorboard + boto3). torch 2.5.1 keeps weights_only=False as
# the torch.load default, so the whole-model LDMPepDesign pickles unpickle (.autoencoder/.abs_position_encoding).
if [ -f /opt/pepglad-venv/bin/activate ]; then
  source /opt/pepglad-venv/bin/activate
else
  echo "WARN: /opt/pepglad-venv not found — falling back to \$ROOT/venv (standalone/non-baked host)"
  [ -f "$ROOT/venv/bin/activate" ] && source "$ROOT/venv/bin/activate" || { echo "FATAL: no venv"; exit 1; }
fi
# The only dep cyclic_official_eval.sh installed that the baked venv may lack. Tiny, pure-python; NOT a stack reinstall.
python -c 'import requests' 2>/dev/null || pip install -q --disable-pip-version-check 'requests==2.32.3' || true
python -c 'import torch,torch_scatter,rdkit,Bio,scipy,yaml; assert torch.cuda.is_available(); print("venv ok", torch.__version__, torch.cuda.get_device_name(0))'

stage preparing
[ -d "$ROOT/PepGLAD/.git" ] || git clone https://github.com/THUNLP-MT/PepGLAD.git "$ROOT/PepGLAD"
cd "$ROOT/PepGLAD"; git checkout "$PEPGLAD_COMMIT"
# FRESH per-checkpoint working copy of the processed test set (the capacity filter rewrites test_index.txt
# in place; a fresh copy each run keeps one checkpoint's filtering from leaking into the next in the loop).
rm -rf datasets/pepbdb
mkdir -p datasets/pepbdb/processed datasets/pepbdb/pdbs
aws s3 sync "$CYCLIC_DATA" datasets/pepbdb/processed --only-show-errors
# reference PDBs live at mmap_dir/../pdbs (cal_metrics + get_summary expect that)
mv datasets/pepbdb/processed/pdbs/* datasets/pepbdb/pdbs/ 2>/dev/null || cp -a datasets/pepbdb/processed/pdbs/. datasets/pepbdb/pdbs/
# ---- optional AE shim: make a non-stock pickled AE class importable before any torch.load ----
# Placed INSIDE the clone (cwd during every ckpt load) so `import m1_closure_ae` resolves and its own
# `from utils/models/trainer import ...` bind to this stock repo. ae_run.py is an import-first launcher
# used to run the stock scripts (setup_latent_guidance.py / generate.py) that torch.load internally.
SHIM_INSTALLED=0
if [ -n "$AE_SHIM_S3" ]; then
  aws s3 cp "$AE_SHIM_S3" "$ROOT/PepGLAD/m1_closure_ae.py" --only-show-errors && SHIM_INSTALLED=1
  cat > "$ROOT/PepGLAD/ae_run.py" <<'AERUN'
import sys, runpy
sys.path.insert(0, '.')
try:
    import m1_closure_ae  # registers the fork AE class so torch.load can unpickle it
    import models          # register LDMPepDesign/AutoEncoder/CoDesignDataset (matches m2c_eval wrapper)
    print('[ae_run] m1_closure_ae + models registered')
except Exception as e:
    print('[ae_run] WARN: shim import failed:', repr(e))
script = sys.argv[1]
sys.argv = sys.argv[1:]            # stock script sees argv[0]=script, then its own args
runpy.run_path(script, run_name='__main__')
AERUN
  echo "AE shim installed ($AE_SHIM_S3) -> ckpt loads routed through ae_run.py"
fi
# helper: run a stock PepGLAD script, importing the AE shim FIRST when installed (else call directly —
# preserves the exact validated invocation for stock-AE checkpoints like base/FT).
run_stock(){ if [ "$SHIM_INSTALLED" = "1" ]; then python ae_run.py "$@"; else python "$@"; fi; }

# ---- THE PARAMETER: pull the checkpoint-under-test (single whole-model .ckpt) -> cyclic_model.ckpt ----
aws s3 cp "$CKPT_S3" cyclic_model.ckpt --only-show-errors
echo "cyclic model (under test): $CKPT_LABEL <- $CKPT_S3"

stage filter_and_calibrate
# filter cyclic test to the model's abs_position capacity (< ~29 residues) — reads THIS model's size
python - <<'PY'
import sys
sys.path.insert(0, '.')
try:
    import m1_closure_ae  # register a non-stock pickled AE class (M2c) before torch.load; no-op if absent
except Exception as e:
    print('note: m1_closure_ae not imported (fine for stock-AE ckpts):', repr(e))
import torch
from data.codesign import CoDesignDataset
cap = torch.load('cyclic_model.ckpt', map_location='cpu').abs_position_encoding.weight.shape[0]
P='datasets/pepbdb/processed'; idx=f'{P}/test_index.txt'
lines=open(idx).read().splitlines(keepends=True)
ds=CoDesignDataset(mmap_dir=P, specify_index=idx, backbone_only=False, use_covariance_matrix=True)
keep=[lines[i] for i in range(len(ds))
      if (lambda b:(int(b['position_ids'][b['mask']].max())+1<cap) if b['mask'].any() else False)(ds.collate_fn([ds[i]]))]
open(idx,'w').writelines(keep); print('abs_position cap', cap, '| test kept', len(keep), 'of', len(lines))
PY
cp cyclic_model.ckpt cyclic_calibrated.ckpt
mkdir -p run_outputs
python - <<'PY'
import yaml
from pathlib import Path
c=yaml.safe_load(Path('configs/pepbench/ldm/setup_latent_guidance.yaml').read_text())
c['dataset']['test']['mmap_dir']='datasets/pepbdb/processed'
c['dataset']['test']['specify_index']='datasets/pepbdb/processed/train_index.txt'
c['dataloader'].update(num_workers=0, batch_size=4)
Path('run_outputs/calib.yaml').write_text(yaml.safe_dump(c))
PY
run_stock setup_latent_guidance.py --config run_outputs/calib.yaml --ckpt cyclic_calibrated.ckpt --gpu 0 2>&1 | tail -2

stage generating_official
python - <<'PY'
import os, yaml
from pathlib import Path
c=yaml.safe_load(Path('configs/pepbench/test_codesign.yaml').read_text())
c['dataset']['test']['mmap_dir']='datasets/pepbdb/processed'
c['dataset']['test']['specify_index']='datasets/pepbdb/processed/test_index.txt'
c['dataloader']['num_workers']=0
c['n_samples']=int(os.environ.get('N_SAMPLES','10'))
Path('run_outputs/test_cyclic.yaml').write_text(yaml.safe_dump(c))
print('n_samples', c['n_samples'])
PY
rm -rf ./results/cyclic
run_stock generate.py --config run_outputs/test_cyclic.yaml --ckpt cyclic_calibrated.ckpt --gpu 0 --save_dir ./results/cyclic
aws s3 cp ./results/cyclic/results.jsonl "$OUT_S3/results/results.jsonl" --only-show-errors || true

stage cal_metrics
python cal_metrics.py --results ./results/cyclic/results.jsonl 2>&1 | tee "$ROOT/status/cyclic_benchmark_metrics.txt"
aws s3 cp "$ROOT/status/cyclic_benchmark_metrics.txt" "$OUT_S3/cyclic_benchmark_metrics.txt" --only-show-errors || true

stage writing_result_json
# Parse the cal_metrics text into a machine-readable result JSON (DockQ etc.) for the base-vs-current diff.
ROOT="$ROOT" CYCLIC_DATA="$CYCLIC_DATA" CKPT_LABEL="$CKPT_LABEL" CKPT_S3="$CKPT_S3" N_SAMPLES="$N_SAMPLES" AE_SHIM_S3="$AE_SHIM_S3" python - <<'PY'
import json, os, re
from pathlib import Path
ROOT = os.environ.get('ROOT') or '/opt/guangzhou-peptide'
txt = Path(ROOT, 'status/cyclic_benchmark_metrics.txt').read_text()
def grab(pat):
    m = re.search(pat, txt)
    return float(m.group(1)) if m else None
# count kept test complexes from the filter log line (robust: fall back to None).
# The log is append-mode and accumulates across loop iterations, so take the LAST match (this run's).
kept = None
mks = re.findall(r'test kept\s+(\d+)\s+of', Path(ROOT,'status/cyclic_benchmark_eval.log').read_text())
if mks: kept = int(mks[-1])
res = {
  "ckpt": os.environ["CKPT_LABEL"],
  "ckpt_s3": os.environ["CKPT_S3"],
  "benchmark": "PepBDB-cyclic",
  "benchmark_data": os.environ.get("CYCLIC_DATA",""),
  "n_samples": int(os.environ["N_SAMPLES"]),
  "n_test_complexes_kept": kept,
  "ae_shim": os.environ.get("AE_SHIM_S3") or None,
  "status": "ok",
  "metrics": {
    "DockQ_mean":           grab(r'DockQ\(mean\):\s*([0-9.]+)'),
    "SlideAAR_mean":        grab(r'Slide AAR\(mean\):\s*([0-9.]+)'),
    "RMSD_CA_median":       grab(r'RMSD\(CA\)\(median\):\s*([0-9.]+)'),
    "SeqDiversity_mean":    grab(r'Sequence Diversity \(mean\):\s*([0-9.]+)'),
    "StructDiversity_mean": grab(r'Struct Diversity \(mean\):\s*([0-9.]+)'),
    "CodesignDiversity_mean": grab(r'Codesign Diversity \(mean\):\s*([0-9.]+)'),
    "Consistency_mean":     grab(r'Consistency \(mean\):\s*([0-9.]+)'),
  },
  "reference": {"PepGLAD_PepBDB_cyclic_DockQ": 0.403},
}
Path(ROOT,'status/result.json').write_text(json.dumps(res, indent=2))
print(json.dumps(res, indent=2))
PY
aws s3 cp "$ROOT/status/result.json" "$OUT_S3/result.json" --only-show-errors || true
stage cyclic_benchmark_eval_complete
echo "=== DONE $CKPT_LABEL -> $OUT_S3/result.json ==="
