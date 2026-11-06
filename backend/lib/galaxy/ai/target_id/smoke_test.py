"""Offline smoke test for the target-ID orchestrator (no galaxy/LLM/network needed).

Run: PYTHONPATH=backend/lib python3 backend/lib/galaxy/ai/target_id/smoke_test.py
Exercises: parallel multi-channel fan-out, the evidence-gate arbiter (OR/AND tiers), and the
tabular arbiter (fallback + a trained toy model). Pure asserts; prints a PASS line.
"""
import sys


def _run():
    from galaxy.ai.target_id import (
        MockChannel, CallableChannel, EvidenceGateArbiter, TabularArbiter,
        TargetIDOrchestrator,
    )

    # 3 channels; TP53 corroborated by all, EGFR by two, MYC by one, NOISE by none-strongly.
    genetics = MockChannel("genetics", {"TP53": 9.0, "EGFR": 8.0, "MYC": 1.1, "NOISE": 1.0, "A": 1.0, "B": 1.0})
    ppi = MockChannel("ppi", {"TP53": 10.0, "EGFR": 7.5, "MYC": 1.0, "NOISE": 1.05, "A": 1.0, "B": 1.0})
    perturb = MockChannel("perturb", {"TP53": 8.5, "EGFR": 1.2, "MYC": 9.0, "NOISE": 1.0, "A": 1.0, "B": 1.0})

    def _boom(ctx):
        raise RuntimeError("channel blew up")
    flaky = CallableChannel("flaky", _boom)  # must be isolated, not crash the run

    orch = TargetIDOrchestrator([genetics, ppi, perturb, flaky], arbiter=EvidenceGateArbiter(z_thresh=2.0))
    res = orch.identify("targets for test indication")

    names = [t.target for t in res.targets]
    tiers = {t.target: t.tier for t in res.targets}
    assert "flaky" in res.channel_errors, "errored channel must be isolated into channel_errors"
    assert set(res.channels_run) == {"genetics", "ppi", "perturb"}, res.channels_run
    assert names[0] == "TP53", "TP53 (fired in all 3 channels) must rank #1; got %s" % names[:3]
    assert tiers["TP53"] == "corroborated", tiers
    assert tiers["EGFR"] == "corroborated", tiers  # fired in genetics+ppi
    assert tiers["MYC"] == "nominated", tiers       # fired only in perturb
    # NOISE/A/B fired nowhere -> 'none' tier, ranked below corroborated/nominated
    assert res.targets[-1].tier == "none"
    top3 = names[:3]
    assert "TP53" in top3 and "EGFR" in top3, top3

    # Tabular arbiter without a model -> honest fallback to the gate (same #1).
    tab = TabularArbiter(model=None)
    res2 = TargetIDOrchestrator([genetics, ppi, perturb], arbiter=tab).identify("q")
    assert res2.arbiter == "tabular" and res2.targets[0].target == "TP53", res2.to_dict()

    # Tabular arbiter WITH a toy model (weights perturb channel) -> MYC should rise.
    class _ToyModel:
        def __init__(self, channels):
            self.channels = channels
        def predict(self, X):
            import numpy as np
            w = np.array([1.0 if c == "perturb" else 0.0 for c in self.channels])
            return X.dot(w)
    feat_channels = ["genetics", "perturb", "ppi"]
    tab2 = TabularArbiter(model=_ToyModel(feat_channels), feature_channels=feat_channels)
    res3 = TargetIDOrchestrator([genetics, ppi, perturb], arbiter=tab2).identify("q")
    assert res3.targets[0].target in ("TP53", "MYC"), [t.target for t in res3.targets[:3]]
    assert "MYC" in [t.target for t in res3.targets[:2]], "perturb-weighted model must lift MYC"

    print("target_id smoke: PASS  (#1=%s, tiers TP53/EGFR/MYC=%s/%s/%s, tabular-fallback + trained OK)" % (
        names[0], tiers["TP53"], tiers["EGFR"], tiers["MYC"]))


if __name__ == "__main__":
    try:
        _run()
    except AssertionError as e:
        print("target_id smoke: FAIL ->", e)
        sys.exit(1)
    except Exception as e:  # pragma: no cover
        print("target_id smoke: ERROR ->", type(e).__name__, e)
        sys.exit(2)
