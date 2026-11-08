"""Tabular softmax-policy environment for the U3 control (numpy only; runs on EC2 with the tests).

P prompts x K items; item quality s[p,k] in [0,1] is the graded reward. Binary reward = 1[s >= thr].
Start policies:  'concentrated' - almost all mass on a few items that all pass the threshold (consistent per prompt, the
situation of the stalled GRPO run: every group has identical binary rewards);  'broad' - uniform (binary reward varies).
Updaters: 'legacy' (binary GRPO, z-scored advantage) and 'graded' (GradedPreferenceUpdater + tabular DPO)."""
from __future__ import annotations

import numpy as np

from .preference_updater import GradedPreferenceUpdater, KLWeightGate, LegacyBinaryGRPO, dpo_loss_and_grad_coef


def make_env(seed: int, P: int = 8, K: int = 64, thr: float = 0.2, start: str = "concentrated", conc: float = 8.0,
             n_core: int = 6):
    rng = np.random.default_rng(1000 + seed)
    s = rng.uniform(0, 1, (P, K))
    theta0 = np.zeros((P, K))
    if start == "concentrated":
        for p in range(P):
            passing = np.where(s[p] >= thr)[0]
            core = rng.choice(passing, size=n_core, replace=False)
            theta0[p, core] = conc
    return dict(s=s, theta0=theta0, thr=thr, P=P, K=K)


def _probs(theta):
    z = theta - theta.max(axis=1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=1, keepdims=True)


def _kl(theta, theta0):
    p, q = _probs(theta), _probs(theta0)
    return float(np.mean(np.sum(p * (np.log(p + 1e-300) - np.log(q + 1e-300)), axis=1)))


def run(env, updater: str, rounds: int = 10, group: int = 16, lr: float = 1.0, beta: float = 0.5, seed: int = 0,
        epochs: int = 1, use_gate: bool = False):
    rng = np.random.default_rng(seed)
    s, thr, P, K = env["s"], env["thr"], env["P"], env["K"]
    theta0 = env["theta0"].copy()
    theta = theta0.copy()
    e0 = float(np.mean(np.sum(_probs(theta0) * s, axis=1)))
    upd = GradedPreferenceUpdater(group_size=group, margin=0.02)
    legacy = LegacyBinaryGRPO(thr)
    gate = KLWeightGate(check_from=3)
    hist = []
    for r in range(rounds):
        pr = _probs(theta)
        acts = np.stack([rng.choice(K, size=group, p=pr[p]) for p in range(P)])          # P x group
        sc = np.take_along_axis(s, acts, axis=1)
        if updater == "legacy":
            adv, frac0 = legacy.advantages({p: sc[p] for p in range(P)})
            grad = np.zeros_like(theta)
            for p in range(P):
                for a, A in zip(acts[p], adv[p]):
                    oh = np.zeros(K)
                    oh[a] = 1.0
                    grad[p] += A * (oh - pr[p])
            theta += lr * grad / group
            diag = {"frac_zero_variance_groups": frac0, "n_pairs": 0}
        else:
            flat_samples = [f"{p}:{a}" for p in range(P) for a in acts[p]]
            flat_scores = [float(x) for p in range(P) for x in sc[p]]
            groups = [p for p in range(P) for _ in range(group)]
            _, diag = upd.make_pairs(flat_samples, flat_scores, group_by=groups)
            ps = upd.last_index_pairs
            for _ in range(epochs):
                g = np.zeros_like(theta)
                for w, l in zip(ps.winners, ps.losers):
                    pw, aw = divmod(w, group)
                    pl, al = divmod(l, group)
                    k_w, k_l = acts[pw, aw], acts[pl, al]
                    lw, ll = theta[pw, k_w], theta[pl, k_l]
                    rlw, rll = theta0[pw, k_w], theta0[pl, k_l]
                    _, dz = dpo_loss_and_grad_coef(lw, ll, rlw, rll, beta)
                    g[pw, k_w] += dz * beta
                    g[pl, k_l] -= dz * beta
                theta -= lr * g / max(1.0, len(ps) / P)       # per-prompt average pair count
        kl = _kl(theta, theta0)
        relw = float(np.linalg.norm(theta - theta0) / (np.linalg.norm(theta0) + 1e-12)) if np.linalg.norm(theta0) > 0 \
            else float(np.linalg.norm(theta - theta0))
        act = gate.update(r, kl, relw) if use_gate else "off"
        hist.append(dict(round=r, kl=kl, rel_weight_change=relw, gate=act, **{k: v for k, v in diag.items()
                         if k in ("frac_zero_variance_groups", "n_pairs", "frac_groups_retained")}))
    e1 = float(np.mean(np.sum(_probs(theta) * s, axis=1)))
    return dict(gain=e1 - e0, e0=e0, e1=e1, kl=hist[-1]["kl"], rel_weight_change=hist[-1]["rel_weight_change"], hist=hist)
