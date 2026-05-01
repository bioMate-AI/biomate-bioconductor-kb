#!/usr/bin/env python3
"""
IND Gold Standard Concordance Validation

Runs ADMET-AI predictions on all gold standard compounds and computes
predicted vs. measured concordance for hERG, DILI, and Ames endpoints.

This validates BioMate's ADMET engine on a set of well-characterized
reference drugs with known clinical pharmacology outcomes.

Metrics reported per endpoint:
  - Sensitivity (true positive rate)
  - Specificity (true negative rate)
  - Accuracy
  - Matthews Correlation Coefficient (MCC)
  - Balanced Accuracy

Usage:
    python evaluation/runners/validate_ind_gold_standard.py
    python evaluation/runners/validate_ind_gold_standard.py --gold-standard path/to/v2.yaml
    python evaluation/runners/validate_ind_gold_standard.py --output results/
"""
from __future__ import annotations

import argparse
import json
import logging
import warnings
from pathlib import Path
from typing import Optional

import yaml
import numpy as np

log = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

DATASET_DIR = Path(__file__).parent.parent / "datasets" / "ind_gold_standard"
RESULTS_DIR = Path(__file__).parent.parent / "results" / "ind_gold_standard_validation"

# ADMET-AI column mapping for each endpoint
ENDPOINT_CONFIG = {
    "hERG": {
        "admet_col": "hERG",          # probability of IC50 < 10 µM
        "threshold": 0.5,              # binary classification threshold
        "gold_col": "hERG_IC50_uM",    # measured IC50 in µM
        "gold_flag_fn": lambda v: float(v) < 10.0,  # flag if IC50 < 10 µM
        "higher_is_positive": True,    # higher prob = more likely to inhibit
    },
    "DILI": {
        "admet_col": "DILI",
        "threshold": 0.5,
        "gold_col": "DILI_result",     # 1 = concern, 0 = no concern
        "gold_flag_fn": lambda v: int(v) == 1,
        "higher_is_positive": True,
    },
    "Ames": {
        "admet_col": "AMES",
        "threshold": 0.5,
        "gold_col": "Ames_result",     # 1 = positive, 0 = negative
        "gold_flag_fn": lambda v: int(v) == 1,
        "higher_is_positive": True,
    },
}

# Additional ADMET-AI columns to report (no concordance check, just informational)
EXTRA_COLS = [
    "PPBR_AZ", "VDss_Lombardo", "Half_Life_Obach",
    "Clearance_Microsome_AZ", "Clearance_Hepatocyte_AZ",
    "Caco2_Wang", "HIA_Hou", "Bioavailability_Ma",
    "CYP2D6_Substrate_CarbonMangels", "CYP3A4_Substrate_CarbonMangels",
]


def load_gold_standard(yaml_path: Path) -> list[dict]:
    with open(yaml_path, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return data["compounds"]


def run_admet_predictions(smiles_list: list[str]) -> "pd.DataFrame":
    """Run ADMET-AI on a batch of SMILES. Returns DataFrame with all predictions."""
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        from admet_ai import ADMETModel
        model = ADMETModel()
        return model.predict(smiles=smiles_list)


def _mcc(tp: int, tn: int, fp: int, fn: int) -> float:
    """Matthews Correlation Coefficient."""
    denom = ((tp + fp) * (tp + fn) * (tn + fp) * (tn + fn)) ** 0.5
    if denom == 0:
        return 0.0
    return (tp * tn - fp * fn) / denom


def compute_concordance(
    compounds: list[dict],
    predictions: "pd.DataFrame",
    endpoint: str,
    config: dict,
) -> dict:
    """Compute concordance metrics for one endpoint."""
    admet_col = config["admet_col"]
    gold_col = config["gold_col"]
    threshold = config["threshold"]
    gold_flag_fn = config["gold_flag_fn"]

    if admet_col not in predictions.columns:
        log.warning("Column %s not in ADMET-AI output", admet_col)
        return {"endpoint": endpoint, "error": f"{admet_col} not in predictions"}

    tp = tn = fp = fn = 0
    details = []

    for i, cpd in enumerate(compounds):
        # Get gold standard label
        gold_val = cpd.get("assays", {}).get(gold_col)
        if gold_val is None:
            continue
        try:
            gold_positive = gold_flag_fn(gold_val)
        except (ValueError, TypeError):
            continue

        # Get ADMET-AI prediction
        if i >= len(predictions):
            continue
        pred_prob = float(predictions.iloc[i][admet_col])
        pred_positive = pred_prob >= threshold

        # Accumulate confusion matrix
        if gold_positive and pred_positive:
            tp += 1; outcome = "TP"
        elif not gold_positive and not pred_positive:
            tn += 1; outcome = "TN"
        elif not gold_positive and pred_positive:
            fp += 1; outcome = "FP"
        else:
            fn += 1; outcome = "FN"

        details.append({
            "compound": cpd["id"],
            "gold_value": gold_val,
            "gold_positive": gold_positive,
            "pred_prob": round(pred_prob, 4),
            "pred_positive": pred_positive,
            "outcome": outcome,
            "expected_flags": cpd.get("expected", {}).get("safety_flags", []),
            "market_status": cpd.get("market_status", "approved"),
        })

    total = tp + tn + fp + fn
    sensitivity = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    specificity = tn / (tn + fp) if (tn + fp) > 0 else 0.0
    accuracy = (tp + tn) / total if total > 0 else 0.0
    balanced_acc = (sensitivity + specificity) / 2
    mcc = _mcc(tp, tn, fp, fn)
    ppv = tp / (tp + fp) if (tp + fp) > 0 else 0.0  # precision
    npv = tn / (tn + fn) if (tn + fn) > 0 else 0.0

    return {
        "endpoint": endpoint,
        "admet_col": admet_col,
        "threshold": threshold,
        "n_evaluated": total,
        "tp": tp, "tn": tn, "fp": fp, "fn": fn,
        "sensitivity": round(sensitivity, 4),
        "specificity": round(specificity, 4),
        "accuracy": round(accuracy, 4),
        "balanced_accuracy": round(balanced_acc, 4),
        "mcc": round(mcc, 4),
        "ppv": round(ppv, 4),
        "npv": round(npv, 4),
        "details": details,
    }


def format_concordance_table(results: list[dict]) -> str:
    """Format concordance results as a Markdown table for the manuscript."""
    lines = [
        "| Endpoint | n | TP | TN | FP | FN | Sens | Spec | Acc | Bal.Acc | MCC |",
        "|----------|---|-----|-----|-----|-----|------|------|-----|---------|-----|",
    ]
    for r in results:
        if "error" in r:
            lines.append(f"| {r['endpoint']} | — | ERROR | | | | | | | | |")
            continue
        lines.append(
            f"| {r['endpoint']} | {r['n_evaluated']} "
            f"| {r['tp']} | {r['tn']} | {r['fp']} | {r['fn']} "
            f"| {r['sensitivity']:.3f} | {r['specificity']:.3f} "
            f"| {r['accuracy']:.3f} | {r['balanced_accuracy']:.3f} | {r['mcc']:.3f} |"
        )
    return "\n".join(lines)


def format_compound_table(results: list[dict]) -> str:
    """Compound-level detail table for supplementary material."""
    # Collect all compound IDs
    all_cpds: dict[str, dict] = {}
    for r in results:
        for d in r.get("details", []):
            cid = d["compound"]
            if cid not in all_cpds:
                all_cpds[cid] = {"id": cid, "market": d["market_status"]}
            ep = r["endpoint"]
            all_cpds[cid][f"{ep}_gold"] = "+" if d["gold_positive"] else "−"
            all_cpds[cid][f"{ep}_pred"] = f"{d['pred_prob']:.2f}"
            all_cpds[cid][f"{ep}_outcome"] = d["outcome"]

    lines = [
        "| Compound | Status | hERG gold | hERG pred | hERG | DILI gold | DILI pred | DILI | Ames gold | Ames pred | Ames |",
        "|----------|--------|-----------|-----------|------|-----------|-----------|------|-----------|-----------|------|",
    ]
    for cid, row in sorted(all_cpds.items()):
        ms = row.get("market", "approved")
        lines.append(
            f"| {cid} | {ms} "
            f"| {row.get('hERG_gold','?')} | {row.get('hERG_pred','?')} | {row.get('hERG_outcome','?')} "
            f"| {row.get('DILI_gold','?')} | {row.get('DILI_pred','?')} | {row.get('DILI_outcome','?')} "
            f"| {row.get('Ames_gold','?')} | {row.get('Ames_pred','?')} | {row.get('Ames_outcome','?')} |"
        )
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--gold-standard",
        default=str(DATASET_DIR / "reference_compounds_v2.yaml"),
        help="Path to gold standard YAML",
    )
    parser.add_argument(
        "--output",
        default=str(RESULTS_DIR),
        help="Output directory for results",
    )
    args = parser.parse_args()

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    # ── Load gold standard ─────────────────────────────────────────────────
    compounds = load_gold_standard(Path(args.gold_standard))
    log.info("Loaded %d compounds from gold standard", len(compounds))

    smiles_list = [c["smiles"] for c in compounds]
    ids = [c["id"] for c in compounds]

    # ── Run ADMET-AI predictions (batch) ───────────────────────────────────
    log.info("Running ADMET-AI on %d compounds ...", len(smiles_list))
    predictions = run_admet_predictions(smiles_list)
    log.info("ADMET-AI predictions complete: %d rows × %d cols", *predictions.shape)

    # Save raw predictions
    pred_path = output_dir / "admet_predictions_gold_standard.csv"
    predictions.insert(0, "compound_id", ids)
    predictions.to_csv(pred_path, index=False)
    log.info("Raw predictions saved to %s", pred_path)

    # ── Concordance per endpoint ───────────────────────────────────────────
    all_results = []
    for endpoint, config in ENDPOINT_CONFIG.items():
        result = compute_concordance(compounds, predictions, endpoint, config)
        all_results.append(result)
        log.info(
            "[%s] n=%d | Sens=%.3f | Spec=%.3f | Acc=%.3f | MCC=%.3f",
            endpoint,
            result.get("n_evaluated", 0),
            result.get("sensitivity", 0),
            result.get("specificity", 0),
            result.get("accuracy", 0),
            result.get("mcc", 0),
        )
        # Flag errors (FP / FN)
        for d in result.get("details", []):
            if d["outcome"] in ("FP", "FN"):
                log.warning(
                    "  %s %s: gold=%s pred=%.3f → %s",
                    endpoint, d["compound"],
                    "+" if d["gold_positive"] else "−",
                    d["pred_prob"], d["outcome"],
                )

    # ── Save JSON results ──────────────────────────────────────────────────
    results_path = output_dir / "concordance_results.json"
    # Remove detail lists for summary JSON
    summary = [{k: v for k, v in r.items() if k != "details"} for r in all_results]
    results_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    # ── Print concordance table ────────────────────────────────────────────
    print("\n" + "=" * 70)
    print("IND GOLD STANDARD CONCORDANCE — ADMET-AI vs MEASURED")
    print("=" * 70)
    print(format_concordance_table(all_results))
    print()
    print("Compound-level detail:")
    print(format_compound_table(all_results))
    print()
    print(f"Results saved to: {output_dir}")

    # ── Manuscript-ready summary ──────────────────────────────────────────
    md_path = output_dir / "concordance_manuscript_table.md"
    md_content = [
        "## Table 4. BioMate ADMET-AI Concordance with Known Reference Compound Safety Profiles",
        "",
        "All values are from ADMET-AI Chemprop-RDKit predictions vs. published measured data",
        f"(n={len(compounds)} reference compounds; sources: Redfern 2003, DILIrank, Hansen 2009, ChEMBL).",
        "",
        "### 4a. Endpoint-level summary",
        "",
        format_concordance_table(all_results),
        "",
        "*Sensitivity = TP/(TP+FN); Specificity = TN/(TN+FP); MCC = Matthews Correlation Coefficient.*",
        "*Classification threshold: p ≥ 0.50 for all endpoints.*",
        "",
        "### 4b. Compound-level predictions",
        "",
        format_compound_table(all_results),
        "",
        "*gold: +/− = measured positive/negative; pred: ADMET-AI probability; TP/TN/FP/FN.*",
    ]
    md_path.write_text("\n".join(md_content), encoding="utf-8")
    log.info("Manuscript table written to %s", md_path)

    return all_results


if __name__ == "__main__":
    main()
