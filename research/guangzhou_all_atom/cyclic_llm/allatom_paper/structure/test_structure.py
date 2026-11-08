"""Structure-wrapper tests (no cloud spend): meter, plan-never-spends, submit gating, launcher tiers refuse to launch."""
import os
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..")))
from structure.wrappers import BoltzCofoldTier, BoltzGenTier, BudgetExceeded, CostMeter, UniMoMoTier


class FakePB:
    def __init__(self):
        self.calls = []

    def dispatch_cofold(self, target, candidates, run_id=None, dry_run=True):
        self.calls.append((target, len(candidates), dry_run))
        return {"dry_run": dry_run, "run_id": run_id}

    def fetch_result(self, run_id, target):
        return {"ready": False}


def test_plan_never_spends_and_is_dry_run():
    m, pb = CostMeter(1.0), FakePB()
    t = BoltzCofoldTier(m, physics_batch=pb)
    out = t.plan([{"id": "a", "pep": "FRGDLAFPK"}], run_id="r1")
    assert out["dry_run"] is True and pb.calls == [("avb6", 1, True)] and m.spent_est == 0.0


def test_submit_needs_explicit_allow_spend():
    m, pb = CostMeter(1.0), FakePB()
    t = BoltzCofoldTier(m, physics_batch=pb)
    with pytest.raises(PermissionError):
        t.submit([{"id": "a", "pep": "FRGDLAFPK"}])
    assert pb.calls == []                              # nothing reached the dispatcher


def test_submit_respects_cap_before_dispatch_and_records_cost():
    m, pb = CostMeter(0.15), FakePB()
    t = BoltzCofoldTier(m, physics_batch=pb)
    t.submit([{"id": "a", "pep": "FRGDLAFPK"}], allow_spend=True)
    assert pb.calls[-1][2] is False and m.spent_est == pytest.approx(0.10)
    with pytest.raises(BudgetExceeded):
        t.submit([{"id": "b", "pep": "FRGDLAFPK"}], allow_spend=True)
    assert len(pb.calls) == 1                          # the over-cap call never dispatched


def test_launcher_tiers_plan_only_and_scripts_exist():
    m = CostMeter(5.0)
    for T in (BoltzGenTier, UniMoMoTier):
        t = T(m)
        p = t.plan(n=3)
        assert p["est_cost_usd"] > 0 and all(p["scripts_exist"]), p
        with pytest.raises(NotImplementedError):
            t.submit()
    assert m.spent_est == 0.0
