"""Tier-0 hard rules as a post-hoc Constraint.check (free filter in BudgetedOracle; no oracle call is charged for a failure).

Rules (docs/20261031_ALLATOM_LLM_PAPER_DESIGN.md section 3): macrocycle (a ring of >= `ring_min` atoms), N-methyl amide count in
[nme_min, nme_max], molecular weight <= mw_max, no PAINS alert. The token-level automaton with prefix-feasibility look-ahead
(mask/advance/is_complete/soft_logits) is workstream U1; this class implements `check` and `explain` only, and refuses the
automaton methods explicitly so nobody mistakes it for the decoder constraint."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional

_STATE = {}


def _rd():
    from rdkit import Chem, RDLogger
    from rdkit.Chem import Descriptors
    from rdkit.Chem.FilterCatalog import FilterCatalog, FilterCatalogParams
    RDLogger.DisableLog("rdApp.*")
    if not _STATE:
        p = FilterCatalogParams()
        p.AddCatalog(FilterCatalogParams.FilterCatalogs.PAINS)
        _STATE["pains"] = FilterCatalog(p)
        _STATE["nme"] = Chem.MolFromSmarts("[CX3](=O)[NX3]([CH3])")
    return Chem, Descriptors


@dataclass(frozen=True)
class HardRules:
    ring_min: int = 12
    nme_min: int = 2
    nme_max: int = 6
    mw_max: float = 1300.0
    use_pains: bool = True

    def explain(self, smiles: str) -> Dict[str, object]:
        """Per-rule outcome; `ok` is True only if every rule passes; invalid SMILES -> ok False, reason 'invalid'."""
        Chem, Descriptors = _rd()
        m = Chem.MolFromSmiles(smiles) if isinstance(smiles, str) and smiles else None
        if m is None:
            return {"ok": False, "reason": "invalid"}
        ring = max((len(r) for r in m.GetRingInfo().AtomRings()), default=0)
        nme = len(m.GetSubstructMatches(_STATE["nme"]))
        mw = float(Descriptors.MolWt(m))
        pains = bool(self.use_pains and _STATE["pains"].HasMatch(m))
        res = {"ring_ok": ring >= self.ring_min, "max_ring": ring, "nme_ok": self.nme_min <= nme <= self.nme_max, "n_nme": nme,
               "mw_ok": mw <= self.mw_max, "mw": mw, "pains_ok": not pains}
        res["ok"] = bool(res["ring_ok"] and res["nme_ok"] and res["mw_ok"] and res["pains_ok"])
        return res

    # -- Constraint.check (post-hoc, used as the free filter)
    def check(self, smiles: str) -> bool:
        return bool(self.explain(smiles)["ok"])

    # -- the automaton surface belongs to U1: refuse explicitly, whatever the arguments
    @staticmethod
    def _refuse(*args, **kwargs):
        raise NotImplementedError("HardRules is the post-hoc filter; the decoding automaton is workstream U1")

    def init_state(self, *args, **kwargs):
        return self._refuse()

    def mask(self, *args, **kwargs):
        return self._refuse()

    def advance(self, *args, **kwargs):
        return self._refuse()

    def is_complete(self, *args, **kwargs):
        return self._refuse()

    def soft_logits(self, *args, **kwargs):
        return self._refuse()
