import inspect

import numpy as np

from . import hack_env as H
from .stop_monitor import AlwaysStop, GapStopMonitor, NeverStop


def _batches(T_gain, S_gain, T=20, n=400, seed=0):
    """Both verifiers see the same latent quality of each molecule (so selecting on train also selects on stop) plus small
    independent noise; T_gain / S_gain are the population-level improvements seen by each verifier at round t."""
    rng = np.random.default_rng(seed)
    out = []
    for t in range(T):
        lat = rng.normal(0, 1, n)
        out.append((lat + T_gain(t) + 0.3 * rng.normal(size=n), lat + S_gain(t) + 0.3 * rng.normal(size=n)))
    return out


def test_stops_when_train_climbs_and_stop_flattens_and_restores_best_round():
    m = GapStopMonitor()
    res = []
    for t, (tr, st) in enumerate(_batches(lambda t: 0.5 * t, lambda t: min(t, 5) * 0.8)):
        d = m.update(t, tr, st)
        res.append(d)
        if d["should_stop"]:
            break
    assert res[-1]["should_stop"] and 5 <= m.stopped_at <= 14
    assert 3 <= res[-1]["restore_round"] <= 9                                          # near where the stop score peaked


def test_does_not_stop_when_both_improve_or_both_plateau():
    for tg, sg in ((lambda t: 0.5 * t, lambda t: 0.5 * t), (lambda t: min(t, 4), lambda t: min(t, 4))):
        m = GapStopMonitor()
        stopped = False
        for t, (tr, st) in enumerate(_batches(tg, sg, seed=1)):
            stopped = m.update(t, tr, st)["should_stop"] or stopped
        assert not stopped


def test_controls_behave():
    n, a = NeverStop(), AlwaysStop(warmup=2)
    for t in range(6):
        dn, da = n.update(t, [0.0], [0.0]), a.update(t, [0.0], [0.0])
        assert not dn["should_stop"]
        assert da["should_stop"] == (t >= 2)
    assert da["restore_round"] == 2


def test_monitor_signature_has_no_heldout_input():
    sig = inspect.signature(GapStopMonitor.update)
    assert list(sig.parameters) == ["self", "round_idx", "train_scores", "stop_scores"]


def test_envs_are_deterministic_and_hack_directions_orthogonal():
    e1, e2 = H.make("hackable", 3), H.make("hackable", 3)
    assert np.allclose(e1["xs"], e2["xs"]) and abs(e1["uh"] @ e1["xs"]) < 1e-9 and abs(e1["us"] @ e1["uh"]) < 1e-9
    a, b = H.run_es(e1, 3, T=5), H.run_es(e2, 3, T=5)
    assert np.allclose(a["H"], b["H"])


def test_hackable_env_rises_then_falls_for_most_seeds():
    ups = 0
    for s in range(20):
        Hs = H.run_es(H.make("hackable", s), s, T=40)["H"]
        ups += int(max(Hs) > Hs[0] and Hs[-1] < max(Hs) - 0.3 * (max(Hs) - Hs[0]))
    assert ups >= 12                                                                   # planted Goodhart shape exists (validity is checked at scale in stage A)
