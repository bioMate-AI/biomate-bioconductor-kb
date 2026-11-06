"""VerifierHook: score.py's CHEAP tier + reward.py as a graded-reward hook (inventory rows 12, 15). Honest by construction:
 - a pass is never binding evidence (rule gate applies to alphavbeta6 only; other targets: rule_applicable=False, gate = FTO + developability only);
 - physics fields stay 'pending' (reward contribution 0) and are listed explicitly in every record;
 - tier='full' reads precomputed physics results and the FTO structure axis may contact external services: refused unless allow_full=True."""
import os, sys
from _paths import CYC
import score as _score, reward as _reward
from v4_adapter import helm_from_tokens

PHYS_FIELDS = ("ddg_fep", "binding_dG", "selectivity_gap", "groove_occupancy", "geometry")


class VerifierHook:
    def __init__(self, target="avb6", allow_full=False): self.target, self.allow_full = target, bool(allow_full)

    def grade_helm(self, helm, tier="cheap"):
        if tier != "cheap" and not (tier == "full" and self.allow_full): raise ValueError("only tier='cheap' is allowed (tier='full' needs allow_full=True)")
        rec = _score.score(helm, target=self.target, tier=tier); r = _reward.reward(rec)
        return dict(helm=helm, target=self.target, tier=tier, reward=r["reward"], gated=r["gated"], terms=r["terms"], hard_gate_pass=rec["hard_gate_pass"],
                    hard_gate_reasons=rec["hard_gate_reasons"], rule_applicable=rec["rule_applicable"], fto_verdict=rec["fto"]["verdict"],
                    developability_pass=rec["developability"]["pass"], pending_physics=[f for f in PHYS_FIELDS if not isinstance(rec.get(f), (int, float))], record=rec)

    def grade_tokens(self, tokens, tier="cheap"):
        h = helm_from_tokens(tokens); return None if h is None else self.grade_helm(h, tier)
