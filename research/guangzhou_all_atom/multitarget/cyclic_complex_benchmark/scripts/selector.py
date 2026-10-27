"""Our pose selector for cyclic-peptide co-folding samples (method S in PREREG.md).

Idea: given N samples of one complex, pick the one most likely to be native-like using ONLY ground-truth-free evidence.
Design choices (fixed BEFORE Stage B data exist; made after the 26-complex pilot):
  1. WITHIN-COMPLEX normalisation: every feature is converted to a z-score / rank among the N samples of the SAME complex. Absolute confidences are not
     comparable across receptors; relative standing within a complex is. (This is what lets a selector trained on one set of receptors transfer.)
  2. Features = model confidences (ipTM, pTM, iplddt, pae...), ring-closure geometry, clash/contact terms, and CONSENSUS (how many other samples place the
     peptide in the same pose: cons_mean_rmsd, cons_nbr, cons_largest_cluster).
  3. Model = L2 logistic regression on the within-complex features predicting 'sample is acceptable' (DockQ >= thr); the pick is argmax of the score within a complex.
Ground-truth columns (dockq*, capri*, fnat, irmsd, lrmsd) are NEVER features — enforced by `assert_no_gt_columns` (an early exploratory screen on the pilot accidentally let irmsd/lrmsd through).
"""
import math
import numpy as np

GT_PREFIXES = ("dockq", "capri", "fnat", "irmsd", "lrmsd", "dockq_error")
FEATURES = ["confidence_score", "ptm", "iptm", "protein_iptm", "ligand_iptm", "complex_plddt", "complex_iplddt", "complex_pde", "complex_ipde",
            "iptm_pep_rec", "contact_density", "n_contact_pairs", "clash_count", "min_pep_rec_dist", "pep_plddt", "if_plddt", "pae_if", "pae_pep_to_rec",
            "ring_bond_dev_max", "ring_bond_dev_sum", "ring_angle_dev_sum", "ring_omega_dev", "ring_strain", "cons_mean_rmsd", "cons_nbr", "cons_largest_cluster"]


def assert_no_gt_columns(cols):
    bad = [c for c in cols if c.startswith(GT_PREFIXES) or c in ("irmsd", "lrmsd")]
    assert not bad, f"ground-truth columns used as features: {bad}"


def _num(x):
    return float(x) if isinstance(x, (int, float)) and not isinstance(x, bool) and not (isinstance(x, float) and math.isnan(x)) else float("nan")


def within_complex_features(rows, feats=FEATURES):
    """rows: list of dicts for ONE complex -> (n_samples, n_feats) z-scores within the complex (constant/NaN columns -> 0)."""
    assert_no_gt_columns(feats)
    X = np.array([[_num(r.get(f)) for f in feats] for r in rows], dtype=float)
    out = np.zeros_like(X)
    for j in range(X.shape[1]):
        col = X[:, j]; ok = ~np.isnan(col)
        if ok.sum() >= 2 and np.nanstd(col) > 1e-12:
            out[ok, j] = (col[ok] - np.nanmean(col)) / np.nanstd(col)
    return out


def build(rows_by_complex, thr=0.23, feats=FEATURES):
    Xs, ys, gs = [], [], []
    for cid, rows in rows_by_complex.items():
        rows = [r for r in rows if r.get("dockq") is not None]
        if len(rows) < 3:
            continue
        Xs.append(within_complex_features(rows, feats)); ys += [int(r["dockq"] >= thr) for r in rows]; gs += [cid] * len(rows)
    return np.vstack(Xs), np.array(ys), np.array(gs)


class Selector:
    def __init__(self, C=0.3, feats=FEATURES, mixed_only=False):
        from sklearn.linear_model import LogisticRegression
        self.feats = feats; self.mixed_only = mixed_only; self.m = LogisticRegression(C=C, max_iter=2000)  # L2 is the default
        self.trivial = None

    def fit(self, rows_by_complex, thr=0.23):
        if self.mixed_only:      # amendment A6: a complex whose samples all succeed (or all fail) has no within-complex ranking information
            rows_by_complex = {c: rs for c, rs in rows_by_complex.items() if 0 < sum(r["dockq"] >= thr for r in rs) < len(rs)}
            if not rows_by_complex:
                self.trivial = True; return self
        X, y, _ = build(rows_by_complex, thr, self.feats)
        if y.min() == y.max():                       # no signal to learn (all/none acceptable) -> behave like default ranking
            self.trivial = True; return self
        self.m.fit(X, y); self.trivial = False; return self

    def pick(self, rows):
        """index of the selected sample within `rows` (one complex)."""
        if self.trivial:
            return int(np.argmax([_num(r.get("confidence_score")) if not math.isnan(_num(r.get("confidence_score"))) else -1e9 for r in rows]))
        return int(np.argmax(self.m.decision_function(within_complex_features(rows, self.feats))))

    def coef(self):
        return dict(sorted(zip(self.feats, self.m.coef_[0].round(3)), key=lambda kv: -abs(kv[1]))) if not self.trivial else {}
