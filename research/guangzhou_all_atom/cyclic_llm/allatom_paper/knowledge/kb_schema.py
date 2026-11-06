"""Schema v1.0 for the literature-sourced knowledge layer (workstream K). Pure python (no heavy imports).

Entry kinds: rule | fundamental | caution | card. Tiers: T1 primary quantitative study, T2 review/textbook/author background statement,
T3 secondary (Wikipedia/Wikidata/vendor), T-internal (our own campaign docs, file path in source.path).
A rule may carry weight ONLY if: tier in {T1,T2}, kind in {rule,fundamental}, quote_verified is True, direction in WEIGHTED_DIRECTIONS
and it maps to at least one computable feature. Everything else is kept for retrieval context with weight 0.
"""
from __future__ import annotations
import re

SCHEMA_VERSION = "1.0"
KINDS = ("rule", "fundamental", "caution", "card")
TIERS = ("T1", "T2", "T3", "T-internal")
DIRECTIONS = ("+", "-", "multi", "window", "context", "caution", "conflict")
WEIGHTED_DIRECTIONS = ("+", "-", "multi", "window")
CONFIDENCE = ("high", "medium", "low")
COMPUTABLE = {"tpsa", "hbd", "hba", "mw", "clogp", "alogp", "nrotb", "n_heavy_atoms", "n_nme", "n_dres", "is_cyclic"}
PROXY = {"exposed_nh": "hbd"}           # feature that stands in for a non-2D-computable one (weight scaled by 0.5)
REQUIRED = ("id", "kind", "statement", "direction", "scope", "outcome", "tier", "source", "quote", "confidence", "access_date",
            "extracted_by", "weight", "weight_eligible", "quote_verified", "applicable_target", "structure_ref")
ID_RE = re.compile(r"^(LIT|CARD|INT)-[A-Z0-9]+-\d{3}$")


def outcome_class(outcome: str) -> str:
    """permeability | stability | solubility | other  (weights from different classes must not be summed into one potential)."""
    o = (outcome or "").lower()
    if any(k in o for k in ("permeab", "absorption", "oral", "mdck", "caco", "cp50")):
        return "permeability"
    if any(k in o for k in ("stab", "protease", "half-life", "proteoly")):
        return "stability"
    if "solub" in o:
        return "solubility"
    return "other"


def quote_words(q: str) -> int:
    return len(q.split())


def validate(entry: dict) -> list:
    """Return a list of problems (empty = valid)."""
    p = []
    for k in REQUIRED:
        if k not in entry:
            p.append(f"missing:{k}")
    if p:
        return p
    if not ID_RE.match(entry["id"]):
        p.append("bad_id")
    if entry["kind"] not in KINDS:
        p.append("bad_kind")
    if entry["tier"] not in TIERS:
        p.append("bad_tier")
    if entry["direction"] not in DIRECTIONS:
        p.append("bad_direction")
    if entry["confidence"] not in CONFIDENCE:
        p.append("bad_confidence")
    s = entry["source"]
    if entry["tier"] != "T-internal":
        for k in ("pmcid", "doi", "title", "journal", "year", "url"):
            if not s.get(k):
                p.append(f"source_missing:{k}")
    else:
        if not s.get("path"):
            p.append("source_missing:path")
    if not entry["quote"] or quote_words(entry["quote"]) > 30:
        p.append("quote_empty_or_over_30_words")
    for q in entry.get("quotes", []) or []:
        if not q or quote_words(q) > 30:
            p.append("extra_quote_empty_or_over_30_words")
    if entry["kind"] == "card":
        c = entry.get("card") or {}
        for k in ("method", "modality", "outcome", "failure_modes", "lessons"):
            if not c.get(k):
                p.append(f"card_missing:{k}")
    if entry["weight_eligible"]:
        if entry["tier"] not in ("T1", "T2") or entry["kind"] not in ("rule", "fundamental"):
            p.append("eligible_tier_or_kind")
        if entry["direction"] not in WEIGHTED_DIRECTIONS:
            p.append("eligible_direction")
        if not entry["quote_verified"]:
            p.append("eligible_but_quote_unverified")
    if (not entry["weight_eligible"]) and entry["weight"] not in (0, 0.0):
        p.append("weight_without_eligibility")
    if not entry["quote_verified"] and entry["weight"] not in (0, 0.0):
        p.append("unverified_has_weight")
    if entry["applicable_target"] is not None and not isinstance(entry["applicable_target"], list):
        p.append("applicable_target_not_list")
    if entry["structure_ref"] is not None and not isinstance(entry["structure_ref"], list):
        p.append("structure_ref_not_list")
    return p
