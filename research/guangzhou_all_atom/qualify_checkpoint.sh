#!/bin/bash
# Calibrate a COPY using training data, then perform a three-attempt validation smoke.
set -Eeuo pipefail
ROOT=${1:?PepGLAD checkout required}
CHECKPOINT=${2:?checkpoint path required}
OUT=${3:?output directory required}
CODE=${4:?path to project scripts required}
PYTHON=${PYTHON:-/opt/guangzhou-peptide/venv/bin/python}
export PYTHONPATH="$ROOT"
export OMP_NUM_THREADS=1
cd "$ROOT"
mkdir -p "$OUT"
cp "$CHECKPOINT" "$OUT/model.ckpt"
"$PYTHON" - "$OUT" <<'PY'
import sys, yaml
from pathlib import Path
c=yaml.safe_load(Path('configs/pepbench/ldm/setup_latent_guidance.yaml').read_text())
c['dataloader'].update(num_workers=0, batch_size=4)
Path(sys.argv[1], 'calibration.yaml').write_text(yaml.safe_dump(c))
PY
"$PYTHON" setup_latent_guidance.py --config "$OUT/calibration.yaml" --ckpt "$OUT/model.ckpt" --gpu 0 > "$OUT/calibration.log" 2>&1
"$PYTHON" "$CODE/generation_smoke.py" --checkpoint "$OUT/model.ckpt" --output "$OUT" > "$OUT/generation.log" 2>&1
cat "$OUT/summary.json"
