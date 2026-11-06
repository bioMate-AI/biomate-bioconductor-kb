"""Contrastive pose selector (PREREG A8): linear scorer trained with a multi-positive InfoNCE (listwise softmax) loss WITHIN each complex.
For one complex with samples i, scores s_i = w . x_i (x = within-complex z-scored features) and positives P = {DockQ >= thr}:
    loss = -log( sum_{i in P} exp(s_i) / sum_i exp(s_i) )  +  lam/2 * |w|^2 / n_complexes_used
Only complexes with at least one positive AND one negative carry contrast and are used. No ground-truth column may be a feature (same guard as selector.py)."""
import os, sys
import numpy as np
from scipy.optimize import minimize
from scipy.special import logsumexp
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import selector as SEL


def loss_and_grad(w, Xs, ys, lam):
    f, g = 0.0, np.zeros_like(w)
    for X, y in zip(Xs, ys):
        s = X @ w; lse_all = logsumexp(s); pos = y.astype(bool); lse_pos = logsumexp(s[pos])
        f += lse_all - lse_pos
        p_all = np.exp(s - lse_all); p_pos = np.zeros_like(s); p_pos[pos] = np.exp(s[pos] - lse_pos)
        g += X.T @ (p_all - p_pos)
    n = len(Xs); return f / n + 0.5 * lam * (w @ w), g / n + lam * w


class ContrastiveSelector:
    def __init__(self, lam=0.1, feats=SEL.FEATURES):
        SEL.assert_no_gt_columns(feats); self.lam = lam; self.feats = list(feats); self.w = None; self.trivial = None

    def fit(self, rows_by_complex, thr=0.23):
        Xs, ys = [], []
        for rows in rows_by_complex.values():
            y = np.array([int(r["dockq"] >= thr) for r in rows])
            if 0 < y.sum() < len(y): Xs.append(SEL.within_complex_features(rows, self.feats)); ys.append(y)
        if not Xs: self.trivial = True; return self
        r = minimize(loss_and_grad, np.zeros(Xs[0].shape[1]), args=(Xs, ys, self.lam), jac=True, method="L-BFGS-B")
        self.w = r.x; self.trivial = False; return self

    def pick(self, rows):
        if self.trivial: return int(np.argmax([r.get("confidence_score") if r.get("confidence_score") is not None else -1e18 for r in rows]))
        return int(np.argmax(SEL.within_complex_features(rows, self.feats) @ self.w))

    def coef(self):
        return {} if self.trivial else dict(sorted(zip(self.feats, self.w.round(3)), key=lambda kv: -abs(kv[1])))
