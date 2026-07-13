"""CI smoke test for the biomni-admet image — run INSIDE the built image before push.

Exercises the exact path the workflow uses (ADMETModel.predict + the post-predict
processing main.nf does), so a dependency drift that breaks inference fails CI here
instead of being discovered in production. Guards the two regressions that have bitten:
  • cat() ... (NoneType, dim=int)  — chemprop/torch/admet-ai drift
  • too many indices for array ... — numpy 2.x (chemprop 1.6.1 needs numpy<2)
Exit non-zero on any failure.
"""
import math
import os

# 0) runtime shape of the box — the "too many indices" regression is runtime-dependent
#    (chemprop's predict DataLoader/threads behave differently on 1 vCPU vs many, which
#    is why it fails on a 1-vCPU Batch container but not on a multi-core CI runner).
#    Run this smoke under `--cpus=1` in CI to reproduce the Batch condition.
try:
    import torch as _torch
    print(f"cpu_count={os.cpu_count()} sched_affinity={len(os.sched_getaffinity(0))} "
          f"torch_threads={_torch.get_num_threads()}", flush=True)
except Exception as _e:
    print(f"cpu-diagnostics: {_e}", flush=True)

# 1) versions — numpy is the load-bearing one for the "too many indices" regression
import numpy as _np
print(f"numpy=={_np.__version__}", flush=True)
assert int(_np.__version__.split(".")[0]) < 2, f"numpy must be <2 for chemprop 1.6.1, got {_np.__version__}"
for _m in ("torch", "chemprop", "admet_ai", "descriptastorus", "rdkit"):
    try:
        _mod = __import__(_m)
        print(f"{_m}=={getattr(_mod, '__version__', '?')}", flush=True)
    except Exception as _e:
        print(f"{_m} import-fail: {_e}", flush=True)

# 2) real prediction — the exact call that crashed with cat(NoneType)
from admet_ai import ADMETModel

model = ADMETModel()
smiles = ["CC(=O)OC1=CC=CC=C1C(=O)O"]  # aspirin
df = model.predict(smiles=smiles)
assert df is not None and len(df) == 1, f"expected 1 row, got {None if df is None else len(df)}"
cols = list(df.columns)
assert len(cols) > 10, f"too few ADMET endpoints predicted: {cols}"

# 3) replicate main.nf's post-predict processing (itertuples + getattr) so the smoke
#    fails here too if a shape/indexing regression is live in the consume path.
mapped = 0
for _smiles_val, row in zip(smiles, df.itertuples(index=False)):
    for admet_col in ("hERG", "BBB_Martins", "Solubility_AqSolDB", "DILI"):
        val = getattr(row, admet_col, None)
        if val is not None and not (isinstance(val, float) and math.isnan(val)):
            mapped += 1
assert mapped > 0, "no ADMET values could be mapped from the prediction frame"

have = [c for c in ("hERG", "BBB_Martins", "Solubility_AqSolDB") if c in cols]
print(f"SMOKE PASS: predicted {len(cols)} endpoints; mapped {mapped} values; sample cols={have}", flush=True)
