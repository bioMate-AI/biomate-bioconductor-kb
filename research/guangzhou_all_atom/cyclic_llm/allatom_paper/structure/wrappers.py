"""Thin, cost-metered wrappers for the EXISTING structure / physics tier (unmodified): Boltz-2 cofold via physics_batch (Batch
GPU-spot job-def), BoltzGen and UniMoMo (bake-and-run instance launchers). Nothing here trains or modifies a model.

Rules: `plan()` never spends; `submit()` needs `allow_spend=True` AND stays inside the meter's cap; every call is recorded.
Boltz cofold input is SEQUENCE-based (one-letter peptides, `{"id","pep"}`) because the existing converter writes protein/cyclic
entities: non-canonical residues are not representable on this path (documented limitation of the existing tier).
BoltzGen / UniMoMo are launched by whole-instance bake scripts (no library entry point): the wrappers describe the launch (script,
required environment, estimated cost) and refuse to launch from here."""
from __future__ import annotations

import importlib.util
import os
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional

HERE = os.path.dirname(os.path.abspath(__file__))
CYC = os.path.abspath(os.path.join(HERE, "..", ".."))
GA = os.path.abspath(os.path.join(CYC, ".."))            # research/guangzhou_all_atom


class BudgetExceeded(RuntimeError):
    pass


@dataclass
class CallRecord:
    tier: str
    kind: str                # plan | submit
    est_cost_usd: float
    run_id: Optional[str]
    t: float = field(default_factory=time.time)
    detail: Dict = field(default_factory=dict)


class CostMeter:
    def __init__(self, cap_usd: float):
        self.cap_usd, self.calls = float(cap_usd), []

    @property
    def spent_est(self) -> float:
        return sum(c.est_cost_usd for c in self.calls)

    def record(self, tier, kind, est, run_id=None, **detail) -> CallRecord:
        if self.spent_est + est > self.cap_usd + 1e-12:
            raise BudgetExceeded(f"{tier}: {est:.3f} would exceed cap {self.cap_usd:.3f} (spent {self.spent_est:.3f})")
        r = CallRecord(tier, kind, float(est), run_id, detail=detail)
        self.calls.append(r)
        return r


def _load(path: str, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class BoltzCofoldTier:
    EST_USD = 0.10          # upper end of the design's ~0.03-0.10 per complex [ESTIMATE]

    def __init__(self, meter: CostMeter, target: str = "avb6", physics_batch=None):
        self.meter, self.target = meter, target
        self._pb = physics_batch

    def _physics(self):
        if self._pb is None:
            self._pb = _load(os.path.join(CYC, "physics_batch.py"), "physics_batch")
        return self._pb

    def plan(self, candidates: List[Dict], run_id: Optional[str] = None) -> Dict:
        out = self._physics().dispatch_cofold(self.target, candidates, run_id=run_id, dry_run=True)
        self.meter.record("boltz_cofold", "plan", 0.0, run_id, n=len(candidates))
        return out

    def submit(self, candidates: List[Dict], run_id: Optional[str] = None, allow_spend: bool = False) -> Dict:
        if not allow_spend:
            raise PermissionError("submit() needs allow_spend=True (explicit owner/coordinator-approved spend)")
        est = self.EST_USD * len(candidates)
        self.meter.record("boltz_cofold", "submit", est, run_id, n=len(candidates))   # raises BudgetExceeded before any submit
        return self._physics().dispatch_cofold(self.target, candidates, run_id=run_id, dry_run=False)

    def fetch(self, run_id: str) -> Dict:
        return self._physics().fetch_result(run_id, self.target)


class _LauncherTier:
    NAME, SCRIPTS, ENV, EST_USD, NOTE = "", (), (), 0.0, ""

    def __init__(self, meter: CostMeter):
        self.meter = meter

    def plan(self, **kw) -> Dict:
        self.meter.record(self.NAME, "plan", 0.0, None)
        scripts = [os.path.join(GA, s) for s in self.SCRIPTS]
        return dict(tier=self.NAME, scripts=scripts, scripts_exist=[os.path.exists(s) for s in scripts],
                    required_env=list(self.ENV), est_cost_usd=self.EST_USD, note=self.NOTE, params=kw)

    def submit(self, *a, **kw):
        raise NotImplementedError(f"{self.NAME}: launched by whole-instance bake scripts ({', '.join(self.SCRIPTS)}); "
                                  f"launching from this wrapper needs an approved run plan. {self.NOTE}")


class BoltzGenTier(_LauncherTier):
    NAME = "boltzgen"
    SCRIPTS = ("boltzgen_ourtarget.sh", "boltzgen_qualify.sh", "launch_boltzgen_loto_eval.sh")
    ENV = ("OUT_S3", "NUM_DESIGNS", "BUDGET")
    EST_USD = 2.0
    NOTE = "Program finding: our cyclic BoltzGen fine-tune lost to the base model on 3/3 targets; use the base model as is."


class UniMoMoTier(_LauncherTier):
    NAME = "unimomo"
    SCRIPTS = ("launch_dpo_peptide_trainer_unimomo.sh", "audit_unimomo_run.py", "dpo_unimomo_adapter.py")
    ENV = ("OUT_S3",)
    EST_USD = 3.0
    NOTE = "Program finding: UniMoMo cyclic DockQ 0.759 vs 0.506 for our BoltzGen fine-tune (best existing cyclic design baseline)."
