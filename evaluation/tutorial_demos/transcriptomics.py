"""Validator for the transcriptomics tutorial demo (GSE49712 / SEQC ERCC)."""
from __future__ import annotations

import csv
import math
import os
from typing import Any

import boto3

ERCC_TRUTH_PATH = os.environ.get(
    "ERCC_TRUTH_PATH",
    "s3://biomate-public-datasets/tutorial-gold/transcriptomics/GSE49712/ercc_truth.tsv",
)
THRESHOLD_RECOVERY = 0.90
THRESHOLD_AUC = 0.95


def _load_ercc_truth() -> dict[str, float]:
    """Returns ERCC id -> expected log2(Mix B / Mix A)."""
    bucket, _, key = ERCC_TRUTH_PATH.replace("s3://", "").partition("/")
    s3 = boto3.client("s3")
    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode()
    out: dict[str, float] = {}
    for row in csv.DictReader(body.splitlines(), delimiter="\t"):
        ratio = float(row["expected_ratio"])
        out[row["ercc_id"]] = math.log2(ratio)
    return out


def _load_de_results(de_uri: str) -> dict[str, dict[str, float]]:
    bucket, _, key = de_uri.replace("s3://", "").partition("/")
    s3 = boto3.client("s3")
    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read().decode()
    out: dict[str, dict[str, float]] = {}
    for row in csv.DictReader(body.splitlines(), delimiter="\t"):
        gid = row.get("gene_id") or row.get("ensembl_id") or row.get("id")
        if not gid or not gid.startswith("ERCC-"):
            continue
        try:
            out[gid] = {
                "log2fc": float(row["log2FoldChange"]),
                "padj": float(row.get("padj") or row.get("padj_BH") or "nan"),
            }
        except (KeyError, ValueError):
            continue
    return out


def _auc(scores: list[tuple[float, int]]) -> float:
    """Mann-Whitney style AUC; scores = [(prediction, label∈{0,1}), ...]."""
    pos = [s for s, y in scores if y == 1]
    neg = [s for s, y in scores if y == 0]
    if not pos or not neg:
        return float("nan")
    wins = sum(1 for p in pos for n in neg if p > n) + 0.5 * sum(
        1 for p in pos for n in neg if p == n
    )
    return wins / (len(pos) * len(neg))


def validate(run_doc: dict[str, Any]) -> dict[str, Any]:
    de_uri = run_doc.get("outputs", {}).get("de_results")
    if not de_uri:
        return {"pass": False, "error": "no de_results in run outputs"}

    truth = _load_ercc_truth()
    obs = _load_de_results(de_uri)

    matched = [(g, truth[g], obs[g]) for g in truth if g in obs]
    if not matched:
        return {"pass": False, "error": "no ERCC overlap between truth and de_results"}

    # Recovery: fraction with matching sign on non-zero true log2FC.
    nonzero = [m for m in matched if abs(m[1]) > 1e-6]
    recovered = sum(1 for _g, t, o in nonzero if (t > 0) == (o["log2fc"] > 0))
    recovery = recovered / len(nonzero) if nonzero else 0.0

    # AUC of -padj as DE score vs ERCC-is-DE label (|true|>0).
    auc = _auc([(-(m[2]["padj"]) if not math.isnan(m[2]["padj"]) else 0.0,
                 1 if abs(m[1]) > 1e-6 else 0) for m in matched])

    ok = recovery >= THRESHOLD_RECOVERY and (math.isnan(auc) or auc >= THRESHOLD_AUC)
    return {
        "pass": bool(ok),
        "metric_name": "ercc_truth_recovery",
        "metric_value": round(recovery, 4),
        "threshold": THRESHOLD_RECOVERY,
        "secondary": {"name": "ercc_auc_roc", "value": round(auc, 4),
                      "threshold": THRESHOLD_AUC},
        "n_ercc_matched": len(matched),
    }
