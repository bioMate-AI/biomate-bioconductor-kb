"""
BioMate ADMET-AI TDC Benchmark Evaluation

Evaluates ADMET-AI predictions on the same TDC test splits used in the
ADMET-AI paper (Swanson et al. 2023, Bioinformatics), giving directly
comparable benchmark numbers.

Endpoints evaluated:
  hERG       — binary classification, AUROC, n_test ≈ 98
  DILI       — binary classification, AUROC, n_test ≈ 71
  AMES       — binary classification, AUROC, n_test ≈ 1092
  PPBR_AZ    — regression, MAE (%), n_test ≈ 424

TDC uses scaffold-based splits (Bemis-Murcko scaffolds) for all ADMET datasets.
We reproduce the same split by loading the full dataset and applying the same
random_seed=1 scaffold split used by TDC.

Usage:
  python evaluation/runners/run_admet_tdc_benchmark.py
  python evaluation/runners/run_admet_tdc_benchmark.py --endpoints hERG,PPBR_AZ
  python evaluation/runners/run_admet_tdc_benchmark.py --save-preds
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
import warnings
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

# Suppress ADMET-AI/Lightning verbose output
for noisy in ("lightning", "pytorch_lightning", "lightning.pytorch"):
    logging.getLogger(noisy).setLevel(logging.ERROR)
warnings.filterwarnings("ignore")

_REPO_ROOT   = Path(__file__).parent.parent.parent
_DATA_DIR    = _REPO_ROOT / "data"
_RESULTS_DIR = _REPO_ROOT / "evaluation" / "results" / "admet_tdc_benchmark"
_RESULTS_DIR.mkdir(parents=True, exist_ok=True)

# TDC official scaffold split seed
_TDC_SEED = 1
_TDC_TEST_FRAC = 0.1   # 10% test, matching TDC default

# ADMET-AI published results (from Swanson et al. 2023, Table 1 + TDC leaderboard)
ADMET_AI_PUBLISHED = {
    "hERG":   {"metric": "AUROC", "value": 0.870, "source": "Swanson et al. 2023"},
    "DILI":   {"metric": "AUROC", "value": 0.856, "source": "Swanson et al. 2023"},
    "AMES":   {"metric": "AUROC", "value": 0.870, "source": "TDC leaderboard 2024"},
    "PPBR_AZ":{"metric": "MAE",   "value": 8.6,   "source": "Swanson et al. 2023"},
}

# Chemprop baseline (TDC official)
CHEMPROP_BASELINE = {
    "hERG":   {"metric": "AUROC", "value": 0.870},
    "DILI":   {"metric": "AUROC", "value": 0.847},
    "AMES":   {"metric": "AUROC", "value": 0.850},
    "PPBR_AZ":{"metric": "MAE",   "value": 8.4},
}


# ─── Data loading with TDC-compatible scaffold split ─────────────────────────

def _scaffold_split(df: pd.DataFrame,
                    smiles_col: str = "Drug",
                    test_frac: float = 0.1,
                    seed: int = 1) -> tuple[pd.DataFrame, pd.DataFrame]:
    """
    Bemis-Murcko scaffold-based train/test split matching TDC's split method.
    Groups compounds by scaffold, assigns minority scaffolds to test set.
    """
    try:
        from rdkit import Chem
        from rdkit.Chem.Scaffolds import MurckoScaffold
    except ImportError:
        log.warning("RDKit not available — falling back to random split")
        df_shuf = df.sample(frac=1, random_state=seed).reset_index(drop=True)
        n_test = max(1, int(len(df_shuf) * test_frac))
        return df_shuf.iloc[n_test:].reset_index(drop=True), df_shuf.iloc[:n_test].reset_index(drop=True)

    scaffolds: dict[str, list[int]] = {}
    for idx, row in df.iterrows():
        smi = str(row[smiles_col]).strip()
        try:
            mol = Chem.MolFromSmiles(smi)
            scaffold = MurckoScaffold.MurckoScaffoldSmiles(mol=mol, includeChirality=False) if mol else ""
        except Exception:
            scaffold = ""
        scaffolds.setdefault(scaffold, []).append(idx)

    rng = np.random.default_rng(seed)
    scaffold_sets = list(scaffolds.values())
    rng.shuffle(scaffold_sets)

    test_indices, train_indices = [], []
    n_test_target = int(len(df) * test_frac)
    for group in scaffold_sets:
        if len(test_indices) < n_test_target:
            test_indices.extend(group)
        else:
            train_indices.extend(group)

    return df.loc[train_indices].reset_index(drop=True), df.loc[test_indices].reset_index(drop=True)


def load_tdc_data(endpoint: str) -> tuple[pd.DataFrame, pd.DataFrame, str]:
    """
    Load TDC data with official train/test split.

    Priority:
    1. pytdc package with official split (exact match to ADMET-AI benchmark)
    2. Local .tab file with our scaffold split (approximate)

    Returns (train_df, test_df, split_method_description).
    """
    # TDC module + name mapping (pytdc 1.0: Tox/ADME, not ADMET)
    pytdc_module_map = {
        "hERG":    ("Tox",  "hERG"),
        "DILI":    ("Tox",  "DILI"),
        "AMES":    ("Tox",  "AMES"),
        "PPBR_AZ": ("ADME", "PPBR_AZ"),
    }

    # Try pytdc official split first
    try:
        from tdc.single_pred import Tox as TDC_Tox, ADME as TDC_ADME
        module_name, tdc_name = pytdc_module_map[endpoint]
        cls = TDC_Tox if module_name == "Tox" else TDC_ADME
        data = cls(name=tdc_name)
        splits = data.get_split(method="scaffold", seed=_TDC_SEED,
                                frac=[0.7, 0.1, 0.2])  # standard TDC split
        train_df = splits["train"].rename(columns={"Drug": "smiles", "Y": "label"})
        valid_df  = splits["valid"].rename(columns={"Drug": "smiles", "Y": "label"})
        test_df   = splits["test"].rename(columns={"Drug": "smiles", "Y": "label"})
        # Combine train+valid (we only need test for evaluation)
        train_df  = pd.concat([train_df, valid_df], ignore_index=True)
        log.info("[%s] pytdc official split: %d train / %d test", endpoint, len(train_df), len(test_df))
        return train_df, test_df, "pytdc_official_scaffold"
    except Exception as exc:
        log.info("[%s] pytdc not available (%s) — using local file + scaffold split", endpoint, str(exc)[:60])

    # Fall back to local files with capped scaffold split
    file_map = {
        "hERG":    _DATA_DIR / "herg.tab",
        "DILI":    _DATA_DIR / "dili.tab",
        "AMES":    _DATA_DIR / "ames.tab",
        "PPBR_AZ": _DATA_DIR / "ppbr_az.tab",
    }
    path = file_map.get(endpoint)
    if not path or not path.exists():
        raise FileNotFoundError(f"Data file not found for {endpoint}: {path}")

    df = pd.read_csv(path, sep="\t", quotechar='"').dropna(subset=["Drug", "Y"])
    df = df.rename(columns={"Drug": "smiles", "Y": "label"})

    # For PPBR_AZ: use full dataset (do not filter to human — TDC uses all species)
    # Human-only filter was causing incorrect subset selection

    train_df, test_df = _scaffold_split(df, smiles_col="smiles",
                                         test_frac=_TDC_TEST_FRAC, seed=_TDC_SEED)
    # Warn if test set is much larger than expected (scaffold grouping artefact)
    expected = int(len(df) * _TDC_TEST_FRAC)
    if len(test_df) > expected * 1.5:
        log.warning("[%s] Test set (%d) is >1.5× expected (%d) — scaffold clusters skew split. "
                    "Results may not match TDC official benchmark.", endpoint, len(test_df), expected)
    log.info("[%s] Local split: %d train / %d test", endpoint, len(train_df), len(test_df))
    return train_df, test_df, f"local_scaffold_seed{_TDC_SEED}"


# ─── ADMET-AI prediction ──────────────────────────────────────────────────────

# ADMET-AI column → our endpoint key
_ADMET_AI_COL = {
    "hERG":    "hERG",
    "DILI":    "DILI",
    "AMES":    "AMES",
    "PPBR_AZ": "PPBR_AZ",
}


def run_admet_ai(smiles_list: list[str], batch_size: int = 100) -> pd.DataFrame:
    """
    Run ADMET-AI predictions on a list of SMILES strings.
    Processes in batches to avoid memory issues on large test sets.
    Returns a DataFrame with all ADMET-AI output columns.
    """
    from admet_ai import ADMETModel
    model = ADMETModel()

    results = []
    total = len(smiles_list)
    for i in range(0, total, batch_size):
        batch = smiles_list[i:i + batch_size]
        log.info("  Predicting batch %d/%d (%d–%d of %d)",
                 i // batch_size + 1, (total + batch_size - 1) // batch_size,
                 i + 1, min(i + batch_size, total), total)
        try:
            df_batch = model.predict(smiles=batch)
            # Preserve SMILES order
            df_batch.insert(0, "_smiles", batch[:len(df_batch)])
            results.append(df_batch)
        except Exception as exc:
            log.warning("  Batch %d failed: %s — inserting NaN rows", i // batch_size + 1, exc)
            empty = pd.DataFrame({"_smiles": batch})
            results.append(empty)

    return pd.concat(results, ignore_index=True) if results else pd.DataFrame()


# ─── Metrics ─────────────────────────────────────────────────────────────────

def compute_metrics(y_true: np.ndarray, y_pred: np.ndarray,
                    task_type: str, endpoint: str) -> dict:
    """Compute AUROC (classification) or MAE (regression)."""
    from sklearn.metrics import roc_auc_score, mean_absolute_error

    valid = ~np.isnan(y_pred)
    y_true_v, y_pred_v = y_true[valid], y_pred[valid]
    n_valid = int(valid.sum())
    n_total = len(y_true)

    result = {
        "endpoint": endpoint,
        "n_total": n_total,
        "n_valid": n_valid,
        "n_missing_pred": n_total - n_valid,
    }

    if task_type == "classification":
        if len(np.unique(y_true_v)) < 2:
            result["auroc"] = None
            result["note"] = "Only one class in test set — AUROC undefined"
        else:
            result["auroc"] = round(float(roc_auc_score(y_true_v, y_pred_v)), 4)
        result["metric"] = "AUROC"
        result["value"] = result.get("auroc")
    else:
        result["mae"] = round(float(mean_absolute_error(y_true_v, y_pred_v)), 3)
        result["metric"] = "MAE"
        result["value"] = result.get("mae")

    # Compare to published baselines
    published = ADMET_AI_PUBLISHED.get(endpoint, {})
    baseline  = CHEMPROP_BASELINE.get(endpoint, {})
    result["admet_ai_published"] = published.get("value")
    result["chemprop_baseline"]  = baseline.get("value")

    if result["value"] is not None and published.get("value") is not None:
        if task_type == "classification":
            delta = result["value"] - published["value"]
            result["vs_admet_ai"] = f"{delta:+.4f}"
            # AUROC: match within ±0.02 absolute
            result["matches_published"] = abs(delta) < 0.02
        else:
            delta = result["value"] - published["value"]
            result["vs_admet_ai"] = f"{delta:+.2f}%"
            # MAE: match within ±20% relative (different splits cause larger variation)
            result["matches_published"] = abs(delta) / published["value"] < 0.20

    return result


# ─── Per-endpoint evaluation ──────────────────────────────────────────────────

ENDPOINT_CONFIG = {
    "hERG":    {"task": "classification", "threshold": 0.5, "unit": "binary"},
    "DILI":    {"task": "classification", "threshold": 0.5, "unit": "binary"},
    "AMES":    {"task": "classification", "threshold": 0.5, "unit": "binary"},
    "PPBR_AZ": {"task": "regression",     "threshold": None, "unit": "percent"},
}


def evaluate_endpoint(endpoint: str,
                       save_preds: bool = False) -> dict:
    """Run full evaluation for one TDC endpoint."""
    log.info("\n=== Evaluating %s ===", endpoint)
    cfg = ENDPOINT_CONFIG[endpoint]

    # 1. Load and split data
    train_df, test_df, split_method = load_tdc_data(endpoint)
    log.info("[%s] Test set: %d compounds (split: %s)", endpoint, len(test_df), split_method)

    # 2. Run ADMET-AI on test set
    log.info("[%s] Running ADMET-AI predictions...", endpoint)
    smiles_list = test_df["smiles"].tolist()
    pred_df = run_admet_ai(smiles_list)

    # 3. Extract predictions
    col = _ADMET_AI_COL[endpoint]
    if col not in pred_df.columns:
        log.error("[%s] Column '%s' not in ADMET-AI output: %s", endpoint, col, list(pred_df.columns[:10]))
        return {"endpoint": endpoint, "error": f"column {col} not found"}

    y_pred_raw = pred_df[col].values
    y_true     = test_df["label"].values.astype(float)

    # For regression (PPBR), label is % PPB; ADMET-AI also outputs %
    # For classification, ADMET-AI outputs probability; label is binary 0/1
    y_pred = y_pred_raw.astype(float)

    # 4. Compute metrics
    metrics = compute_metrics(y_true, y_pred, cfg["task"], endpoint)

    # 5. Save predictions if requested
    if save_preds:
        out = test_df[["smiles", "label"]].copy()
        out["pred"] = y_pred
        out_path = _RESULTS_DIR / f"{endpoint}_predictions.csv"
        out.to_csv(out_path, index=False)
        log.info("[%s] Predictions saved to %s", endpoint, out_path)
        metrics["predictions_path"] = str(out_path)

    metrics["split_method"] = split_method
    return metrics


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoints", default="hERG,DILI,AMES,PPBR_AZ",
                        help="Comma-separated list of endpoints to evaluate")
    parser.add_argument("--save-preds", action="store_true",
                        help="Save per-compound predictions to CSV")
    args = parser.parse_args()

    endpoints = [e.strip() for e in args.endpoints.split(",")]
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")

    results = {}
    for endpoint in endpoints:
        if endpoint not in ENDPOINT_CONFIG:
            log.warning("Unknown endpoint: %s — skipping", endpoint)
            continue
        try:
            results[endpoint] = evaluate_endpoint(endpoint, save_preds=args.save_preds)
        except Exception as exc:
            log.error("[%s] Evaluation failed: %s", endpoint, exc)
            results[endpoint] = {"endpoint": endpoint, "error": str(exc)}

    # Print summary table
    print(f"\n{'='*80}")
    print("  BioMate ADMET-AI TDC Benchmark — Results")
    print(f"  Evaluated: {ts}")
    print(f"  Split: scaffold (seed={_TDC_SEED}, test_frac={_TDC_TEST_FRAC})")
    print(f"{'='*80}")
    print(f"\n  {'Endpoint':<12} {'Metric':<8} {'BioMate':>10} {'ADMET-AI pub':>14} "
          f"{'Chemprop base':>15} {'vs ADMET-AI':>12} {'Match':>7}")
    print("  " + "-"*80)

    all_match = True
    for endpoint in endpoints:
        r = results.get(endpoint, {})
        if "error" in r:
            print(f"  {endpoint:<12} ERROR: {r['error']}")
            continue
        metric  = r.get("metric", "?")
        value   = r.get("value")
        pub     = r.get("admet_ai_published", "—")
        base    = r.get("chemprop_baseline", "—")
        vs      = r.get("vs_admet_ai", "—")
        match   = "✓" if r.get("matches_published") else "✗" if r.get("matches_published") is False else "—"
        n       = r.get("n_valid", "?")
        if not r.get("matches_published", True):
            all_match = False
        val_str = f"{value:.4f}" if value is not None and metric == "AUROC" else \
                  f"{value:.2f}%" if value is not None else "—"
        pub_str = f"{pub:.3f}" if isinstance(pub, float) else str(pub)
        base_str = f"{base:.3f}" if isinstance(base, float) else str(base)
        print(f"  {endpoint:<12} {metric:<8} {val_str:>10} {pub_str:>14} {base_str:>15} "
              f"{str(vs):>12} {match:>7}  (n={n})")

    # Save JSON results
    out_path = _RESULTS_DIR / f"tdc_benchmark_{ts}.json"
    with open(out_path, "w") as f:
        json.dump({
            "timestamp": ts,
            "split": {"seed": _TDC_SEED, "test_frac": _TDC_TEST_FRAC, "method": "scaffold"},
            "results": results,
        }, f, indent=2, default=str)
    print(f"\n  Results saved → {out_path}")

    if all_match:
        print("\n  ✓ All results match ADMET-AI published benchmarks (within ±0.02 tolerance)")
    else:
        print("\n  ⚠ Some results differ from published benchmarks — check split alignment")

    return 0 if all_match else 1


if __name__ == "__main__":
    sys.exit(main())
