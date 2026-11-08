"""Verbatim copies of pilot 4 metric/baseline functions (p4eval.spear, ranks_metrics, corr, gp_post) so pilot 5 scoring needs no torch. test_p5metrics.py asserts the source text is identical to pilot 4's."""
import numpy as np
from scipy.stats import rankdata


def spear(a, b):
    if np.ptp(a) == 0 or np.ptp(b) == 0: return 0.0
    ra, rb = rankdata(a), rankdata(b); ra -= ra.mean(); rb -= rb.mean(); d = np.sqrt((ra * ra).sum() * (rb * rb).sum()); return float((ra * rb).sum() / d) if d > 0 else 0.0


def ranks_metrics(pred, truth, gain):
    nq = len(truth); order = np.argsort(-pred, kind="stable"); ntop = max(1, int(np.ceil(0.1 * nq)))
    ideal = np.sort(gain)[::-1][:10]; disc = 1.0 / np.log2(np.arange(2, 2 + min(10, nq)))
    ndcg = float((gain[order[:10]] * disc).sum() / max((ideal * disc).sum(), 1e-9))
    tt = set(np.argsort(-truth, kind="stable")[:ntop]); rec = len(tt & set(order[:ntop])) / ntop
    return spear(pred, truth), ndcg, rec


def corr(prior_q, prior_s, y_s, Sqs, q, lam, b=1.0):
    r = (y_s - y_s.mean()) - b * (prior_s - prior_s.mean()); w = Sqs ** q
    return b * prior_q + (w @ r) / (w.sum(1) + lam)


def gp_post(Sss, Sqs, y, sig2=1.5 ** 2, noise=0.5 ** 2, mean0=7.5):
    m = y.mean(); K = sig2 * Sss + noise * np.eye(len(y)); Kq = sig2 * Sqs
    try: mu = m + Kq @ np.linalg.solve(K, y - m); v = sig2 - np.einsum("ij,ji->i", Kq, np.linalg.solve(K, Kq.T))
    except np.linalg.LinAlgError: mu = np.full(Sqs.shape[0], m); v = np.full(Sqs.shape[0], sig2)
    return mu, np.sqrt(np.clip(v, 1e-6, None))


