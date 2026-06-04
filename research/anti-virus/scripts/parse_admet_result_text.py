#!/usr/bin/env python3
"""Parse ADMET-AI text blob from predict_admet_properties workflow output."""
from __future__ import annotations

import re
from typing import Any

_COMPOUND_RE = re.compile(r"^Compound:\s*(.+)$", re.MULTILINE)
_METRIC_RE = re.compile(r"^\s{2}(.+?)\s*:\s*([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*$", re.MULTILINE)


def parse_admet_text(text: str) -> dict[str, dict[str, Any]]:
    """Return {smiles: {metric_key: float, ...}} from ADMET-AI text report."""
    out: dict[str, dict[str, Any]] = {}
    if not text.strip():
        return out
    blocks = re.split(r"-{10,}\n", text)
    for block in blocks:
        cm = _COMPOUND_RE.search(block)
        if not cm:
            continue
        smi = cm.group(1).strip()
        metrics: dict[str, Any] = {"smiles": smi}
        for mm in _METRIC_RE.finditer(block):
            key = mm.group(1).strip().lower().replace(" ", "_").replace("%", "pct")
            try:
                metrics[key] = float(mm.group(2))
            except ValueError:
                metrics[key] = mm.group(2)
        out[smi] = metrics
    return out


def triage_fields(metrics: dict[str, Any]) -> dict[str, str]:
    """Map parsed metrics to hERG / DILI / BBB display strings."""
    herg = metrics.get("herg_inhibition")
    dili = metrics.get("dili_probability")
    bbb = metrics.get("bbb_penetration")
    return {
        "hERG": _fmt_prob(herg, high=0.30),
        "DILI": _fmt_prob(dili, high=0.50),
        "BBB": _fmt_prob(bbb, high=None),
    }


def _fmt_prob(val: Any, high: float | None) -> str:
    if val is None:
        return "—"
    try:
        v = float(val)
    except (TypeError, ValueError):
        return str(val)
    s = f"{v:.3f}"
    if high is not None and v >= high:
        return f"{s} ⚠"
    return s
