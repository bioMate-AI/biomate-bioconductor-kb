"""
Harness — produce critic predictions for each labeled item.

This is the 'harness' arm of the RealBio bare-vs-harness frame. For each data item it
builds a :class:`RunContext` from the stored contract, runs the registered critics
through the real :func:`run_critics` hook (so the citation + advisory guardrails
apply), and records what the *target* critic did:

    fired_target            — the target critic produced a PUBLISHED issue
    target_remediation_kind — the RemediationKind it proposed (for harmful-rem scoring)
    published_codes         — every published issue code (cross-fire audit)

A prediction is a small JSON object; predictions are written to a jsonl the scorer
consumes, exactly like a RealBio model's prediction file. The 'bare' arm
(:func:`bare_predictions`) is a deterministic LLM-bare *lower bound*: an LLM with no
run-contract and no KB, asked "is this successful run valid?", abstains ("looks fine").
It never fires — recall 0, false-alarm 0. Replace it with a real LLM's predictions
(same jsonl schema) to get the true bare arm (see README §bare-vs-harness).
"""
from __future__ import annotations

import json
from typing import Any, Dict, List, Optional

from . import _bootstrap  # noqa: F401

from galaxy.ai.critics.hook import run_critics
from galaxy.ai.critics.registry import CriticRegistry
from galaxy.ai.critics.run_context import RunContext

from .stub_critics import build_registry


def _ctx_from_item(item: Dict[str, Any]) -> RunContext:
    c = item["contract"]
    return RunContext.from_contract(
        design=c.get("design"),
        manifest=c.get("manifest"),
        run_id=item["id"],
        inline_artifacts=c.get("inline_artifacts"),
    )


def predict_item(item: Dict[str, Any], registry: CriticRegistry) -> Dict[str, Any]:
    """Run the registered critics on one item and summarise what the target critic did."""
    ctx = _ctx_from_item(item)
    report = run_critics(ctx, registry=registry, require_citation=True)

    target = item["target_critic"]
    fired_target = False
    target_kind: Optional[str] = None
    published_codes: List[str] = []
    published_critics: List[str] = []

    for f in report.findings:
        if not f.published:
            continue
        published_codes.append(f.issue.code)
        published_critics.append(f.issue.critic_id)
        if f.issue.critic_id == target:
            fired_target = True
            if f.remediation is not None:
                target_kind = f.remediation.kind.value

    return {
        "id": item["id"],
        "arm": "harness",
        "fired_target": fired_target,
        "target_remediation_kind": target_kind,
        "published_codes": published_codes,
        "published_critics": published_critics,
        "critics_run": list(report.critics_run),
    }


def harness_predictions(items: List[Dict[str, Any]],
                        registry: Optional[CriticRegistry] = None) -> List[Dict[str, Any]]:
    registry = registry or build_registry()
    return [predict_item(it, registry) for it in items]


def bare_predictions(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Deterministic LLM-bare lower bound: abstain on every item (never fire)."""
    return [{
        "id": it["id"],
        "arm": "bare_abstain",
        "fired_target": False,
        "target_remediation_kind": None,
        "published_codes": [],
        "published_critics": [],
        "critics_run": [],
    } for it in items]


def write_predictions(preds: List[Dict[str, Any]], path: str) -> None:
    with open(path, "w") as fh:
        for p in preds:
            fh.write(json.dumps(p) + "\n")


def load_predictions(path: str) -> List[Dict[str, Any]]:
    out = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out
