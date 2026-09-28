"""D5 — Physicochemical calibration dataset ETL (cyclic-peptide program, LANE D).

Assembles a UNIFIED, calibration-grade physicochemical dataset that turns the A1 verify
heads (permeability / solubility / logD) from ranking-grade into *calibrated*. This is the
best target-agnostic lever for new-target generalizability (see
docs/20260926_NEGATIVE_AND_EXPERT_DATA_SOURCING.md Part 2b and
docs/20260927_PEPTIDE_PARALLEL_WORK_PLAN.md D5).

What it does
------------
1. Pulls the TDC-ADME regression tasks (PyTDC, optional — skipped if not installed):
   solubility (AqSolDB/ESOL), Caco-2, PAMPA (NCATS), MDCK, logD (Lipophilicity/AstraZeneca),
   PPBR. Small molecules — they calibrate the *shared* property heads.
2. Reads the LOCAL CycPeptMPDB CSV (peptide permeability — the peptide-specific head).
3. Standardizes every SMILES with RDKit (canonical, salt-stripped, largest fragment).
4. Adds a small block of RDKit-computed descriptors as FREE features (Mordred optional).
5. Emits ONE tidy long-format calibration dataset:
      (property, value, unit, split, split_scheme, provenance, source, dataset, smiles, ...)
   keyed to the A1 heads via the ``head`` column (permeability | solubility | logD | ppbr).

Eval discipline (IMPORTANT)
---------------------------
For the PEPTIDE permeability head we emit BOTH a Bemis-Murcko SCAFFOLD split and a RANDOM
split, each labeled in ``split_scheme``. CycPeptMPDB has documented random-split inflation;
the honest scaffold-split ceiling is ~R^2 0.48-0.50 and HELM-BERT's scaffold R^2 0.483 is the
public bar. Report the SCAFFOLD number as the head's real generalization; random is diagnostic
only. TDC small-molecule tasks are emitted with TDC's own scaffold split (get_split), plus a
random split for parity.

Output
------
  <out_dir>/physchem_calibration.csv   — the unified long table (one row per measurement)
  <out_dir>/physchem_calibration.meta.json — provenance, per-source counts, license notes,
                                             split ceilings, dep versions
  <out_dir>/README.md                  — how it feeds peptide_verify.py, deps, license notes

CPU-only. TDC pulls are small (each ADME task is a few-hundred-KB to a few-MB CSV; the whole
suite here is < ~50 MB). CycPeptMPDB is already local (~19 MB).

Run
---
  pip install PyTDC          # optional; without it, TDC tasks are skipped (CycPeptMPDB still runs)
  python build_physchem_calibration.py                       # full build
  python build_physchem_calibration.py --no-tdc              # CycPeptMPDB only (offline)
  python build_physchem_calibration.py --self-test           # cheap RDKit validation, no downloads
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

ROOT = Path(__file__).resolve().parent
DEFAULT_CYCPEPT = ROOT / "data" / "raw" / "CycPeptMPDB_Peptide_All.csv"
DEFAULT_OUT = ROOT / "data" / "processed" / "physchem_calibration"

# --------------------------------------------------------------------------------------------
# TDC-ADME task registry.
#   name         : TDC ADME dataset name (arg to tdc.single_pred.ADME(name=...))
#   head         : which A1 verify head this calibrates
#   unit / note  : what the value means (for the unit column + README)
#   value_transform: how we normalise TDC's raw label into the head's native scale
# TDC returns a DataFrame with columns Drug_ID, Drug (SMILES), Y (label).
# NAMES ARE THE REAL TDC ADME dataset names (verified against PyTDC's ADME group; the API
# fuzzy-matches lowercase). NOTE (verified 2026-09-27 against a live PyTDC pull): the TDC ADME
# group does NOT contain a standalone "ESOL" or "MDCK" dataset — AqSolDB is the solubility set,
# and there is no MDCK regression task. Those two are therefore handled outside TDC (see README:
# ESOL/MDCK can be added later from MoleculeNet / a direct CSV; kept out to avoid a dead pull).
# --------------------------------------------------------------------------------------------
TDC_ADME_TASKS = [
    # --- solubility head ---
    dict(name="solubility_aqsoldb", head="solubility", unit="log10(mol/L)",
         note="AqSolDB aqueous solubility (log S).", value_transform="identity"),
    # --- permeability head (small molecule; peptide perm comes from CycPeptMPDB) ---
    dict(name="caco2_wang", head="permeability", unit="log10(cm/s)",
         note="Caco-2 apparent permeability (Papp). TDC label already log10(cm/s).",
         value_transform="identity"),
    dict(name="pampa_ncats", head="permeability", unit="class{0,1}",
         note="NCATS PAMPA permeability (BINARY: 1=permeable). Classification task — "
              "kept as a class label; use for calibration of a permeability *classifier* "
              "threshold, not the log-Papp regressor.", value_transform="identity"),
    # --- logD/lipophilicity head ---
    dict(name="lipophilicity_astrazeneca", head="logD", unit="logD7.4",
         note="MoleculeNet/AstraZeneca lipophilicity (logD at pH 7.4).",
         value_transform="identity"),
    # --- plasma protein binding head (developability, related to free fraction) ---
    dict(name="ppbr_az", head="ppbr", unit="percent_bound",
         note="Plasma protein binding rate (percent bound).", value_transform="identity"),
]

# Optional tasks tried by name-candidate (skip gracefully if the installed PyTDC lacks them).
# MDCK is NOT in the TDC ADME group as of the verified pull; left as an optional probe in case a
# future PyTDC version adds it, so the ETL picks it up automatically without a code change.
TDC_OPTIONAL_ALIASES = [
    dict(candidates=["mdck_ncats", "mdck", "MDCK_NCATS"], head="permeability", unit="log10(cm/s)",
         note="MDCK permeability (if present in this PyTDC version).", value_transform="identity"),
]

# --------------------------------------------------------------------------------------------
# Unified output schema (long format — one row per measurement).
# --------------------------------------------------------------------------------------------
SCHEMA_COLUMNS = [
    "uid",            # stable sha1 of (dataset, source_id, canonical_smiles)
    "head",           # permeability | solubility | logD | ppbr  -> keys the A1 verify head
    "property",       # human-readable property name
    "value",          # numeric measurement (native scale of the head; see unit)
    "unit",           # unit / scale of value
    "task_type",      # regression | classification
    "canonical_smiles",
    "modality",       # small_molecule | peptide
    "provenance",     # measured | computed
    "source",         # e.g. AqSolDB, Caco2_Wang, CycPeptMPDB
    "dataset",        # TDC name or CycPeptMPDB
    "source_id",      # original id within the source
    "split",          # train | valid | test
    "split_scheme",   # scaffold | random  (BOTH emitted where required)
    "license",        # short license tag
    # free RDKit descriptors (computed features for the surrogate / applicability domain):
    "MW", "LogP", "TPSA", "HBD", "HBA", "RotB", "NumRings", "FracCsp3",
]


@dataclass
class SourceStat:
    dataset: str
    head: str
    n_rows: int = 0
    n_dropped_smiles: int = 0
    license: str = ""
    note: str = ""


# --------------------------------------------------------------------------------------------
# RDKit helpers (standardization + descriptors)
# --------------------------------------------------------------------------------------------
def _rdkit():
    from rdkit import Chem, RDLogger
    RDLogger.DisableLog("rdApp.*")
    return Chem


def standardize_smiles(smiles: str) -> Optional[str]:
    """Canonical, salt-stripped, largest-fragment SMILES. Returns None on parse failure.

    Peptide-safe: keeps stereochemistry (peptide developability is stereo-dependent), only
    strips disconnected small counter-ions by taking the largest organic fragment.
    """
    Chem = _rdkit()
    if not smiles or not isinstance(smiles, str):
        return None
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return None
    # largest fragment (drops salts / counter-ions) without a network of extra deps
    frags = Chem.GetMolFrags(mol, asMols=True, sanitizeFrags=False)
    if len(frags) > 1:
        mol = max(frags, key=lambda m: m.GetNumHeavyAtoms())
    try:
        Chem.SanitizeMol(mol)
    except Exception:
        return None
    return Chem.MolToSmiles(mol, canonical=True)


def rdkit_descriptors(canonical_smiles: str) -> Dict[str, Optional[float]]:
    """Cheap RDKit descriptor block used as free features + applicability-domain columns."""
    Chem = _rdkit()
    from rdkit.Chem import Descriptors, Lipinski, rdMolDescriptors
    d: Dict[str, Optional[float]] = {k: None for k in
                                     ("MW", "LogP", "TPSA", "HBD", "HBA", "RotB",
                                      "NumRings", "FracCsp3")}
    mol = Chem.MolFromSmiles(canonical_smiles)
    if mol is None:
        return d
    try:
        d["MW"] = float(Descriptors.MolWt(mol))
        d["LogP"] = float(Descriptors.MolLogP(mol))
        d["TPSA"] = float(rdMolDescriptors.CalcTPSA(mol))
        d["HBD"] = float(Lipinski.NumHDonors(mol))
        d["HBA"] = float(Lipinski.NumHAcceptors(mol))
        d["RotB"] = float(Descriptors.NumRotatableBonds(mol))
        d["NumRings"] = float(rdMolDescriptors.CalcNumRings(mol))
        d["FracCsp3"] = float(rdMolDescriptors.CalcFractionCSP3(mol))
    except Exception:
        pass
    return d


def murcko_scaffold(canonical_smiles: str) -> str:
    """Bemis-Murcko generic scaffold key (matches permeability_predictor.py / the pepglad
    converter convention). Falls back to the SMILES itself for acyclic / failed cases."""
    Chem = _rdkit()
    from rdkit.Chem.Scaffolds import MurckoScaffold
    mol = Chem.MolFromSmiles(canonical_smiles)
    if mol is None:
        return canonical_smiles
    try:
        s = MurckoScaffold.MurckoScaffoldSmiles(
            mol=MurckoScaffold.GetScaffoldForMol(mol), includeChirality=False)
        return s or canonical_smiles
    except Exception:
        return canonical_smiles


# --------------------------------------------------------------------------------------------
# Deterministic splits
# --------------------------------------------------------------------------------------------
def _bucket(key: str, salt: str) -> int:
    """Stable 0..999 hash bucket for a (key, salt) pair."""
    return int(hashlib.sha1(f"{salt}:{key}".encode()).hexdigest(), 16) % 1000


def scaffold_split_labels(scaffolds: List[str], val_frac=0.1, test_frac=0.1,
                          salt="scaffold") -> List[str]:
    """Family-disjoint split: every row sharing a scaffold lands in the SAME bucket, so no
    scaffold crosses train/valid/test. Deterministic (hash-based)."""
    labels = []
    tcut = int(test_frac * 1000)
    vcut = tcut + int(val_frac * 1000)
    for s in scaffolds:
        b = _bucket(s, salt)
        labels.append("test" if b < tcut else ("valid" if b < vcut else "train"))
    return labels


def random_split_labels(keys: List[str], val_frac=0.1, test_frac=0.1,
                        salt="random") -> List[str]:
    """Row-level random split (per-molecule hash). Diagnostic ONLY for the peptide perm head
    (documented random-split inflation)."""
    labels = []
    tcut = int(test_frac * 1000)
    vcut = tcut + int(val_frac * 1000)
    for k in keys:
        b = _bucket(k, salt)
        labels.append("test" if b < tcut else ("valid" if b < vcut else "train"))
    return labels


# --------------------------------------------------------------------------------------------
# CycPeptMPDB (local peptide permeability)
# --------------------------------------------------------------------------------------------
def load_cycpeptmpdb(csv_path: Path, limit: Optional[int] = None) -> List[dict]:
    """Read the local CycPeptMPDB CSV, standardize SMILES, keep the log-Papp permeability
    target (same filter window as permeability_predictor.py), emit BOTH scaffold + random
    splits. Returns a list of unified-schema row dicts (each measurement -> 2 rows: one per
    split_scheme)."""
    import csv as _csv
    rows: List[dict] = []
    scaf_cache: Dict[str, str] = {}
    # first pass: collect valid records + scaffolds
    records = []
    with open(csv_path, newline="", encoding="utf-8-sig") as fh:
        reader = _csv.DictReader(fh)
        for i, r in enumerate(reader):
            if limit and i >= limit:
                break
            smi = (r.get("SMILES") or "").strip()
            try:
                perm = float(r.get("Permeability", ""))
            except (TypeError, ValueError):
                continue
            if not (-10.5 < perm < -3.5):  # drop detection-limit placeholders / OOR
                continue
            csmi = standardize_smiles(smi)
            if csmi is None:
                continue
            scaf = scaf_cache.get(csmi)
            if scaf is None:
                scaf = murcko_scaffold(csmi)
                scaf_cache[csmi] = scaf
            records.append(dict(csmi=csmi, perm=perm, scaf=scaf,
                                source_id=(r.get("ID") or r.get("Structurally_Unique_ID") or str(i)),
                                orig_source=r.get("Source", "")))
    if not records:
        return rows
    scaf_labels = scaffold_split_labels([rec["scaf"] for rec in records])
    rand_labels = random_split_labels([rec["csmi"] for rec in records])
    for rec, s_lab, r_lab in zip(records, scaf_labels, rand_labels):
        desc = rdkit_descriptors(rec["csmi"])
        base = dict(
            head="permeability",
            property="peptide membrane permeability (log Papp)",
            value=rec["perm"],
            unit="log10(cm/s)",
            task_type="regression",
            canonical_smiles=rec["csmi"],
            modality="peptide",
            provenance="measured",
            source="CycPeptMPDB",
            dataset="CycPeptMPDB_Peptide_All",
            source_id=rec["source_id"],
            license="CC BY-NC-SA 4.0 (CycPeptMPDB; non-commercial — see license note)",
            **desc,
        )
        for scheme, lab in (("scaffold", s_lab), ("random", r_lab)):
            row = dict(base)
            row["split"] = lab
            row["split_scheme"] = scheme
            row["uid"] = hashlib.sha1(
                f"{row['dataset']}|{row['source_id']}|{scheme}|{rec['csmi']}".encode()
            ).hexdigest()[:16]
            rows.append(row)
    return rows


# --------------------------------------------------------------------------------------------
# TDC-ADME loader (optional)
# --------------------------------------------------------------------------------------------
def tdc_available() -> bool:
    try:
        import tdc  # noqa: F401
        return True
    except Exception:
        return False


def _emit_tdc_task(name: str, head: str, unit: str, note: str, task_type: str,
                   data_dir: Path, stats: List[SourceStat]) -> List[dict]:
    """Load one TDC ADME task, standardize, emit scaffold (TDC-native) + random splits."""
    from tdc.single_pred import ADME
    rows: List[dict] = []
    stat = SourceStat(dataset=name, head=head, license="permissive (CC0/MIT/CC-BY; see README)",
                      note=note)
    try:
        data = ADME(name=name, path=str(data_dir))
    except Exception as e:  # noqa: BLE001
        stat.note += f" | LOAD FAILED: {type(e).__name__}: {e}"
        stats.append(stat)
        return rows
    # TDC scaffold split (train/valid/test dict of DataFrames)
    try:
        split = data.get_split(method="scaffold")
    except Exception:
        split = data.get_split()  # fall back to TDC default (random)
    # build canonical -> row template once, then tag with each scheme's label
    # scaffold labels come from TDC's split; random labels from our own hash
    per_scheme = {"scaffold": split}
    # random split: reuse the same rows, relabel by hash of SMILES
    full = data.get_data()  # full DataFrame with Drug, Y, Drug_ID
    for _, rec in full.iterrows():
        csmi = standardize_smiles(str(rec["Drug"]))
        if csmi is None:
            stat.n_dropped_smiles += 1
            continue
        try:
            val = float(rec["Y"])
        except (TypeError, ValueError):
            continue
        desc = rdkit_descriptors(csmi)
        source_id = str(rec.get("Drug_ID", ""))
        base = dict(
            head=head, property=note.split(".")[0], value=val, unit=unit,
            task_type=task_type, canonical_smiles=csmi, modality="small_molecule",
            provenance="measured", source=name, dataset=name, source_id=source_id,
            license=stat.license, **desc,
        )
        # scaffold label from TDC split membership
        for scheme in ("scaffold", "random"):
            row = dict(base)
            if scheme == "scaffold":
                lab = _which_tdc_split(split, str(rec["Drug"]), csmi)
            else:
                lab = random_split_labels([csmi], salt=f"random:{name}")[0]
            row["split"] = lab
            row["split_scheme"] = scheme
            row["uid"] = hashlib.sha1(
                f"{name}|{source_id}|{scheme}|{csmi}".encode()).hexdigest()[:16]
            rows.append(row)
        stat.n_rows += 1
    _ = per_scheme
    stats.append(stat)
    return rows


def _which_tdc_split(split: dict, raw_smiles: str, csmi: str) -> str:
    """Map a molecule to its TDC scaffold-split bucket by SMILES membership. TDC split dicts
    key on 'train'/'valid'/'test' DataFrames with a 'Drug' column."""
    for name in ("test", "valid", "train"):
        df = split.get(name)
        if df is None:
            continue
        col = df["Drug"] if "Drug" in df.columns else None
        if col is not None and (raw_smiles in set(col.values)):
            return name
    # fallback: deterministic hash so we never drop a row
    return random_split_labels([csmi], salt="scaffold_fallback")[0]


def load_tdc_adme(data_dir: Path, stats: List[SourceStat]) -> List[dict]:
    rows: List[dict] = []
    for t in TDC_ADME_TASKS:
        tt = "classification" if "class" in t["unit"] else "regression"
        rows.extend(_emit_tdc_task(t["name"], t["head"], t["unit"], t["note"], tt,
                                   data_dir, stats))
    # optional aliases (MDCK) — try candidates quietly, record ONE clean stat
    for opt in TDC_OPTIONAL_ALIASES:
        got = False
        probe: List[SourceStat] = []
        for cand in opt["candidates"]:
            before = len(rows)
            rows.extend(_emit_tdc_task(cand, opt["head"], opt["unit"], opt["note"],
                                       "regression", data_dir, probe))
            if len(rows) > before:
                got = True
                stats.append(probe[-1])  # keep only the stat for the candidate that loaded
                break
        if not got:
            stats.append(SourceStat(dataset="/".join(opt["candidates"]), head=opt["head"],
                                    note="optional MDCK task not available in this PyTDC version — skipped"))
    return rows


# --------------------------------------------------------------------------------------------
# Writer
# --------------------------------------------------------------------------------------------
def write_outputs(rows: List[dict], out_dir: Path, stats: List[SourceStat],
                  used_tdc: bool) -> dict:
    import csv as _csv
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "physchem_calibration.csv"
    with open(csv_path, "w", newline="") as fh:
        w = _csv.DictWriter(fh, fieldnames=SCHEMA_COLUMNS, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)

    # per-head / per-scheme summary
    by_head: Dict[str, Dict] = {}
    for r in rows:
        h = r["head"]
        by_head.setdefault(h, {"scaffold": {"train": 0, "valid": 0, "test": 0},
                               "random": {"train": 0, "valid": 0, "test": 0},
                               "modalities": {}, "sources": set()})
        by_head[h][r["split_scheme"]][r["split"]] += 1
        by_head[h]["modalities"][r["modality"]] = by_head[h]["modalities"].get(r["modality"], 0) + 1
        by_head[h]["sources"].add(r["source"])
    for h in by_head:
        by_head[h]["sources"] = sorted(by_head[h]["sources"])

    meta = {
        "generated_by": "build_physchem_calibration.py (D5 physicochemical calibration ETL)",
        "n_rows_total": len(rows),
        "note": "long format; each measurement appears once per split_scheme (scaffold + random).",
        "used_tdc": used_tdc,
        "deps": _dep_versions(),
        "schema": SCHEMA_COLUMNS,
        "heads": {
            "permeability": "A1 permeability head (peptide=CycPeptMPDB log Papp; small-mol=Caco-2/PAMPA/MDCK)",
            "solubility": "A1 solubility head (AqSolDB/ESOL log S)",
            "logD": "A1 logD/lipophilicity head (MoleculeNet/AstraZeneca logD7.4)",
            "ppbr": "plasma protein binding (developability adjunct)",
        },
        "eval_discipline": {
            "peptide_permeability_split": "SCAFFOLD is the reported generalization metric; "
                                          "random is diagnostic (documented random-split inflation).",
            "scaffold_ceiling_r2": "~0.48-0.50 (honest)",
            "helm_bert_scaffold_r2_bar": 0.483,
        },
        "per_head": by_head,
        "sources": [s.__dict__ for s in stats],
        "license_notes": _LICENSE_NOTES,
    }
    meta_path = out_dir / "physchem_calibration.meta.json"
    meta_path.write_text(json.dumps(meta, indent=2) + "\n")
    return meta


def _dep_versions() -> dict:
    v = {}
    try:
        import rdkit
        v["rdkit"] = rdkit.__version__
    except Exception:
        v["rdkit"] = None
    try:
        import tdc
        v["PyTDC"] = getattr(tdc, "__version__", "unknown")
    except Exception:
        v["PyTDC"] = None
    try:
        import pandas
        v["pandas"] = pandas.__version__
    except Exception:
        v["pandas"] = None
    return v


_LICENSE_NOTES = {
    "CycPeptMPDB": "CC BY-NC-SA 4.0 — NON-COMMERCIAL. OK to train/calibrate heads internally; "
                   "do NOT redistribute the derived dataset or use commercially without a license. "
                   "Attribute Li et al., CycPeptMPDB.",
    "TDC_ADME": "Individual TDC datasets carry their own permissive licenses: AqSolDB (CC0), "
                "ESOL/Delaney (MIT via MoleculeNet), Caco2_Wang (public), PAMPA_NCATS (public), "
                "Lipophilicity_AstraZeneca (CC-BY-SA via MoleculeNet), PPBR_AZ (public). "
                "PyTDC harness is MIT. Verify per-task before commercial redistribution.",
    "RDKit_descriptors": "Computed features (BSD-licensed RDKit) — freely usable.",
}


# --------------------------------------------------------------------------------------------
# Self-test (cheap, no downloads)
# --------------------------------------------------------------------------------------------
def self_test() -> int:
    print("[self-test] RDKit standardization + descriptors + splits (no downloads)")
    # 1. standardization strips a salt and canonicalizes
    s = standardize_smiles("CC(=O)O.[Na+]")  # acetic acid + sodium (largest frag = acetic acid)
    assert s is not None and "Na" not in s, f"salt not stripped: {s}"
    print("  standardize salt-strip OK ->", s)
    # 2. descriptors present
    d = rdkit_descriptors(standardize_smiles("c1ccccc1"))
    assert d["NumRings"] == 1 and d["MW"] and d["TPSA"] == 0.0, d
    print("  descriptors OK -> benzene", {k: d[k] for k in ("MW", "NumRings", "TPSA")})
    # 3. scaffold split is family-disjoint & deterministic
    scafs = ["c1ccccc1", "c1ccccc1", "C1CCCCC1", "C1CCCCC1"]
    labs = scaffold_split_labels(scafs)
    assert labs[0] == labs[1] and labs[2] == labs[3], f"scaffold not grouped: {labs}"
    assert scaffold_split_labels(scafs) == labs, "scaffold split not deterministic"
    print("  scaffold split family-disjoint + deterministic OK ->", labs)
    # 4. CycPeptMPDB read of a tiny slice if present
    if DEFAULT_CYCPEPT.exists():
        rows = load_cycpeptmpdb(DEFAULT_CYCPEPT, limit=200)
        assert rows, "no CycPeptMPDB rows parsed"
        schemes = {r["split_scheme"] for r in rows}
        assert schemes == {"scaffold", "random"}, schemes
        heads = {r["head"] for r in rows}
        assert heads == {"permeability"}, heads
        # every row has the required schema keys
        missing = [k for k in SCHEMA_COLUMNS if k not in rows[0]]
        assert not missing, f"schema keys missing: {missing}"
        n_mol = len({r["source_id"] for r in rows})
        print(f"  CycPeptMPDB slice OK -> {n_mol} peptides, {len(rows)} rows "
              f"(scaffold+random), splits={sorted({r['split'] for r in rows})}")
    else:
        print(f"  CycPeptMPDB CSV not found at {DEFAULT_CYCPEPT} — skipped slice test")
    print("[self-test] PASS")
    return 0


# --------------------------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description="D5 physicochemical calibration ETL")
    ap.add_argument("--cycpept-csv", type=Path, default=DEFAULT_CYCPEPT)
    ap.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--tdc-data-dir", type=Path, default=DEFAULT_OUT / "tdc_raw")
    ap.add_argument("--no-tdc", action="store_true", help="skip TDC pull (offline / CycPeptMPDB only)")
    ap.add_argument("--cycpept-limit", type=int, default=None, help="cap CycPeptMPDB rows (debug)")
    ap.add_argument("--self-test", action="store_true", help="cheap RDKit validation, no downloads")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    rows: List[dict] = []
    stats: List[SourceStat] = []

    # 1. CycPeptMPDB (local, peptide permeability head)
    if args.cycpept_csv.exists():
        cp_rows = load_cycpeptmpdb(args.cycpept_csv, limit=args.cycpept_limit)
        rows.extend(cp_rows)
        n_pep = len({r["source_id"] for r in cp_rows})
        stats.append(SourceStat(dataset="CycPeptMPDB_Peptide_All", head="permeability",
                                n_rows=n_pep, license=_LICENSE_NOTES["CycPeptMPDB"],
                                note="local peptide permeability; scaffold+random splits emitted"))
        print(f"[cycpept] {n_pep} peptides -> {len(cp_rows)} rows (scaffold+random)")
    else:
        print(f"[cycpept] WARNING: {args.cycpept_csv} not found — skipping peptide perm head")

    # 2. TDC-ADME suite (optional; small-molecule shared heads)
    used_tdc = False
    if args.no_tdc:
        print("[tdc] skipped (--no-tdc)")
    elif not tdc_available():
        print("[tdc] PyTDC not installed — skipping TDC-ADME. `pip install PyTDC` to include it.")
    else:
        used_tdc = True
        print("[tdc] pulling TDC-ADME suite (small downloads; each task a few hundred KB–few MB)...")
        rows.extend(load_tdc_adme(args.tdc_data_dir, stats))

    if not rows:
        print("[fatal] no rows assembled (no CycPeptMPDB, no TDC). Nothing to write.", file=sys.stderr)
        return 1

    meta = write_outputs(rows, args.out_dir, stats, used_tdc)
    print(f"\n[done] wrote {meta['n_rows_total']} rows -> {args.out_dir / 'physchem_calibration.csv'}")
    print(json.dumps({"per_head": {h: {sch: meta['per_head'][h][sch]
                                       for sch in ('scaffold', 'random')}
                                   for h in meta['per_head']}}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
