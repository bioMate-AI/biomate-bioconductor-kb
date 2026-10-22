"""cyclic_denovo_adapter.py — WIRE the cyclic rule-constrained generation into the EXISTING product loop.

No new loop. Reuses backend `drug_discovery.denovo_pipeline.DeNovoPipeline` + `bayesian_optimizer.
BayesianOptimizer` (the Saturn-class multi-objective GP + EHVI + diversity loop that's already built), and
plugs in:
  * GENERATOR  = our SNG rule-constrained proposer (rule_conditioned_generator.gen_avb6) — rules constrain +
                 reject BY CONSTRUCTION, emitting HELM. Wrapped as a `generators.Generator`.
  * OBJECTIVES = the Experience KB + physics as `ObjectiveSpec` predictors (HELM_list -> {HELM: value}):
                 FTO-DoE, developability, binding (score() physics; feasibility-0 until physics lands).
  * FEATURISER = HELM-aware (the BO's default is SMILES->Morgan; we override to a monomer-token hashing vector
                 so HELM strings flow through the GP). One method override — not a rebuild.
CPU-runnable end-to-end (SNG enumeration + cheap KB objectives + GP). The hard rule gate is enforced in the
GENERATOR (SNG); the BO ranks the rule-valid library by the soft KB/physics objectives.
"""
from __future__ import annotations
import os, sys, hashlib
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.abspath(os.path.join(HERE, "../../../backend/lib"))
for p in (HERE, BACKEND):
    if p not in sys.path:
        sys.path.insert(0, p)

from galaxy.ai.drug_discovery.generators import Generator, GenerationSpec
from galaxy.ai.drug_discovery.denovo_pipeline import DeNovoPipeline, ObjectiveSpec
from galaxy.ai.drug_discovery import bayesian_optimizer as _bo

import rule_conditioned_generator as rcg
import fto_score as _fto
from score import developability, score
from acceptance_gate import raw_tokens

_DOE = {"LOW": 0.0, "MED": 0.5, "HIGH": 1.0, "infringes": 1.0}


# ---- HELM-aware featuriser (override the BO's SMILES->Morgan) ----
def _helm_featurise(self, helm_list):
    """Fixed-dim monomer-token hashing vector so HELM candidates featurise for the GP."""
    F = 512
    out = np.zeros((len(helm_list), F), dtype=np.float64)
    for i, h in enumerate(helm_list):
        try:
            toks = raw_tokens(h)
        except Exception:
            toks = [h]
        for t in toks:
            out[i, int(hashlib.md5(t.encode()).hexdigest(), 16) % F] += 1.0
        n = max(len(toks), 1)
        out[i] /= n
    return out


_bo.BayesianOptimizer._featurise = _helm_featurise   # reuse the whole BO; just swap featurisation


# ---- GENERATOR: our SNG rule-constrained proposer, as a product Generator ----
class CyclicSNGGenerator(Generator):
    name = "cyclic_sng_rule_constrained"
    is_learned = False

    def propose(self, spec: GenerationSpec):
        n = spec.n_molecules or 24
        _H, X = rcg.gen_avb6(n)                       # rule+FTO constrained BY CONSTRUCTION
        helms = [c["helm"] for c in X]
        self.last_status = {"ok": bool(helms), "reason": "ok" if helms else "no_candidates",
                            "generator": self.name, "n": len(helms)}
        return helms


# ---- OBJECTIVES: KB + physics as predictors (HELM_list -> {HELM: value}) ----
def _pred_fto_clearance(helms):                       # maximize (1 - DoE risk)
    out = {}
    for h in helms:
        try:
            f = _fto.fto_score(h, "avb6")
            out[h] = 1.0 - _DOE.get(f["claim"]["doe"], 0.5)
        except Exception:
            out[h] = 0.0
    return out


def _pred_developability(helms):                      # maximize (liability-free + mid hydrophobicity)
    out = {}
    for h in helms:
        try:
            d = developability(h)
            band = 1.0 if (-0.2 <= d.get("meanH", 0) <= 0.7) else 0.4
            out[h] = max(0.0, 1.0 - 0.25 * len(d.get("liabilities", []))) * band * (1.0 if d.get("pass") else 0.6)
        except Exception:
            out[h] = 0.0
    return out


def _pred_binding(helms):                             # maximize (physics; feasibility-0 until physics lands)
    out = {}
    for h in helms:
        try:
            r = score(h, "avb6", tier="full")
            b = r.get("ddg_fep")
            b = b if isinstance(b, (int, float)) else r.get("binding_dG")
            out[h] = max(0.0, min(1.0, -float(b) / 3.0)) if isinstance(b, (int, float)) else 0.0
        except Exception:
            out[h] = 0.0
    return out


def build(campaign="avb6-cyclic-denovo", db_path="/tmp/cyclic_denovo.db"):
    objectives = [
        ObjectiveSpec(name="fto_clearance", predictor=_pred_fto_clearance, direction="maximize"),
        ObjectiveSpec(name="developability", predictor=_pred_developability, direction="maximize"),
        ObjectiveSpec(name="binding", predictor=_pred_binding, direction="maximize"),
    ]
    gen = CyclicSNGGenerator()
    pipe = DeNovoPipeline(campaign_id=campaign, generator=gen, objectives=objectives,
                          db_path=db_path, n_initial=6)
    return pipe, gen


if __name__ == "__main__":
    pipe, gen = build()
    # seed set the GP is fit on: a rule-constrained pool, scored by the same objectives
    _H, seedX = rcg.gen_avb6(16)
    seed = [c["helm"] for c in seedX]
    print(f"seed rule-constrained candidates: {len(seed)}", flush=True)
    spec = GenerationSpec(n_molecules=24, max_candidates=200)
    res = pipe.run_round(spec, seed_smiles=seed, n_propose=8, diversity_weight=0.2)
    print(f"\n=== REUSED product loop (DeNovoPipeline + BayesianOptimizer) on cyclic SNG generation ===")
    print(f"generator={gen.name}  generated={getattr(res,'n_generated',None)}  scored={getattr(res,'n_scored',None)}")
    sl = getattr(res, "shortlist", None) or getattr(res, "ranked", None) or []
    for r in (sl[:8] if isinstance(sl, list) else []):
        print("  ", {k: (round(v, 3) if isinstance(v, float) else v) for k, v in r.items()})
    print("\nWIRED: cyclic rule-constrained generator -> existing multi-objective BO loop (reuse, no rebuild).")
