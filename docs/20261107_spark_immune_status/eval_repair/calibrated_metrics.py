#!/usr/bin/env python3
"""Calibrated perturbation / representation metrics (2026-10-04).

Implements the well-calibrated evaluation from Du et al. bioRxiv 2025.10.20.683304 ("Deep learning
perturbation models DO beat baselines on well-calibrated metrics") so our virtual-KO / perturbation-
grounding and representation evals are not fooled by the two miscalibration mechanisms that paper names:
  (1) CONTROL BIAS  — crediting a model for predicting the control->perturbed shift, not the perturbation.
  (2) SIGNAL DILUTION — equal per-gene weighting drowns the few real DEGs in thousands of noise genes.

Core metrics (per-perturbation, pred/truth are Δexpression vectors over genes):
  wmse(pred, truth, w)         DEG-weighted MSE                       (lower better)
  weighted_rho(pred, truth, w) DEG-weighted Pearson corr             (higher better)
  nir(pred, truth_bank, i)     Normalized Inverse Rank of the true    (higher better, in [0,1])
                               profile by Euclidean distance among a bank of candidate truths
  drf(m_pred, m_pos, m_neg)    Dynamic Range Fraction: fraction of the achievable range realized,
                               bounded by a POSITIVE control (held-out replicate) and NEGATIVE
                               control (mean/control baseline).                     (1=matches pos ctrl)

DEG weights: effect-size weighting w_j ∝ |truth_j| (the genes that actually move), the robust continuous
analogue of DEG-membership weighting. Honest: report alongside the naive (unweighted MSE/Pearson), never
instead of — the field disagrees on whether calibration flips the verdict (Bühlmann 2026 vs Du 2025).
"""
import numpy as np


def deg_weights(truth, eps=1e-8):
    """Effect-size (|Δ|) gene weights, normalized to sum 1. truth = Δexpression (perturbed − control)."""
    t = np.abs(np.asarray(truth, float)).ravel()
    s = t.sum()
    return (t / s) if s > eps else np.full(t.size, 1.0 / max(t.size, 1))


def wmse(pred, truth, w=None):
    pred = np.asarray(pred, float).ravel(); truth = np.asarray(truth, float).ravel()
    w = deg_weights(truth) if w is None else np.asarray(w, float).ravel()
    return float(np.sum(w * (pred - truth) ** 2) / max(w.sum(), 1e-12))


def weighted_rho(pred, truth, w=None):
    pred = np.asarray(pred, float).ravel(); truth = np.asarray(truth, float).ravel()
    w = deg_weights(truth) if w is None else np.asarray(w, float).ravel()
    sw = max(w.sum(), 1e-12)
    mp = np.sum(w * pred) / sw; mt = np.sum(w * truth) / sw
    cov = np.sum(w * (pred - mp) * (truth - mt)) / sw
    vp = np.sum(w * (pred - mp) ** 2) / sw; vt = np.sum(w * (truth - mt) ** 2) / sw
    d = np.sqrt(vp * vt)
    return float(cov / d) if d > 1e-12 else 0.0


def nir(pred, truth_bank, true_idx):
    """Normalized Inverse Rank: rank the TRUE profile's Euclidean distance to `pred` among all candidate
    truths in `truth_bank` [N, G]; 1.0 = true profile is the single closest, 0.0 = farthest. Rewards a
    prediction that is specifically nearest its own ground truth (a dilution-robust retrieval metric)."""
    bank = np.asarray(truth_bank, float); p = np.asarray(pred, float).ravel()
    if bank.ndim != 2 or bank.shape[1] != p.size or len(bank) < 2:
        raise ValueError("NIR requires at least two feature-aligned candidates")
    if not isinstance(true_idx, (int, np.integer)) or not 0 <= true_idx < len(bank):
        raise ValueError("Invalid true_idx")
    if not np.isfinite(bank).all() or not np.isfinite(p).all():
        raise ValueError("NIR requires finite inputs")
    d = np.linalg.norm(bank - p, axis=1)
    # Average rank for exact ties: an uninformative all-tied bank scores 0.5.
    rank = (d < d[true_idx]).sum() + 0.5 * ((d == d[true_idx]).sum() - 1)
    return float(1.0 - rank / (len(d) - 1))


def drf(m_pred, m_pos, m_neg):
    """Dynamic Range Fraction = (m_pred − m_neg)/(m_pos − m_neg). Works for any metric value as long as
    m_pos (positive control / held-out replicate) and m_neg (negative control / mean baseline) are the
    metric computed the SAME way. 1 ≈ as good as the replicate ceiling; 0 ≈ no better than the null."""
    denom = m_pos - m_neg
    return float((m_pred - m_neg) / denom) if abs(denom) > 1e-12 else float("nan")


def calibrated_report(pred, truth, truth_bank=None, true_idx=None, pos_ctrl=None, neg_ctrl=None):
    """One-shot: naive + calibrated metrics for a single Δ-prediction, with DRF when controls are given.
    pos_ctrl/neg_ctrl are Δ-vectors (a held-out replicate of `truth`, and the mean/zero baseline)."""
    w = deg_weights(truth)
    out = {
        "mse": wmse(pred, truth, np.ones_like(np.asarray(truth, float).ravel())),  # naive (equal weight)
        "pearson": weighted_rho(pred, truth, np.ones_like(np.asarray(truth, float).ravel())),
        "wmse": wmse(pred, truth, w), "weighted_rho": weighted_rho(pred, truth, w),
    }
    if truth_bank is not None and true_idx is not None:
        out["nir"] = nir(pred, truth_bank, true_idx)
    if pos_ctrl is not None and neg_ctrl is not None:
        # DRF on weighted_rho (higher-better): how far from mean-baseline toward the replicate ceiling
        m_pos = weighted_rho(pos_ctrl, truth, w); m_neg = weighted_rho(neg_ctrl, truth, w)
        out["drf_weighted_rho"] = drf(out["weighted_rho"], m_pos, m_neg)
        out["pos_ctrl_weighted_rho"] = m_pos; out["neg_ctrl_weighted_rho"] = m_neg
    return out


if __name__ == "__main__":  # self-test
    rng = np.random.RandomState(0)
    truth = rng.randn(200); truth[:10] *= 8          # 10 strong DEGs + noise
    perfect = truth.copy()
    noisy = truth + 0.3 * rng.randn(200)
    mean_base = np.zeros(200)
    bank = np.vstack([truth] + [rng.randn(200) for _ in range(9)])
    assert abs(wmse(perfect, truth)) < 1e-9, "perfect WMSE should be 0"
    assert abs(weighted_rho(perfect, truth) - 1.0) < 1e-9, "perfect weighted_rho should be 1"
    assert nir(perfect, bank, 0) == 1.0, "perfect NIR should be 1"
    assert drf(weighted_rho(perfect, truth), weighted_rho(perfect, truth), weighted_rho(mean_base, truth)) == 1.0
    r = calibrated_report(noisy, truth, bank, 0, pos_ctrl=truth + 0.1 * rng.randn(200), neg_ctrl=mean_base)
    print("self-test PASS; noisy report:", {k: round(v, 3) for k, v in r.items()})
