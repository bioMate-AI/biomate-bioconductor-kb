# D5 — Physicochemical calibration dataset (`build_physchem_calibration.py`)

**Lane D / D5** of the peptide parallel work plan
(`docs/20260927_PEPTIDE_PARALLEL_WORK_PLAN.md`), sourcing per
`docs/20260926_NEGATIVE_AND_EXPERT_DATA_SOURCING.md` Part 2b.

**Goal:** assemble a **calibration-grade** physicochemical dataset that turns the A1 verify
heads (`peptide_verify.py`) from *ranking-grade* into *calibrated*. Physicochemical properties
are **target-agnostic** — a solubility / permeability / logD model transfers to any new
target's chemistry, so this is the single best lever for the **new-target-generalizability**
pain.

CPU-only ETL. No GPU. No git operations.

---

## What it pulls

| Head (keys A1) | Source(s) | Modality | Task | Rows (full) | Access |
|---|---|---|---|---|---|
| `permeability` | **CycPeptMPDB** (local CSV) | peptide | regression (log Papp) | ~8,466 | local `data/raw/CycPeptMPDB_Peptide_All.csv` |
| `permeability` | `caco2_wang` | small-mol | regression (log10 cm/s) | 910 | TDC-ADME |
| `permeability` | `pampa_ncats` | small-mol | **classification** (0/1) | 2,034 | TDC-ADME |
| `solubility` | `solubility_aqsoldb` (AqSolDB) | small-mol | regression (log S) | 9,982 | TDC-ADME |
| `logD` | `lipophilicity_astrazeneca` | small-mol | regression (logD7.4) | 4,200 | TDC-ADME |
| `ppbr` | `ppbr_az` | small-mol | regression (% bound) | 1,614 | TDC-ADME |

Notes verified against a live PyTDC pull (2026-09-27):
- **The TDC ADME group has no standalone `ESOL` or `MDCK` dataset.** AqSolDB is the solubility
  set. ESOL/MDCK can be added later from MoleculeNet / a direct CSV — deliberately left out to
  avoid a dead pull. The script probes MDCK aliases and skips gracefully (recorded in meta).
- CycPeptMPDB is the **peptide-specific** permeability head; the TDC small-molecule sets
  calibrate the **shared** heads.

### Dependencies

```bash
pip install PyTDC        # optional — without it, TDC tasks are skipped, CycPeptMPDB still runs
pip install rdkit        # REQUIRED (standardization + descriptors)
pip install pandas       # REQUIRED
# Mordred is optional and NOT required; the script uses a compact RDKit descriptor block.
```

**Env gotcha (this machine):** the on-PATH `python3` is Homebrew Python 3.14 (PEP 668
externally-managed; RDKit/pandas present, **PyTDC not installable there without
`--break-system-packages`**). PyTDC also needs `setuptools<81` (newer setuptools removed
`pkg_resources.get_distribution`) and `numpy<2 / pandas<2` for its wheels. A clean venv works:
```bash
python3.10 -m venv venv && source venv/bin/activate
pip install "setuptools<81" "numpy<2" "pandas<2" PyTDC rdkit scikit-learn
```
Without PyTDC the CycPeptMPDB peptide head still builds (`--no-tdc`).

### Download sizes
Each TDC ADME task is small: **~150–300 KB** compressed, few-MB uncompressed; the whole suite
here is **< ~10 MB**. CycPeptMPDB is already local (~19 MB). Total runtime: seconds (CPU).

---

## Run

```bash
# full build (TDC + CycPeptMPDB)
python build_physchem_calibration.py

# CycPeptMPDB only (offline / no PyTDC)
python build_physchem_calibration.py --no-tdc

# cheap validation, no downloads (RDKit standardization/descriptors/splits + CycPeptMPDB slice)
python build_physchem_calibration.py --self-test
```

Outputs land in `data/processed/physchem_calibration/`:
- `physchem_calibration.csv` — the unified long table
- `physchem_calibration.meta.json` — provenance, per-head/per-scheme counts, deps, licenses
- (TDC raw caches under `tdc_raw/`)

---

## Output schema (long format — one row per measurement per split_scheme)

| column | meaning |
|---|---|
| `uid` | stable sha1 of (dataset, source_id, scheme, canonical_smiles) |
| `head` | **`permeability` / `solubility` / `logD` / `ppbr`** — keys the A1 verify head |
| `property` | human-readable property name |
| `value` | numeric measurement, in the head's native scale (`unit`) |
| `unit` | e.g. `log10(cm/s)`, `log10(mol/L)`, `logD7.4`, `percent_bound`, `class{0,1}` |
| `task_type` | `regression` \| `classification` |
| `canonical_smiles` | RDKit-standardized (canonical, salt-stripped largest fragment, stereo kept) |
| `modality` | `peptide` \| `small_molecule` |
| `provenance` | `measured` (assay) \| `computed` (reserved) |
| `source` / `dataset` / `source_id` | attribution |
| `split` | `train` \| `valid` \| `test` |
| `split_scheme` | **`scaffold` \| `random`** — both emitted (see eval discipline) |
| `license` | short per-source license tag |
| `MW,LogP,TPSA,HBD,HBA,RotB,NumRings,FracCsp3` | **free RDKit descriptor features** (surrogate + applicability domain) |

Each measurement appears **twice** (once per `split_scheme`); filter on `split_scheme` before
training/eval.

---

## Eval discipline (IMPORTANT — read before reporting any R²)

For the **peptide permeability head**, report the **SCAFFOLD-split** number as the real
generalization metric. CycPeptMPDB has **documented random-split inflation**; the honest
scaffold-split ceiling is **~R² 0.48–0.50**, and **HELM-BERT's scaffold R² 0.483** is the
public bar to be aware of (per D5 / the strength gate in the work plan). The `random` split is
**diagnostic only** — a high random-split R² does not mean the head generalizes.

- **Peptide permeability:** Bemis-Murcko generic-scaffold family-disjoint split (matches
  `permeability_predictor.py` / `cycpeptmpdb_to_pepglad.py`). **Verified zero scaffold leakage
  across train/valid/test.**
- **TDC small-molecule tasks:** TDC's own `get_split(method="scaffold")` for the scaffold
  scheme (verified zero train∩test SMILES overlap) + a deterministic hash random split for
  parity.

The scaffold split is intentionally imbalanced in fraction (families cluster) — that is the
honest cost of family-disjointness, not a bug.

---

## How it feeds `peptide_verify.py` (A1 heads)

`peptide_verify.py` currently trains its **permeability** field on-the-fly from CycPeptMPDB
inside `_score_permeability` (ECFP4 + bootstrap-bagged HistGBM, ranking-grade, scaffold-R² ~0.23),
and has **no solubility / logD heads at all**. This dataset is the calibration substrate to fix
both:

1. **Permeability (calibrate the existing head).** Train the permeability regressor on the
   `head=="permeability" & split_scheme=="scaffold" & split=="train"` rows; evaluate on
   `split=="test"`; **calibrate** predicted uncertainties (e.g. isotonic / temperature scaling
   on `valid`) so the ensemble std is a real confidence interval, not just a spread. Report the
   scaffold-split R² against the 0.483 bar. Peptide rows (`modality=="peptide"`) are the target
   distribution; the small-mol Caco-2/PAMPA rows widen the applicability domain.
2. **New heads (solubility, logD, ppbr).** Add `_score_solubility`, `_score_logD` (and
   optionally `_score_ppbr`) to `peptide_verify.py` mirroring `_score_permeability`: build a
   Morgan FP for the candidate, train on the corresponding `head==...` subset here, predict
   mean + calibrated std, tag `provenance="predicted"`. These plug into `PeptideProperties` as
   new `PropertyValue` fields and flow through `verify_batch` → A2 selection unchanged.
3. **Free descriptor features.** The `MW/LogP/TPSA/HBD/HBA/RotB/NumRings/FracCsp3` columns are
   ready-made surrogate features and an **applicability-domain** signal (flag candidates whose
   descriptors fall outside the training envelope → widen uncertainty).
4. **Feeds M5** (loop wiring): calibrated A1 heads + D3 negatives make the verify layer a
   credible therapy-loop gate (work-plan strength gate: developability head ≥ HELM-BERT
   scaffold R² 0.483).

This dataset is **calibration substrate only** — it does not modify `peptide_verify.py` or any
scorer. Wiring the new heads is the M5 step.

---

## License notes (commercial posture)

- **CycPeptMPDB — CC BY-NC-SA 4.0 (NON-COMMERCIAL).** OK to train/calibrate heads **internally**;
  **do not redistribute the derived dataset or use commercially** without a license. Attribute
  Li et al., CycPeptMPDB. Keep the derived CSV internal.
- **TDC-ADME datasets — individually permissive:** AqSolDB (CC0), Caco2_Wang / PAMPA_NCATS /
  PPBR_AZ (public), Lipophilicity_AstraZeneca (CC-BY-SA via MoleculeNet). PyTDC harness is MIT.
  Verify each per-task license before **redistributing** derived data; using the signal to
  train internally is fine.
- **RDKit descriptors** — BSD, freely usable.

Bottom line: **train/calibrate internally freely; do not ship the derived dataset** (CycPeptMPDB
NC + a couple of CC-BY-SA sources).
