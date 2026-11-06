"""Technique T1 core: evidence-weighted fusion of a prior P and an analog estimate A (pre-registered in docs/20261030_TECHNIQUE_T1_FUSION.md).
  s(x) = w_k * z(P(x)) + (1 - w_k) * z(A(x; revealed)),   w_k = n0 / (n0 + k)
z = centre/scale over the evaluated candidate set (constant component -> 0)."""
import numpy as np
from scipy.stats import spearmanr
EPS = 1e-12


def z(v):
    v = np.asarray(v, float); s = v.std()
    return np.zeros_like(v) if (not np.isfinite(s) or s < EPS) else (v - v.mean()) / s


def w_k(k, n0): return n0 / (n0 + k)


def fuse(P, A, k, n0=5.0, w=None):
    """k = number of revealed labels; k = 0 -> w = 1 -> prior only. w overrides (descriptive weight curves only)."""
    w = w_k(k, n0) if w is None else w
    return w * z(P) + (1.0 - w) * z(A)


def tanimoto(Xa, Xb):
    """Xa (n,d), Xb (m,d) 0/1 arrays -> (n,m) Tanimoto."""
    Xa = np.asarray(Xa, np.float64); Xb = np.asarray(Xb, np.float64); inter = Xa @ Xb.T
    return inter / (Xa.sum(1)[:, None] + Xb.sum(1)[None, :] - inter + 1e-9)


def analog_perm(sim, y_rev, p=4, lam=0.05):
    """Permeability analog estimate: sim (n_rest, k) Tanimoto; y_rev raw revealed labels. A_i = sum_j s^p (y_j - ybar) / (sum_j s^p + lam)."""
    y = np.asarray(y_rev, float); W = np.asarray(sim, float) ** p
    return (W @ (y - y.mean())) / (W.sum(1) + lam)


def spearman(a, b):
    a = np.round(np.asarray(a, float), 10); b = np.asarray(b, float)     # round scores: exact mathematical ties must stay ties (1-ulp float noise otherwise breaks them differently per implementation)
    if len(a) < 3 or np.std(a) < EPS or np.std(b) < EPS: return np.nan
    return float(spearmanr(a, b)[0])


# ---- Amendment A1 (F2): reliability-weighted analog component -----------------------------------------------------------------
R0, M0 = 0.5, 3.0          # shrinkage prior mean and pseudo-count for the reliability, fixed once (A1) and tested on synthetic worlds only


def reliability_perm(sim_rr, y_rev, p=4, lam=0.05, min_mass=0.01):
    """Leave-one-out reliability of the analog estimate from the revealed set only. sim_rr (k,k) Tanimoto among revealed, y_rev raw labels.
    For each revealed j with analog mass sum_i s_ji^p > min_mass: A^{-j}_j from the other revealed items; r_hat = clip(Spearman(A^{-j}, y), 0, 1);
    r = (m r_hat + M0 R0) / (m + M0), m = number of usable revealed items (0 usable -> r = R0)."""
    y = np.asarray(y_rev, float); k = len(y)
    if k < 3: return R0
    W = np.asarray(sim_rr, float) ** p; np.fill_diagonal(W, 0.0); mass = W.sum(1); ok = mass > min_mass; m = int(ok.sum())
    if m < 3: return (m * 0.0 + M0 * R0) / (m + M0)
    Aloo = np.array([(W[j] @ (y - (y.sum() - y[j]) / (k - 1))) / (mass[j] + lam) if ok[j] else np.nan for j in range(k)])
    rh = spearman(Aloo[ok], y[ok]); rh = 0.0 if not np.isfinite(rh) else float(np.clip(rh, 0.0, 1.0))
    return (m * rh + M0 * R0) / (m + M0)


def fuse2(P, A, k, r, n0=5.0):
    """F2: s = w_k z(P) + (1 - w_k) r z(A), r in [0, 1] = reliability of the analog component from the revealed set."""
    w = w_k(k, n0); return w * z(P) + (1.0 - w) * r * z(A)


def reliability_nn(sim_rr, labels, tie_auc):
    """Binding analogue of reliability_perm (A1): leave-one-out reliability of the NN score (max sim to revealed positives - max sim to revealed inactives)
    among the revealed items. sim_rr (k,k) Tanimoto; labels 0/1; tie_auc(y, s) = tie-aware AUROC. Items whose leave-one-out reference lacks both a positive
    and an inactive are skipped; r_hat = clip(2*AUC - 1, 0, 1); r = (m r_hat + M0 R0)/(m + M0); fewer than 2 usable items or one class -> r_hat = 0."""
    lab = np.asarray(labels, int); k = len(lab); S = np.asarray(sim_rr, float).copy(); np.fill_diagonal(S, -1.0); sc = []; yy = []
    for j in range(k):
        o = np.array([i for i in range(k) if i != j]); po = o[lab[o] == 1]; ne = o[lab[o] == 0]
        if len(po) == 0 or len(ne) == 0: continue
        sc.append(S[j, po].max() - S[j, ne].max()); yy.append(lab[j])
    m = len(sc)
    if m < 2 or len(set(yy)) < 2: return (m * 0.0 + M0 * R0) / (m + M0)
    rh = float(np.clip(2 * tie_auc(np.array(yy), np.array(sc)) - 1, 0.0, 1.0)); return (m * rh + M0 * R0) / (m + M0)
