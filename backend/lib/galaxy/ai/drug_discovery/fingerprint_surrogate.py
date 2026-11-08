"""
Fingerprint featuriser and Tanimoto-kernel Gaussian-process surrogate.

One featuriser instance is used for both the training compounds and the
virtual library, so fit and predict always share the same feature space.

Why a Tanimoto kernel: on sparse binary Morgan fingerprints a Euclidean
(RBF/Matern) kernel with a fitted length-scale collapses to its lower bound on
small campaigns -- the marginal likelihood prefers "every compound is
independent", the kernel becomes the identity matrix and every unseen
structure is predicted at the prior mean. The Tanimoto kernel has no
length-scale; the only fitted hyperparameter is the observation-noise level.

Small data are reported, not hidden: ``assess_discrimination`` says whether
the posterior can order any pair of candidates with confidence, and every
prediction carries a latent standard deviation.
"""
import logging
import math
import warnings
from typing import Optional

import numpy as np
from scipy.linalg import solve_triangular
from scipy.stats import norm
from sklearn.exceptions import ConvergenceWarning
from sklearn.gaussian_process import GaussianProcessRegressor
from sklearn.gaussian_process.kernels import ConstantKernel, Kernel, WhiteKernel

try:
    from rdkit import Chem, RDLogger
    from rdkit.Chem import rdFingerprintGenerator
    _RDKIT_AVAILABLE = True
except ImportError:
    _RDKIT_AVAILABLE = False

log = logging.getLogger(__name__)

FINGERPRINT_RADIUS = 2
FINGERPRINT_BITS = 2048

# Noise is fitted on standardised labels (unit variance): 1.0 means the whole
# label variance is attributed to noise, i.e. structure explains nothing.
NOISE_BOUNDS = (1e-4, 1.0)
NOISE_INIT = 0.1

# A candidate pair counts as "ordered" when the posterior probability that the
# higher-mean compound is truly better reaches this level.
DISCRIMINATION_PROBABILITY = 0.95
# Above this size the pairwise check uses the highest- and lowest-mean
# candidates (the pairs most likely to be separable) to bound memory.
DISCRIMINATION_MAX_CANDIDATES = 500

# Below this many training compounds the fitted noise level rests on too few
# points to be trusted, whatever the posterior says.
SMALL_TRAINING_SET = 10


# ---------------------------------------------------------------------------
# Featurisation
# ---------------------------------------------------------------------------

class MorganFeaturizer:
    """Binary Morgan fingerprints."""

    def __init__(self, radius: int = FINGERPRINT_RADIUS, n_bits: int = FINGERPRINT_BITS):
        if not _RDKIT_AVAILABLE:
            raise ImportError(
                "RDKit is required to featurise campaign compounds. "
                "Install it with: pip install rdkit"
            )
        self.radius = radius
        self.n_bits = n_bits
        self._generator = rdFingerprintGenerator.GetMorganGenerator(radius=radius, fpSize=n_bits)

    @property
    def signature(self) -> dict:
        return {"type": "morgan_bits", "radius": self.radius, "n_bits": self.n_bits}

    @staticmethod
    def mol(smiles: str):
        if not smiles:
            return None
        RDLogger.DisableLog("rdApp.*")
        try:
            return Chem.MolFromSmiles(smiles)
        finally:
            RDLogger.EnableLog("rdApp.*")

    def canonical(self, smiles: str) -> Optional[str]:
        m = self.mol(smiles)
        return Chem.MolToSmiles(m) if m is not None else None

    def featurise(self, smiles_list: list) -> "tuple[np.ndarray, list[int]]":
        """Return (N x n_bits float matrix, indices of unparsable SMILES).

        Rows for unparsable SMILES are all-zero; callers must exclude them.
        """
        X = np.zeros((len(smiles_list), self.n_bits), dtype=np.float64)
        invalid: list[int] = []
        for i, smi in enumerate(smiles_list):
            m = self.mol(smi)
            if m is None:
                invalid.append(i)
                continue
            X[i] = self._generator.GetFingerprintAsNumPy(m)
        return X, invalid


def tanimoto_similarity(A: "np.ndarray", B: "np.ndarray") -> "np.ndarray":
    """Pairwise Tanimoto similarity between rows of two binary matrices."""
    A = np.asarray(A, dtype=np.float64)
    B = np.asarray(B, dtype=np.float64)
    inter = A @ B.T
    union = A.sum(axis=1)[:, None] + B.sum(axis=1)[None, :] - inter
    safe = np.where(union > 0, union, 1.0)
    return np.where(union > 0, inter / safe, 0.0)


# ---------------------------------------------------------------------------
# Kernel
# ---------------------------------------------------------------------------

class TanimotoKernel(Kernel):
    """k(x, y) = |x AND y| / |x OR y| on binary fingerprints (positive definite).

    Parameter-free, so there is no length-scale to collapse.
    """

    def __init__(self):
        pass

    def __call__(self, X, Y=None, eval_gradient=False):
        X = np.atleast_2d(X)
        if Y is None:
            K = tanimoto_similarity(X, X)
            np.fill_diagonal(K, 1.0)
        else:
            if eval_gradient:
                raise ValueError("Gradient can only be evaluated when Y is None.")
            K = tanimoto_similarity(X, np.atleast_2d(Y))
        if eval_gradient:
            return K, np.empty((X.shape[0], X.shape[0], 0))
        return K

    def diag(self, X):
        return np.ones(np.atleast_2d(X).shape[0])

    def is_stationary(self):
        return False

    def __repr__(self):
        return "Tanimoto()"


# ---------------------------------------------------------------------------
# Surrogate
# ---------------------------------------------------------------------------

class TanimotoGP:
    """GP regressor on fingerprints with explicit label standardisation.

    Kernel on standardised labels: 1.0 (fixed) * Tanimoto + White(noise).
    ``predict`` returns latent-function (noise-free) mean / std in the
    caller's label units, so the uncertainty describes the predicted score.
    """

    def __init__(self, random_state: Optional[int] = None, n_restarts_optimizer: int = 2):
        self.random_state = random_state
        self.n_restarts_optimizer = n_restarts_optimizer
        self.fit_warnings: list[str] = []
        self.constant_labels = False

    def fit(self, X: "np.ndarray", y: "np.ndarray") -> "TanimotoGP":
        X = np.asarray(X, dtype=np.float64)
        y = np.asarray(y, dtype=np.float64).ravel()
        if X.shape[0] != y.shape[0]:
            raise ValueError(f"X has {X.shape[0]} rows but y has {y.shape[0]} labels")
        self._X_train = X
        self._y_mean = float(y.mean())
        std = float(y.std())
        self.constant_labels = not std > 0
        self._y_std = std if std > 0 else 1.0
        y_std = (y - self._y_mean) / self._y_std

        kernel = (ConstantKernel(1.0, constant_value_bounds="fixed") * TanimotoKernel()
                  + WhiteKernel(noise_level=NOISE_INIT, noise_level_bounds=NOISE_BOUNDS))
        self.gp_ = GaussianProcessRegressor(
            kernel=kernel,
            alpha=1e-8,
            normalize_y=False,
            n_restarts_optimizer=self.n_restarts_optimizer,
            random_state=self.random_state,
        )
        self.fit_warnings = []
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always", ConvergenceWarning)
            self.gp_.fit(X, y_std)
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
        return int(self._X_train.shape[1])

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
        if X.shape[1] != self._X_train.shape[1]:
            raise ValueError(
                f"feature dimension mismatch: surrogate fitted on {self._X_train.shape[1]} "
                f"features, asked to predict on {X.shape[1]}"
            )
        signal = self.gp_.kernel_.k1
        Ks = signal(X, self._X_train)
        mean = Ks @ self.gp_.alpha_
        V = solve_triangular(self.gp_.L_, Ks.T, lower=True, check_finite=False)
        if full_cov:
            cov = signal(X) - V.T @ V
            return mean, (cov + cov.T) / 2.0
        var = signal.diag(X) - np.einsum("ij,ij->j", V, V)
        return mean, np.maximum(var, 0.0)

    def predict(self, X: "np.ndarray", return_std: bool = False):
        mean, var = self._latent(X, full_cov=False)
        mu = mean * self._y_std + self._y_mean
        if return_std:
            return mu, np.sqrt(var) * self._y_std
        return mu

    def predict_cov(self, X: "np.ndarray") -> "tuple[np.ndarray, np.ndarray]":
        mean, cov = self._latent(X, full_cov=True)
        return mean * self._y_std + self._y_mean, cov * self._y_std ** 2


# ---------------------------------------------------------------------------
# Discrimination and acquisition
# ---------------------------------------------------------------------------

def pairwise_order_probability(mean: "np.ndarray", cov: "np.ndarray") -> "np.ndarray":
    """P[f_i > f_j] under the joint posterior, for every ordered pair (i, j)."""
    d = mean[:, None] - mean[None, :]
    v = np.diag(cov)
    sd = np.sqrt(np.maximum(v[:, None] + v[None, :] - 2.0 * cov, 0.0))
    exact = sd <= 1e-12
    p = norm.cdf(d / np.where(exact, 1.0, sd))
    # Zero posterior variance of the difference: the order is certain unless
    # the means coincide.
    p = np.where(exact, np.where(d > 0, 1.0, np.where(d < 0, 0.0, 0.5)), p)
    np.fill_diagonal(p, 0.5)
    return p


def assess_discrimination(model: TanimotoGP, X: "np.ndarray",
                          threshold: float = DISCRIMINATION_PROBABILITY) -> dict:
    """Can the posterior confidently order at least one pair of candidates?"""
    n = X.shape[0]
    result = {"can_discriminate": False, "max_pairwise_order_probability": None,
              "threshold": threshold, "n_candidates_compared": int(n)}
    if model.constant_labels:
        result["reason"] = "all training labels are identical"
        return result
    if n < 2:
        result["reason"] = "fewer than two candidates"
        return result
    idx = np.arange(n)
    if n > DISCRIMINATION_MAX_CANDIDATES:
        order = np.argsort(model.predict(X), kind="stable")
        half = DISCRIMINATION_MAX_CANDIDATES // 2
        idx = np.concatenate([order[:half], order[-half:]])
    mean, cov = model.predict_cov(X[idx])
    max_p = float(pairwise_order_probability(mean, cov).max())
    result["max_pairwise_order_probability"] = round(max_p, 4)
    result["n_candidates_compared"] = int(len(idx))
    if max_p >= threshold:
        result["can_discriminate"] = True
        result["reason"] = f"at least one candidate pair is ordered with P >= {threshold}"
    else:
        result["reason"] = (f"no candidate pair is ordered with P >= {threshold} "
                            f"(best P = {max_p:.3f}); predicted differences are within "
                            "posterior uncertainty")
    return result


def expected_improvement(mu: "np.ndarray", sigma: "np.ndarray", best: float) -> "np.ndarray":
    """Analytic expected improvement (maximisation) over the incumbent ``best``."""
    mu = np.asarray(mu, dtype=np.float64)
    sigma = np.asarray(sigma, dtype=np.float64)
    gain = mu - best
    pos = sigma > 0
    z = gain / np.where(pos, sigma, 1.0)
    ei = np.where(pos, gain * norm.cdf(z) + sigma * norm.pdf(z), np.maximum(gain, 0.0))
    return np.maximum(ei, 0.0)


def expected_hypervolume_improvement(
    mu: "np.ndarray",
    sigma: "np.ndarray",
    front: "np.ndarray",
    reference_point: "np.ndarray",
    rng: "np.random.RandomState",
    n_posterior_samples: int = 32,
    n_mc_points: int = 1024,
) -> "np.ndarray":
    """Monte-Carlo expected hypervolume improvement (all objectives maximised).

    Common random numbers: every candidate uses the same standard-normal draws
    and the same box points, so candidates with identical posteriors receive
    identical EHVI and MC noise cannot create a ranking. The sampling box
    extends past the observed front so improvements beyond it are counted.
    """
    n_cand, n_obj = mu.shape
    z = rng.standard_normal((n_posterior_samples, n_obj))
    samples = mu[:, None, :] + sigma[:, None, :] * z[None, :, :]
    upper = np.maximum(front.max(axis=0), samples.reshape(-1, n_obj).max(axis=0))
    upper = np.maximum(upper, reference_point + 1e-9)
    box = reference_point + rng.uniform(size=(n_mc_points, n_obj)) * (upper - reference_point)
    volume = float(np.prod(upper - reference_point))
    dominated = np.zeros(n_mc_points, dtype=bool)
    for p in front:
        dominated |= np.all(box <= p, axis=1)
    free = ~dominated
    ehvi = np.zeros(n_cand)
    for i in range(n_cand):
        gain = np.all(box[None, :, :] <= samples[i][:, None, :], axis=2) & free[None, :]
        ehvi[i] = gain.mean() * volume
    return ehvi
