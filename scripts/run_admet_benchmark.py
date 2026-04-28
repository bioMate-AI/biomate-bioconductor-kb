#!/usr/bin/env python3
"""
run_admet_benchmark.py — BioMate ADMET Model Accuracy Benchmark

Evaluates BioMate's ADMET predictions against published benchmark datasets
with bootstrap confidence intervals, for inclusion in the CRO comparison
tech report (Option A).

Run inside the biomni-tools Docker container, which provides RDKit.

Datasets evaluated
------------------
* hERG    — ChEMBL hERG IC50 data (binary: IC50 ≤ 10 µM = blocker)
            Published AUROC target: ≥ 0.84 (Cai et al. 2019 J Chem Inf Model)
* DILI    — DILIrank (Chen et al. 2016 Hepatology); vMost-DILI-concern vs
            vNo-DILI-concern.  Target: AUROC ≥ 0.73
* Ames    — Hansen et al. 2009 Chem Res Toxicol (6,512 compounds)
            Target: AUROC ≥ 0.82 (Kazius et al. 2005)
* ClinTox — MoleculeNet ClinTox (FDA approved vs clinical toxicity failed)
            Target: AUROC ≥ 0.80 (Wu et al. 2018 Mol Syst Biol)
* Tox21   — MoleculeNet Tox21, SR-MMP (mitochondrial membrane potential)
            Target: AUROC ≥ 0.83 (Wu et al. 2018)

BioMate prediction functions
-----------------------------
* hERG  : log10(IC50_µM) = 1.4 − 0.30 × logP  (Aronov 2008; Price et al. 2009)
          Score = sigmoid(−(log10(IC50_µM) − 1.0)) — higher = more likely blocker
* DILI  : Lammert 2010 / Fontana 2010: logP > 4.0 AND MW > 400 → high prob;
          logP > 2.5 OR MW > 350 → medium
* Ames  : Structural alert ensemble (Kazius 2005 Table 1 SMARTS + reliability weights)
* ClinTox : Lipophilicity + MW + TPSA + Ames alert boost
* Tox21   : logP + MW heuristic (Naven et al. 2013 Chem Res Toxicol)

Usage
-----
    # Inside biomni-tools Docker container:
    python scripts/run_admet_benchmark.py \\
        --datasets herg,dili,ames,clintox,tox21 \\
        --output results/admet_benchmark/ \\
        --data-dir data/admet/ \\
        [--n-bootstrap 1000] [--seed 42]

Output files
------------
    results/admet_benchmark/
        metrics.json          — AUROC + 90% CI for each dataset
        per_compound.csv      — SMILES, true_label, pred_score, dataset columns
        roc_data.json         — fpr/tpr arrays for Figure 2 ROC curves

References
----------
* Aronov 2008 J Med Chem 51:6632 (hERG logP model)
* Cai et al. 2019 J Chem Inf Model 59:1 (hERG AUROC benchmark)
* Chen et al. 2016 Hepatology 63:388 (DILIrank)
* Hansen et al. 2009 Chem Res Toxicol 22:2088 (Ames dataset)
* Kazius et al. 2005 J Med Chem 48:312 (Ames structural alerts + benchmark)
* Lammert et al. 2010 Toxicol Sci 116:536 (DILI logP/MW model)
* Naven et al. 2013 Chem Res Toxicol 26:634 (Tox21 SR-MMP)
* Wu et al. 2018 Mol Syst Biol 14:e6027 (MoleculeNet)
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import math
import random
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

log = logging.getLogger("admet_bench")


# ---------------------------------------------------------------------------
# RDKit — required; fail early with a clear message if missing
# ---------------------------------------------------------------------------
try:
    from rdkit import Chem
    from rdkit.Chem import Descriptors, rdMolDescriptors, MolFromSmarts
except ImportError:
    sys.exit(
        "ERROR: RDKit is required but not installed.\n"
        "Run this script inside the biomni-tools Docker container:\n"
        "  docker run --rm -v $PWD:/work biomni-tools python /work/scripts/run_admet_benchmark.py ...\n"
        "Or install RDKit: conda install -c conda-forge rdkit"
    )


# ---------------------------------------------------------------------------
# Structural-alert SMARTS for Ames mutagenicity
# Based on Kazius et al. 2005 J Med Chem 48:312 Table 1
# ---------------------------------------------------------------------------
_AMES_SMARTS: dict[str, tuple[str, float]] = {
    # (SMARTS pattern, reliability weight from Kazius Table 1)
    "nitro_aromatic":         ("[cH0][N+](=O)[O-]", 0.93),
    "aromatic_primary_amine": ("[NH2]c",             0.81),
    "nitroso_aromatic":       ("[cH0]N=O",           0.89),
    "n_nitroso":              ("N-N=O",              0.96),
    "epoxide":                ("C1OC1",              0.78),
    "aziridine":              ("C1NC1",              0.85),
    "michael_acceptor":       ("C=CC=O",             0.74),
    "aliphatic_halide":       ("[CX4][F,Cl,Br,I]",  0.67),
    "acylhalide":             ("[CX3](=O)[Cl,Br]",  0.91),
    "hydrazine":              ("NN",                 0.71),
    "n_oxide_het":            ("[nH0][O-]",          0.88),
    "diazo":                  ("[N]=[N+]",           0.94),
}

# Pre-compile SMARTS patterns once at import time
_AMES_PATTERNS: list[tuple[str, object, float]] = []
for _name, (_smarts, _weight) in _AMES_SMARTS.items():
    _pat = MolFromSmarts(_smarts)
    if _pat is not None:
        _AMES_PATTERNS.append((_name, _pat, _weight))


# ---------------------------------------------------------------------------
# BioMate ADMET prediction functions
# Mirror the RDKit phase of predict_admet_properties/main.nf
# ---------------------------------------------------------------------------

def predict_herg(smiles: str) -> Optional[float]:
    """
    BioMate hERG blocker probability.

    Model: log10(IC50_µM) = 1.4 − 0.30 × logP  (Aronov 2008 J Med Chem 51:6632)
    Score: sigmoid(−(log10(IC50_µM) − 1.0)) ∈ [0,1]
    Higher score = more likely blocker (IC50 ≤ 10 µM).
    """
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return None
    logp = Descriptors.MolLogP(mol)
    log10_ic50 = 1.4 - 0.30 * logp   # Aronov 2008
    # Centre at IC50 = 10 µM (log10 = 1.0); positive x → likely blocker
    x = -(log10_ic50 - 1.0)
    score = 1.0 / (1.0 + math.exp(-1.5 * x))
    return round(score, 6)


def predict_dili(smiles: str) -> Optional[float]:
    """
    BioMate DILI risk probability.

    Model: Lammert et al. 2010 Toxicol Sci 116:536 + Fontana et al. 2010 Hepatology.
    """
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return None
    logp = Descriptors.MolLogP(mol)
    mw = Descriptors.MolWt(mol)
    if logp > 4.0 and mw > 400:
        prob = min(0.90, 0.55 + 0.05 * (logp - 4.0))
    elif logp > 2.5 or mw > 350:
        prob = min(0.70, 0.30 + 0.04 * max(0.0, logp))
    else:
        prob = max(0.05, 0.08 + 0.02 * max(0.0, logp))
    return round(prob, 6)


def predict_ames(smiles: str) -> Optional[float]:
    """
    Ames mutagenicity probability from structural alert ensemble.

    Score = 1 − ∏(1 − w_i × m_i) where w_i is Kazius reliability weight and
    m_i = 1 if alert i matches.
    Reference: Kazius et al. 2005 J Med Chem 48:312
    """
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return None
    no_alert_prob = 1.0
    for _name, pattern, weight in _AMES_PATTERNS:
        if mol.HasSubstructMatch(pattern):
            no_alert_prob *= (1.0 - weight)
    return round(1.0 - no_alert_prob, 6)


def predict_clintox(smiles: str) -> Optional[float]:
    """
    ClinTox (failed clinical trial due to toxicity) probability.

    Heuristic: Lipinski violations + logP-based base risk + Ames alert boost.
    """
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return None
    logp = Descriptors.MolLogP(mol)
    mw = Descriptors.MolWt(mol)
    hba = rdMolDescriptors.CalcNumHBA(mol)
    hbd = rdMolDescriptors.CalcNumHBD(mol)

    violations = sum([mw > 500, logp > 5, hba > 10, hbd > 5])
    base = min(0.85, 0.15 + 0.06 * max(0.0, logp))
    boosted = base + 0.08 * violations

    ames_score = predict_ames(smiles) or 0.0
    return round(min(0.95, boosted + 0.30 * ames_score), 6)


def predict_tox21_sr_mmp(smiles: str) -> Optional[float]:
    """
    Tox21 SR-MMP (mitochondrial membrane potential disruption) probability.

    Model: lipophilicity + MW heuristic.
    Reference: Naven et al. 2013 Chem Res Toxicol 26:634
    """
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return None
    logp = Descriptors.MolLogP(mol)
    mw = Descriptors.MolWt(mol)
    base = min(0.85, 0.10 + 0.07 * max(0.0, logp))
    if mw > 400 and logp > 3.5:
        base = min(0.90, base + 0.15)
    return round(base, 6)


# ---------------------------------------------------------------------------
# Dataset loaders
# ---------------------------------------------------------------------------

@dataclass
class LabeledSet:
    name: str
    smiles: list[str]
    labels: list[int]      # 1 = positive (toxic/blocker), 0 = negative
    pos_description: str


def _download(url: str, dest: Path) -> None:
    """Download url to dest, raising RuntimeError on failure."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    log.info("Downloading %s → %s", url, dest)
    try:
        urllib.request.urlretrieve(url, dest)
    except Exception as e:
        raise RuntimeError(f"Failed to download {url}: {e}") from e


def _open_csv_large(path: Path):
    """Open a CSV file with raised field-size limit (handles ChEMBL large rows)."""
    csv.field_size_limit(10_000_000)
    return open(path, newline="")


def load_herg_chembl(data_dir: Path) -> LabeledSet:
    """
    hERG channel blocker dataset from ChEMBL.
    Positive = IC50 ≤ 10 µM (Cai et al. 2019 J Chem Inf Model 59:1 benchmark threshold).

    ChEMBL REST API: target CHEMBL240 (hERG), assay type B, standard IC50.
    """
    dest = data_dir / "herg_chembl.csv"
    if not dest.exists():
        url = (
            "https://www.ebi.ac.uk/chembl/api/data/activity.csv?"
            "target_chembl_id=CHEMBL240&standard_type=IC50"
            "&assay_type=B&limit=2000&offset=0"
        )
        _download(url, dest)

    smiles_list, labels = [], []
    with _open_csv_large(dest) as f:
        reader = csv.DictReader(f)
        for row in reader:
            smi = row.get("canonical_smiles", "").strip()
            val_str = row.get("standard_value", "").strip()
            unit = (row.get("standard_units") or "").lower().strip()
            if not smi or not val_str:
                continue
            try:
                val = float(val_str)
            except ValueError:
                continue
            # Normalise to µM
            if unit in ("nm", "nanomolar"):
                val_um = val / 1000.0
            elif unit in ("um", "micromolar"):
                val_um = val
            else:
                continue
            # Require canonical parse (skip malformed SMILES from ChEMBL)
            if Chem.MolFromSmiles(smi) is None:
                continue
            smiles_list.append(smi)
            labels.append(1 if val_um <= 10.0 else 0)

    if not smiles_list:
        raise RuntimeError(
            f"No valid hERG records parsed from {dest}. "
            "Check the CSV format matches ChEMBL REST API output."
        )
    return LabeledSet("herg", smiles_list, labels, "hERG blocker (IC50 ≤ 10 µM)")


def load_dilirank(data_dir: Path) -> LabeledSet:
    """
    DILIrank — Chen et al. 2016 Hepatology 63:388.
    vMost-DILI-Concern (label=1) vs vNo-DILI-Concern (label=0).
    """
    dest = data_dir / "dilirank.csv"
    if not dest.exists():
        url = (
            "https://raw.githubusercontent.com/DILIrank/DILIrank/main/"
            "data/DILIrank_v2.csv"
        )
        _download(url, dest)

    smiles_list, labels = [], []
    with open(dest, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            smi = (row.get("Canonical_Smiles") or row.get("smiles") or "").strip()
            concern = (row.get("DILIrank") or row.get("DILI_concern") or "").strip().lower()
            if not smi:
                continue
            if Chem.MolFromSmiles(smi) is None:
                continue
            if "most" in concern or concern in ("v-most-dili-concern", "1"):
                smiles_list.append(smi)
                labels.append(1)
            elif "no" in concern or concern in ("v-no-dili-concern", "0"):
                smiles_list.append(smi)
                labels.append(0)

    if not smiles_list:
        raise RuntimeError(
            f"No valid DILIrank records parsed from {dest}. "
            "Expected columns: Canonical_Smiles, DILIrank"
        )
    return LabeledSet("dilirank", smiles_list, labels, "Most DILI concern (DILIrank)")


def load_ames(data_dir: Path) -> LabeledSet:
    """
    Hansen et al. 2009 Chem Res Toxicol 22:2088 Ames mutagenicity dataset.
    6,512 compounds, binary labels (1 = mutagenic).
    """
    dest = data_dir / "ames_hansen2009.csv"
    if not dest.exists():
        # Hansen 2009 dataset is hosted in several public repos;
        # chemprop benchmarks use this canonical version
        url = (
            "https://raw.githubusercontent.com/chemprop/chemprop/"
            "master/tests/data/tox/ames.csv"
        )
        _download(url, dest)

    smiles_list, labels = [], []
    with open(dest, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            smi = (row.get("smiles") or row.get("SMILES") or "").strip()
            lbl = (row.get("activity") or row.get("label") or row.get("mutagenic") or "").strip()
            if not smi or lbl not in ("0", "1"):
                continue
            if Chem.MolFromSmiles(smi) is None:
                continue
            smiles_list.append(smi)
            labels.append(int(lbl))

    if not smiles_list:
        raise RuntimeError(
            f"No valid Ames records parsed from {dest}. "
            "Expected columns: smiles, activity (0/1)"
        )
    return LabeledSet("ames", smiles_list, labels, "Ames mutagenic")


def load_clintox(data_dir: Path) -> LabeledSet:
    """
    MoleculeNet ClinTox (Wu et al. 2018 Mol Syst Biol 14:e6027).
    CT_TOX = 1: failed clinical trial due to toxicity.
    """
    dest = data_dir / "clintox.csv"
    if not dest.exists():
        url = (
            "https://raw.githubusercontent.com/deepchem/deepchem/"
            "master/datasets/clintox.csv"
        )
        _download(url, dest)

    smiles_list, labels = [], []
    with open(dest, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            smi = row.get("smiles", "").strip()
            lbl = row.get("CT_TOX", "").strip()
            if not smi or lbl not in ("0", "1"):
                continue
            if Chem.MolFromSmiles(smi) is None:
                continue
            smiles_list.append(smi)
            labels.append(int(lbl))

    if not smiles_list:
        raise RuntimeError(
            f"No valid ClinTox records parsed from {dest}. "
            "Expected columns: smiles, CT_TOX"
        )
    return LabeledSet("clintox", smiles_list, labels,
                      "Failed clinical trial due to toxicity")


def load_tox21(data_dir: Path, endpoint: str = "SR-MMP") -> LabeledSet:
    """
    MoleculeNet Tox21 (Wu et al. 2018). Column: SR-MMP.
    Label 1 = active (mitochondrial membrane potential disruption).
    """
    dest = data_dir / "tox21.csv"
    if not dest.exists():
        url = (
            "https://raw.githubusercontent.com/deepchem/deepchem/"
            "master/datasets/tox21.csv"
        )
        _download(url, dest)

    smiles_list, labels = [], []
    with open(dest, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            smi = row.get("smiles", "").strip()
            lbl = row.get(endpoint, "").strip()
            if not smi or lbl not in ("0", "1"):
                continue
            if Chem.MolFromSmiles(smi) is None:
                continue
            smiles_list.append(smi)
            labels.append(int(lbl))

    if not smiles_list:
        raise RuntimeError(
            f"No valid Tox21 records for endpoint '{endpoint}' in {dest}."
        )
    return LabeledSet(f"tox21_{endpoint.lower().replace('-', '_')}",
                      smiles_list, labels, f"Tox21 active ({endpoint})")


def load_sider_hepatobiliary(data_dir: Path) -> LabeledSet:
    """
    MoleculeNet SIDER — Hepatobiliary disorders (Kuhn et al. 2016 + Wu et al. 2018).
    Label 1 = drug causes hepatobiliary disorders.
    """
    dest = data_dir / "sider.csv"
    if not dest.exists():
        url = (
            "https://raw.githubusercontent.com/deepchem/deepchem/"
            "master/datasets/sider.csv"
        )
        _download(url, dest)

    smiles_list, labels = [], []
    with open(dest, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            smi = row.get("smiles", "").strip()
            lbl_str = row.get("Hepatobiliary disorders", "").strip()
            if not smi or lbl_str not in ("0", "1"):
                continue
            if Chem.MolFromSmiles(smi) is None:
                continue
            smiles_list.append(smi)
            labels.append(int(lbl_str))

    if not smiles_list:
        raise RuntimeError(
            f"No valid SIDER records in {dest}. "
            "Expected columns: smiles, 'Hepatobiliary disorders'"
        )
    return LabeledSet("sider_hepatobiliary", smiles_list, labels,
                      "Hepatobiliary disorders (SIDER)")


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------

def _auroc(y_true: list[int], y_score: list[float]) -> float:
    """AUROC via Mann-Whitney U statistic. O(n log n)."""
    n_pos = sum(y_true)
    n_neg = len(y_true) - n_pos
    if n_pos == 0 or n_neg == 0:
        return float("nan")
    paired = sorted(zip(y_score, y_true), key=lambda x: -x[0])
    rank_sum = 0
    for rank, (_, label) in enumerate(paired, 1):
        if label == 1:
            rank_sum += rank
    u_stat = rank_sum - n_pos * (n_pos + 1) / 2
    return round(u_stat / (n_pos * n_neg), 6)


def bootstrap_auroc(
    y_true: list[int],
    y_score: list[float],
    n_bootstrap: int = 1000,
    ci: float = 0.90,
    seed: int = 42,
) -> tuple[float, float, float]:
    """Return (auroc, ci_lower, ci_upper). Percentile bootstrap (Efron 1987)."""
    rng = random.Random(seed)
    n = len(y_true)
    boot_aurocs = []
    for _ in range(n_bootstrap):
        idx = [rng.randrange(n) for _ in range(n)]
        yt = [y_true[i] for i in idx]
        ys = [y_score[i] for i in idx]
        if 0 < sum(yt) < len(yt):
            boot_aurocs.append(_auroc(yt, ys))

    if not boot_aurocs:
        return float("nan"), float("nan"), float("nan")

    boot_aurocs.sort()
    alpha = (1 - ci) / 2
    lo = boot_aurocs[max(0, int(alpha * len(boot_aurocs)))]
    hi = boot_aurocs[min(len(boot_aurocs) - 1, int((1 - alpha) * len(boot_aurocs)))]
    return _auroc(y_true, y_score), round(lo, 4), round(hi, 4)


def _roc_curve(y_true: list[int], y_score: list[float]) -> tuple[list[float], list[float]]:
    """Return (fpr_list, tpr_list)."""
    n_pos = sum(y_true)
    n_neg = len(y_true) - n_pos
    if n_pos == 0 or n_neg == 0:
        return [0.0, 1.0], [0.0, 1.0]
    paired = sorted(zip(y_score, y_true), key=lambda x: -x[0])
    fpr_list, tpr_list = [0.0], [0.0]
    tp = fp = 0
    for _, label in paired:
        if label == 1:
            tp += 1
        else:
            fp += 1
        fpr_list.append(round(fp / n_neg, 5))
        tpr_list.append(round(tp / n_pos, 5))
    return fpr_list, tpr_list


# ---------------------------------------------------------------------------
# Benchmark runner
# ---------------------------------------------------------------------------

# Map dataset name prefix → prediction function
_PREDICT_FN = {
    "herg":               predict_herg,
    "dilirank":           predict_dili,
    "dili":               predict_dili,
    "ames":               predict_ames,
    "clintox":            predict_clintox,
    "tox21_sr":           predict_tox21_sr_mmp,
    "sider_hepatobiliary": predict_dili,
}

# Published AUROC targets
_PUBLISHED_TARGETS = {
    "herg":               ("≥ 0.84", "Cai et al. 2019 J Chem Inf Model"),
    "dili":               ("≥ 0.73", "Chen et al. 2016 Hepatology"),
    "dilirank":           ("≥ 0.73", "Chen et al. 2016 Hepatology"),
    "ames":               ("≥ 0.82", "Kazius et al. 2005 J Med Chem"),
    "clintox":            ("≥ 0.80", "Wu et al. 2018 Mol Syst Biol"),
    "tox21":              ("≥ 0.83", "Wu et al. 2018 Mol Syst Biol"),
    "sider":              ("≥ 0.65", "Wu et al. 2018 Mol Syst Biol"),
}


def _resolve_predict_fn(dataset_name: str):
    for prefix, fn in _PREDICT_FN.items():
        if dataset_name.startswith(prefix):
            return fn
    raise ValueError(f"No prediction function registered for dataset '{dataset_name}'")


def _meets_target(auroc: float, target_str: str) -> Optional[bool]:
    if target_str == "n/a" or auroc != auroc:
        return None
    import re
    m = re.match(r"[≥≤><=]+\s*([\d.]+)", target_str)
    if not m:
        return None
    threshold = float(m.group(1))
    if "≥" in target_str or ">=" in target_str:
        return auroc >= threshold
    elif "≤" in target_str or "<=" in target_str:
        return auroc <= threshold
    return None


def run_benchmark(
    dataset: LabeledSet,
    n_bootstrap: int = 1000,
    seed: int = 42,
) -> dict:
    """Run predictions on one dataset and compute AUROC + CI."""
    predict_fn = _resolve_predict_fn(dataset.name)

    scores, valid_labels, per_row, n_invalid_smiles = [], [], [], 0
    for smi, lbl in zip(dataset.smiles, dataset.labels):
        score = predict_fn(smi)
        if score is None:
            n_invalid_smiles += 1
            per_row.append({"smiles": smi, "true_label": lbl,
                            "pred_score": None, "dataset": dataset.name})
            continue
        scores.append(score)
        valid_labels.append(lbl)
        per_row.append({"smiles": smi, "true_label": lbl,
                        "pred_score": round(score, 6), "dataset": dataset.name})

    if not scores:
        raise RuntimeError(
            f"No valid predictions produced for dataset '{dataset.name}'. "
            f"{n_invalid_smiles} SMILES failed RDKit parse."
        )
    if n_invalid_smiles:
        log.warning("%s: %d SMILES failed RDKit parse (excluded from metrics)",
                    dataset.name, n_invalid_smiles)

    auroc, lo, hi = bootstrap_auroc(valid_labels, scores, n_bootstrap, seed=seed)
    fpr, tpr = _roc_curve(valid_labels, scores)

    n_pos = sum(valid_labels)
    n_neg = len(valid_labels) - n_pos
    target_key = dataset.name.split("_")[0]
    target_str, target_ref = _PUBLISHED_TARGETS.get(target_key, ("n/a", "n/a"))

    result = {
        "dataset": dataset.name,
        "positive_description": dataset.pos_description,
        "n_total": len(valid_labels),
        "n_positive": n_pos,
        "n_negative": n_neg,
        "n_invalid_smiles": n_invalid_smiles,
        "auroc": auroc,
        "ci_90_lower": lo,
        "ci_90_upper": hi,
        "n_bootstrap": n_bootstrap,
        "published_target": target_str,
        "published_reference": target_ref,
        "meets_target": _meets_target(auroc, target_str),
        "_roc_fpr": fpr,
        "_roc_tpr": tpr,
        "_per_compound": per_row,
    }

    log.info(
        "%-30s  AUROC=%.3f  90%%CI=[%.3f, %.3f]  n=%d  target=%s  %s",
        dataset.name, auroc, lo, hi, len(valid_labels), target_str,
        "✓" if result["meets_target"] else ("✗" if result["meets_target"] is False else "n/a"),
    )
    return result


# ---------------------------------------------------------------------------
# Dataset registry
# ---------------------------------------------------------------------------

_DATASET_LOADERS = {
    "herg":    load_herg_chembl,
    "dili":    load_dilirank,
    "ames":    load_ames,
    "clintox": load_clintox,
    "tox21":   load_tox21,
    "sider":   load_sider_hepatobiliary,
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description=(
            "BioMate ADMET benchmark — run inside biomni-tools Docker container.\n"
            "Requires RDKit and network access to download datasets."
        )
    )
    parser.add_argument(
        "--datasets",
        default="herg,dili,ames,clintox,tox21",
        help="Comma-separated list of datasets: herg,dili,ames,clintox,tox21,sider",
    )
    parser.add_argument(
        "--output",
        default="results/admet_benchmark",
        help="Output directory for metrics.json, per_compound.csv, roc_data.json",
    )
    parser.add_argument(
        "--data-dir",
        default="data/admet",
        help="Directory for downloaded dataset CSV files",
    )
    parser.add_argument(
        "--n-bootstrap",
        type=int,
        default=1000,
        help="Bootstrap resamples for 90%% CI (default 1000)",
    )
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )

    data_dir = Path(args.data_dir)
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    data_dir.mkdir(parents=True, exist_ok=True)

    requested = [d.strip().lower() for d in args.datasets.split(",")]
    unknown = [d for d in requested if d not in _DATASET_LOADERS]
    if unknown:
        parser.error(f"Unknown datasets: {unknown}. Available: {list(_DATASET_LOADERS)}")

    all_results = []
    all_per_compound = []
    roc_data = {}

    for ds_name in requested:
        log.info("Loading dataset: %s", ds_name)
        loader = _DATASET_LOADERS[ds_name]
        dataset = loader(data_dir)  # raises on failure — no silent fallbacks

        log.info(
            "Loaded %d compounds (%d positive, %d negative) from %s",
            len(dataset.smiles), sum(dataset.labels),
            len(dataset.labels) - sum(dataset.labels),
            dataset.name,
        )

        result = run_benchmark(dataset, n_bootstrap=args.n_bootstrap, seed=args.seed)

        roc_data[dataset.name] = {
            "fpr": result.pop("_roc_fpr"),
            "tpr": result.pop("_roc_tpr"),
            "auroc": result["auroc"],
            "ci_90": [result["ci_90_lower"], result["ci_90_upper"]],
        }
        all_per_compound.extend(result.pop("_per_compound"))
        all_results.append(result)

    # Write metrics.json
    metrics_path = output_dir / "metrics.json"
    with open(metrics_path, "w") as f:
        json.dump(all_results, f, indent=2)
    log.info("Wrote %s", metrics_path)

    # Write per_compound.csv
    pc_path = output_dir / "per_compound.csv"
    if all_per_compound:
        with open(pc_path, "w", newline="") as f:
            writer = csv.DictWriter(
                f, fieldnames=["dataset", "smiles", "true_label", "pred_score"],
                extrasaction="ignore",
            )
            writer.writeheader()
            writer.writerows(all_per_compound)
        log.info("Wrote %s (%d rows)", pc_path, len(all_per_compound))

    # Write roc_data.json
    roc_path = output_dir / "roc_data.json"
    with open(roc_path, "w") as f:
        json.dump(roc_data, f, indent=2)
    log.info("Wrote %s", roc_path)

    # Summary table
    print("\n" + "=" * 78)
    print("BioMate ADMET Benchmark Summary")
    print("=" * 78)
    print(f"{'Dataset':<32} {'AUROC':>6}  {'90% CI':>18}  {'Target':>8}  {'Pass?':>5}")
    print("-" * 78)
    for r in all_results:
        auroc = r["auroc"]
        auroc_str = f"{auroc:.3f}" if auroc == auroc else "  n/a"
        lo, hi = r["ci_90_lower"], r["ci_90_upper"]
        ci_str = f"[{lo:.3f}, {hi:.3f}]" if lo == lo else "        n/a"
        meets = r.get("meets_target")
        pass_str = "✓" if meets is True else ("✗" if meets is False else "n/a")
        target = r.get("published_target", "n/a")
        print(f"{r['dataset']:<32} {auroc_str:>6}  {ci_str:>18}  {target:>8}  {pass_str:>5}")
    print("=" * 78)
    n_pass = sum(1 for r in all_results if r.get("meets_target") is True)
    n_total = sum(1 for r in all_results if r.get("meets_target") is not None)
    print(f"\n{n_pass}/{n_total} datasets meet published benchmark targets")
    print(f"Output: {output_dir.resolve()}/\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
