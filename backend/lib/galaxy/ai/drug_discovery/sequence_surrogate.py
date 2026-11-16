"""
Sequence featuriser + dense-feature Gaussian-process surrogate for the DMTA
loop on peptide and biologic (antibody / protein-binder) modalities.

Why a separate surrogate from fingerprint_surrogate.py:
  The small-molecule path uses a Tanimoto kernel on *sparse binary* Morgan
  fingerprints — an RBF/Matern kernel collapses there. Peptides and biologics
  are amino-acid SEQUENCES, which we featurise into a *dense, low-dimensional,
  physicochemically meaningful* descriptor vector (length, net charge, GRAVY
  hydrophobicity, aromaticity, isoelectric point, instability, AA-class
  fractions, 20-AA composition). On dense standardised features a Matern GP is
  the correct, well-behaved choice — it has a real length-scale and genuinely
  interpolates, so posterior uncertainty is informative for Bayesian selection.

Design contract: `SequenceGP` exposes the SAME interface as
`fingerprint_surrogate.TanimotoGP` (fit / predict(return_std) / predict_cov /
kernel_ / log_marginal_likelihood_value_ / noise_level / fit_warnings /
constant_labels / n_features_in_), so BayesianOptimizer, the acquisition and the
discrimination code consume it unchanged. The featuriser mirrors
`MorganFeaturizer` (featurise(list) -> (X, invalid_indices), signature()).

No heavy third-party deps: descriptors are computed from standard amino-acid
property tables in pure Python + numpy. Biopython is used only if available
(for a refined isoelectric point); otherwise a documented fallback is used.
"""
from __future__ import annotations

import math
import warnings
from dataclasses import dataclass
from typing import Optional

import numpy as np
# scipy / sklearn are imported lazily inside SequenceGP (the only sklearn user),
# mirroring fingerprint_surrogate's usage pattern: the module must import with
# numpy alone so the featuriser and applicability-domain code load even where the
# heavy GP stack is unavailable, and so Galaxy module-load never pulls sklearn.

NOISE_INIT = 0.1
NOISE_BOUNDS = (1e-5, 1.0)
LENGTH_SCALE_BOUNDS = (1e-2, 1e3)

# ── Amino-acid property tables (standard references) ────────────────────────
# Kyte & Doolittle hydropathy (1982).
_KD = {
    "A": 1.8, "R": -4.5, "N": -3.5, "D": -3.5, "C": 2.5, "Q": -3.5, "E": -3.5,
    "G": -0.4, "H": -3.2, "I": 4.5, "L": 3.8, "K": -3.9, "M": 1.9, "F": 2.8,
    "P": -1.6, "S": -0.8, "T": -0.7, "W": -0.9, "Y": -1.3, "V": 4.2,
}
# Side-chain pKa (Lehninger) for net-charge at a given pH.
_PKA_POS = {"K": 10.5, "R": 12.5, "H": 6.0}   # basic
_PKA_NEG = {"D": 3.65, "E": 4.25, "C": 8.3, "Y": 10.1}  # acidic
_N_TERM_PKA, _C_TERM_PKA = 9.0, 2.0
_AROMATIC = set("FWY")
_ALIPHATIC = set("AVLIMG")
_POLAR = set("STNQCY")
_CHARGED = set("DEKRH")
_TINY = set("AGCS")
# DIWV instability dipeptide weights are large; we use a cheap, bounded
# instability proxy (fraction of residues in the high-instability set P,E,S,Q,D)
# rather than the full Guruprasad table — enough signal for a GP feature.
_UNSTABLE = set("PESQD")
_AA20 = "ACDEFGHIKLMNPQRSTVWY"
_AA_INDEX = {a: i for i, a in enumerate(_AA20)}


def _clean_sequence(seq: str) -> str:
    """Uppercase, strip whitespace/gaps/stop; keep only canonical 20 AAs."""
    if not seq:
        return ""
    s = "".join(c for c in str(seq).upper() if c.isalpha())
    return "".join(c for c in s if c in _AA_INDEX)


def _net_charge(seq: str, ph: float = 7.0) -> float:
    pos = 1.0 / (1.0 + 10 ** (ph - _N_TERM_PKA))
    neg = 1.0 / (1.0 + 10 ** (_C_TERM_PKA - ph))
    for aa in seq:
        if aa in _PKA_POS:
            pos += 1.0 / (1.0 + 10 ** (ph - _PKA_POS[aa]))
        elif aa in _PKA_NEG:
            neg += 1.0 / (1.0 + 10 ** (_PKA_NEG[aa] - ph))
    return pos - neg


def _isoelectric_point(seq: str) -> float:
    """Bisection on net charge; refined by Biopython if present."""
    try:
        from Bio.SeqUtils.ProtParam import ProteinAnalysis  # type: ignore
        return float(ProteinAnalysis(seq).isoelectric_point())
    except Exception:
        lo, hi = 0.0, 14.0
        for _ in range(40):
            mid = (lo + hi) / 2.0
            if _net_charge(seq, mid) > 0:
                lo = mid
            else:
                hi = mid
        return (lo + hi) / 2.0


# Descriptor layout is fixed and shared across modalities so fit/predict always
# use the same feature space. Modalities differ only in which descriptors carry
# signal, which the GP's length-scales learn automatically.
_DESCRIPTOR_NAMES = (
    ["length", "net_charge", "charge_density", "gravy", "arom_frac",
     "aliphatic_frac", "polar_frac", "charged_frac", "tiny_frac",
     "unstable_frac", "pi"]
    + [f"aa_{a}" for a in _AA20]
)


def _descriptors(seq: str) -> Optional[np.ndarray]:
    s = _clean_sequence(seq)
    n = len(s)
    if n == 0:
        return None
    counts = np.zeros(20, dtype=np.float64)
    for aa in s:
        counts[_AA_INDEX[aa]] += 1.0
    comp = counts / n
    charge = _net_charge(s)
    feats = [
        float(n),
        charge,
        charge / n,
        float(np.mean([_KD[a] for a in s])),         # GRAVY
        sum(comp[_AA_INDEX[a]] for a in _AROMATIC),
        sum(comp[_AA_INDEX[a]] for a in _ALIPHATIC),
        sum(comp[_AA_INDEX[a]] for a in _POLAR),
        sum(comp[_AA_INDEX[a]] for a in _CHARGED),
        sum(comp[_AA_INDEX[a]] for a in _TINY),
        sum(comp[_AA_INDEX[a]] for a in _UNSTABLE),
        _isoelectric_point(s),
    ]
    return np.concatenate([np.asarray(feats, dtype=np.float64), comp])


# ── Featuriser ──────────────────────────────────────────────────────────────
class SequenceFeaturizer:
    """Amino-acid sequence -> dense physicochemical descriptor vector.

    One instance featurises both the observed sequences and the virtual library
    so fit and predict share a feature space. ``modality`` is recorded in the
    signature and may bias descriptor weighting in future; the feature layout is
    identical across modalities today (peptide vs biologic differ in sequence
    length regime, which the GP handles via its learned length-scales).
    """

    N_FEATURES = len(_DESCRIPTOR_NAMES)

    def __init__(self, modality: str = "peptide"):
        self.modality = modality

    def signature(self) -> dict:
        return {"featuriser": "sequence_descriptors_v1",
                "modality": self.modality,
                "n_features": self.N_FEATURES,
                "descriptors": list(_DESCRIPTOR_NAMES)}

    @staticmethod
    def canonical(seq: str) -> Optional[str]:
        s = _clean_sequence(seq)
        return s or None

    def featurise(self, sequences: list) -> "tuple[np.ndarray, list[int]]":
        """Return (X, invalid_indices). Rows for invalid sequences are zero and
        their indices are reported, mirroring MorganFeaturizer.featurise."""
        X = np.zeros((len(sequences), self.N_FEATURES), dtype=np.float64)
        invalid: list[int] = []
        for i, seq in enumerate(sequences):
            d = _descriptors(seq)
            if d is None:
                invalid.append(i)
            else:
                X[i] = d
        return X, invalid


# ── Surrogate ───────────────────────────────────────────────────────────────
class SequenceGP:
    """Matern Gaussian-process regressor on standardised dense descriptors.

    Drop-in for fingerprint_surrogate.TanimotoGP. Features are standardised
    (zero mean / unit variance per column, fitted on the training set) so the
    Matern length-scale is well conditioned; labels are standardised so the
    returned mean/std are in the caller's units.
    """

    def __init__(self, random_state: Optional[int] = None, n_restarts_optimizer: int = 2,
                 matern_nu: float = 2.5):
        self.random_state = random_state
        self.n_restarts_optimizer = n_restarts_optimizer
        self.matern_nu = matern_nu
        self.fit_warnings: list[str] = []
        self.constant_labels = False

    def _standardise_X(self, X: "np.ndarray", fit: bool) -> "np.ndarray":
        if fit:
            self._x_mean = X.mean(axis=0)
            std = X.std(axis=0)
            self._x_std = np.where(std > 1e-12, std, 1.0)
        return (X - self._x_mean) / self._x_std

    def fit(self, X: "np.ndarray", y: "np.ndarray") -> "SequenceGP":
        X = np.atleast_2d(np.asarray(X, dtype=np.float64))
        y = np.asarray(y, dtype=np.float64).ravel()
        if X.shape[0] != y.shape[0]:
            raise ValueError(f"X has {X.shape[0]} rows but y has {y.shape[0]} labels")
        self._n_features = int(X.shape[1])
        Xs = self._standardise_X(X, fit=True)
        self._X_train = Xs
        self._y_mean = float(y.mean())
        std = float(y.std())
        self.constant_labels = not std > 0
        self._y_std = std if std > 0 else 1.0
        y_std = (y - self._y_mean) / self._y_std

        from sklearn.exceptions import ConvergenceWarning
        from sklearn.gaussian_process import GaussianProcessRegressor
        from sklearn.gaussian_process.kernels import ConstantKernel, Matern, WhiteKernel

        n_dim = Xs.shape[1]
        kernel = (
            ConstantKernel(1.0, constant_value_bounds="fixed")
            * Matern(length_scale=np.ones(n_dim), length_scale_bounds=LENGTH_SCALE_BOUNDS,
                     nu=self.matern_nu)
            + WhiteKernel(noise_level=NOISE_INIT, noise_level_bounds=NOISE_BOUNDS)
        )
        self.gp_ = GaussianProcessRegressor(
            kernel=kernel, alpha=1e-10, normalize_y=False,
            n_restarts_optimizer=self.n_restarts_optimizer, random_state=self.random_state,
        )
        self.fit_warnings = []
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always", ConvergenceWarning)
            self.gp_.fit(Xs, y_std)
        for w in caught:
            if issubclass(w.category, ConvergenceWarning):
                self.fit_warnings.append(str(w.message))
            else:
                warnings.warn_explicit(w.message, w.category, w.filename, w.lineno)
        return self

    @property
    def kernel_(self):
        return self.gp_.kernel_

    @property
    def n_features_in_(self) -> int:
        return self._n_features

    @property
    def noise_level(self) -> float:
        return float(self.gp_.kernel_.k2.noise_level)

    @property
    def noise_at_upper_bound(self) -> bool:
        return math.isclose(self.noise_level, NOISE_BOUNDS[1], rel_tol=1e-3)

    @property
    def log_marginal_likelihood_value_(self) -> float:
        return float(self.gp_.log_marginal_likelihood_value_)

    def _latent(self, X: "np.ndarray", full_cov: bool):
        X = np.atleast_2d(np.asarray(X, dtype=np.float64))
        if X.shape[1] != self._n_features:
            raise ValueError(
                f"feature dimension mismatch: surrogate fitted on {self._n_features} "
                f"features, asked to predict on {X.shape[1]}"
            )
        from scipy.linalg import solve_triangular
        Xs = self._standardise_X(X, fit=False)
        signal = self.gp_.kernel_.k1
        Ks = signal(Xs, self._X_train)
        mean = Ks @ self.gp_.alpha_
        V = solve_triangular(self.gp_.L_, Ks.T, lower=True, check_finite=False)
        if full_cov:
            cov = signal(Xs) - V.T @ V
            return mean.ravel(), (cov + cov.T) / 2.0
        var = signal.diag(Xs) - np.einsum("ij,ij->j", V, V)
        return mean.ravel(), np.maximum(var, 0.0)

    def predict(self, X: "np.ndarray", return_std: bool = False):
        mean, var = self._latent(X, full_cov=False)
        mu = mean * self._y_std + self._y_mean
        if return_std:
            return mu, np.sqrt(var) * self._y_std
        return mu

    def predict_cov(self, X: "np.ndarray") -> "tuple[np.ndarray, np.ndarray]":
        mean, cov = self._latent(X, full_cov=True)
        return mean * self._y_std + self._y_mean, cov * self._y_std ** 2


# ── Applicability domain (feature-space neighbourhood) ──────────────────────
@dataclass
class SequenceADResult:
    sequence: str
    in_domain: bool
    nn_distance: float
    threshold: float


class SequenceApplicabilityDomain:
    """Flags query sequences far from the training set in standardised feature
    space (mean + k*std of training nearest-neighbour distances). A proposal
    outside the domain is an extrapolation and should be treated with caution —
    the parallel of the fingerprint-leverage AD on the small-molecule path.
    """

    def __init__(self, k_sigma: float = 3.0):
        self.k_sigma = k_sigma

    def fit(self, X_train: "np.ndarray") -> "SequenceApplicabilityDomain":
        X = np.atleast_2d(np.asarray(X_train, dtype=np.float64))
        self._mean = X.mean(axis=0)
        std = X.std(axis=0)
        self._std = np.where(std > 1e-12, std, 1.0)
        Xs = (X - self._mean) / self._std
        self._Xs = Xs
        # training nearest-neighbour distances (exclude self)
        nn = []
        for i in range(Xs.shape[0]):
            d = np.linalg.norm(Xs - Xs[i], axis=1)
            d[i] = np.inf
            nn.append(float(np.min(d)) if Xs.shape[0] > 1 else 0.0)
        nn = np.asarray(nn)
        self._threshold = float(nn.mean() + self.k_sigma * nn.std()) if len(nn) else float("inf")
        return self

    def check(self, X_query: "np.ndarray", sequences: list) -> list:
        Xq = (np.atleast_2d(np.asarray(X_query, dtype=np.float64)) - self._mean) / self._std
        out = []
        for i in range(Xq.shape[0]):
            d = float(np.min(np.linalg.norm(self._Xs - Xq[i], axis=1)))
            out.append(SequenceADResult(
                sequence=sequences[i] if i < len(sequences) else "",
                in_domain=d <= self._threshold, nn_distance=d, threshold=self._threshold))
        return out
