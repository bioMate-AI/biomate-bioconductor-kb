"""Loader for knowledge_kb_v1.json (workstream K).

KnowledgePotential: sequence-level log-linear potential from the weight-eligible rules (verified quote, tier T1/T2, kind rule/fundamental),
for use as a product-of-experts reweighting of candidates or as soft-rule input to a Constraint (U1 owns token-level use).
  - directional rules: w * sign * z(feature), z from caller-provided (mean, sd) (compute on source group A only)
  - window rules: hinge penalties on the stated thresholds (any_of = min over alternatives; max_violations = tolerated count)
rules_text(): short provenance-tagged snippets for retrieval-conditioned prompts.
RDKit is imported lazily (only features_from_smiles needs it).
"""
from __future__ import annotations
import json
from typing import Dict, Iterable, List, Optional

from kb_schema import validate

_UPPER = ("_max", "_soft_max")
_LOWER = ("_min",)


def _split_key(k: str):
    for suf in _UPPER:
        if k.endswith(suf):
            return k[: -len(suf)], "max"
    for suf in _LOWER:
        if k.endswith(suf):
            return k[: -len(suf)], "min"
    return None, None


def load_kb(path: str) -> dict:
    doc = json.load(open(path))
    bad = {e["id"]: validate(e) for e in doc["rules"] if validate(e)}
    if bad:
        raise ValueError(f"invalid knowledge entries: {bad}")
    return doc


class KnowledgePotential:
    def __init__(self, kb_path_or_doc, lam: float = 1.0, stats: Optional[Dict[str, tuple]] = None,
                 rule_ids: Optional[Iterable[str]] = None):
        doc = load_kb(kb_path_or_doc) if isinstance(kb_path_or_doc, str) else kb_path_or_doc
        self.rules = [e for e in doc["rules"] if e["weight_eligible"] and e["quote_verified"]]
        if rule_ids is not None:
            keep = set(rule_ids)
            self.rules = [e for e in self.rules if e["id"] in keep]
        self.lam = lam
        self.stats = stats or {}

    @staticmethod
    def _norm_key(f: str) -> str:
        return "clogp" if f == "alogp" else f

    def _hinge(self, feats: Dict[str, float], key: str, thr: float) -> Optional[float]:
        f, side = _split_key(key)
        if f is None:
            return None
        f = self._norm_key(f)
        if f not in feats or feats[f] is None or thr == 0:
            return None
        x = feats[f]
        return max(0.0, (x - thr) / abs(thr)) if side == "max" else max(0.0, (thr - x) / abs(thr))

    def _window_penalty(self, feats, win: dict) -> float:
        any_of = set(win.get("any_of", []))
        mv = win.get("max_violations")
        keys = [k for k in win if _split_key(k)[0] is not None]
        if mv is not None:
            viol = 0
            for k in keys:
                h = self._hinge(feats, k, win[k])
                viol += 1 if (h is not None and h > 0) else 0
            return float(max(0, viol - mv))
        fixed = [self._hinge(feats, k, win[k]) for k in keys if k not in any_of]
        alts = [self._hinge(feats, k, win[k]) for k in keys if k in any_of]
        pen = sum(h for h in fixed if h is not None)
        alts = [a for a in alts if a is not None]
        if alts:
            pen += min(alts)
        return pen

    def log_potential(self, feats: Dict[str, float]) -> float:
        total = 0.0
        for e in self.rules:
            w = e["weight"]
            if e["direction"] in ("+", "-", "multi"):
                for f, sgn in e["feat_mapped"].items():
                    f = self._norm_key(f)
                    if f not in feats or feats[f] is None or f not in self.stats:
                        continue
                    mu, sd = self.stats[f]
                    scale = e["proxy_scale"] if f in e.get("feat_proxy", []) else 1.0
                    total += self.lam * w * scale * sgn * (feats[f] - mu) / (sd if sd > 0 else 1.0)
            elif e["direction"] == "window" and e.get("window"):
                total -= self.lam * w * self._window_penalty(feats, e["window"])
        return total


def rules_text(doc: dict, kinds=("rule", "fundamental"), tiers=("T1", "T2"), scope_contains: Optional[str] = None,
               target: Optional[str] = None, max_rules: int = 8, include_cautions: bool = True) -> str:
    out: List[str] = []
    pool = [e for e in doc["rules"] if e["quote_verified"] and e["tier"] in tiers and e["kind"] in kinds]
    if scope_contains:
        pool = [e for e in pool if any(scope_contains.lower() in s.lower() for s in e["scope"])]
    if target:
        pool = [e for e in pool if (e.get("applicable_target") is None) or target in e["applicable_target"]]
    pool.sort(key=lambda e: (e["confidence"] != "high", e["tier"], e["id"]))
    for e in pool[:max_rules]:
        s = e["source"]
        out.append(f"- [{e['id']}] {e['statement']} ({s.get('journal','')} {s.get('year','')}, doi:{s.get('doi','')})")
    if include_cautions:
        for e in [x for x in doc["rules"] if x["kind"] == "caution" and x["quote_verified"]][:2]:
            out.append(f"- [CAUTION {e['id']}] {e['statement']}")
    return "\n".join(out)


def features_from_smiles(smiles: str) -> Dict[str, Optional[float]]:
    """2D features for the potential (RDKit, lazy). n_dres is None (needs monomer parsing: see ihlm/symbolic.py)."""
    from rdkit import Chem
    from rdkit.Chem import Crippen, Descriptors, Lipinski, rdMolDescriptors
    m = Chem.MolFromSmiles(smiles)
    if m is None:
        return {}
    ri = m.GetRingInfo()
    biggest = max([len(r) for r in ri.AtomRings()] or [0])
    nme = len(m.GetSubstructMatches(Chem.MolFromSmarts("[CX3](=O)[NX3;H0]([CH3])[#6]")))
    return {"tpsa": rdMolDescriptors.CalcTPSA(m), "hbd": float(Lipinski.NumHDonors(m)), "hba": float(Lipinski.NumHAcceptors(m)),
            "mw": Descriptors.MolWt(m), "clogp": Crippen.MolLogP(m), "nrotb": float(rdMolDescriptors.CalcNumRotatableBonds(m)),
            "n_heavy_atoms": float(m.GetNumHeavyAtoms()), "n_nme": float(nme), "n_dres": None, "is_cyclic": 1.0 if biggest >= 12 else 0.0}
