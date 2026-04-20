"""
BioMate Applicability Domain (AD) Checker — Phase 1 CRO Readiness

Determines whether a query compound falls within the applicability domain
of BioMate's QSAR/PBPK models using:

  1. Hat-matrix leverage (Tropsha/Roy approach) — detects structural outliers
     relative to the training set using Morgan fingerprints.

  2. GP posterior confidence intervals — 95% CI from GaussianProcessRegressor's
     posterior standard deviation (already computed in BayesianOptimizer).

AD status is reported per compound in every /propose response and in
model validation reports.

References:
  Tropsha A et al. QSAR & Comb. Sci. 2003.
  Roy K et al. Chemom. Intell. Lab. Syst. 2015.
"""

import logging
import math
from typing import Optional

log = logging.getLogger(__name__)

try:
    import numpy as np
    _NUMPY_AVAILABLE = True
except ImportError:
    _NUMPY_AVAILABLE = False
    np = None  # type: ignore[assignment]

try:
    from rdkit import Chem
    from rdkit.Chem import AllChem
    _RDKIT_AVAILABLE = True
except ImportError:
    _RDKIT_AVAILABLE = False

from pydantic import BaseModel


# ---------------------------------------------------------------------------
# Pydantic output
# ---------------------------------------------------------------------------

class ADResult(BaseModel):
    smiles: str
    ad_status: str                    # "in_domain" | "out_of_domain" | "unknown"
    leverage: Optional[float]         # hat matrix h_i
    leverage_threshold: Optional[float]  # h* = 3p/n
    confidence_interval_95: Optional[tuple[float, float]]  # (lower, upper) from GP
    predicted_mean: Optional[float]
    warnings: list[str]


# ---------------------------------------------------------------------------
# Applicability Domain Checker
# ---------------------------------------------------------------------------

class ApplicabilityDomainChecker:
    """
    Hat-matrix leverage AD checker for QSAR/ML models.

    Usage:
        from rdkit import Chem
        from rdkit.Chem import AllChem

        # Build training fingerprint matrix
        training_fps = np.vstack([
            np.array(AllChem.GetMorganFingerprintAsBitVect(Chem.MolFromSmiles(s), 2, 2048))
            for s in training_smiles
        ])
        checker = ApplicabilityDomainChecker(training_fps)

        # Check a query compound
        query_fp = np.array(AllChem.GetMorganFingerprintAsBitVect(
            Chem.MolFromSmiles(query_smiles), 2, 2048
        ))
        result = checker.check(query_smiles, query_fp)
    """

    def __init__(
        self,
        training_fps: "np.ndarray",
        leverage_factor: float = 3.0,
    ):
        """
        Args:
            training_fps: shape (N, F) — Morgan fingerprint matrix for training set.
            leverage_factor: multiplier for mean leverage threshold (default 3).
                             Compound is out-of-domain if h_i > leverage_factor × h̄.
        """
        if not _NUMPY_AVAILABLE:
            raise ImportError("numpy is required for ApplicabilityDomainChecker")

        self.leverage_factor = leverage_factor
        self._n, self._p = training_fps.shape
        self._X_train = training_fps.astype(float)

        # Hat matrix diagonal: h_i = x_i^T (X^T X)^+ x_i
        # Use pseudoinverse for robustness with highly sparse bit vectors
        XtX = self._X_train.T @ self._X_train
        self._XtX_pinv = np.linalg.pinv(XtX)

        # Training leverage vector
        h_train = np.array([
            float(self._X_train[i] @ self._XtX_pinv @ self._X_train[i])
            for i in range(self._n)
        ])
        self._h_mean = float(h_train.mean())

        # Threshold: h* = leverage_factor × mean(h_train)
        # Standard formula h* = 3p/n is equivalent when XtX is full rank
        self._h_threshold = self.leverage_factor * self._h_mean
        if self._h_threshold == 0:
            # Fallback to theoretical threshold for binary fingerprints
            self._h_threshold = 3.0 * self._p / max(self._n, 1)

    @property
    def leverage_threshold(self) -> float:
        return self._h_threshold

    def compute_leverage(self, query_fp: "np.ndarray") -> float:
        """Return the hat-matrix leverage for a single query fingerprint."""
        x = query_fp.astype(float)
        return float(x @ self._XtX_pinv @ x)

    def check(
        self,
        smiles: str,
        query_fp: "np.ndarray",
        gp_mean: Optional[float] = None,
        gp_std: Optional[float] = None,
    ) -> ADResult:
        """
        Assess applicability domain for a single compound.

        Args:
            smiles: SMILES string (for labelling only).
            query_fp: shape (F,) Morgan fingerprint.
            gp_mean: optional GP posterior mean prediction.
            gp_std: optional GP posterior standard deviation.

        Returns:
            ADResult with leverage, threshold, CI, and domain status.
        """
        warnings: list[str] = []

        h = self.compute_leverage(query_fp)
        in_domain_leverage = h <= self._h_threshold

        if not in_domain_leverage:
            warnings.append(
                f"Leverage h={h:.4f} exceeds threshold h*={self._h_threshold:.4f} "
                f"— compound may be structurally outside the training domain"
            )

        # 95% confidence interval from GP posterior std
        ci: Optional[tuple[float, float]] = None
        if gp_mean is not None and gp_std is not None and gp_std >= 0:
            half_width = 1.96 * gp_std
            ci = (
                round(max(0.0, gp_mean - half_width), 4),
                round(min(1.0, gp_mean + half_width), 4),
            )
            if gp_std > 0.25:
                warnings.append(
                    f"High GP uncertainty (σ={gp_std:.3f}) — prediction confidence is low"
                )

        ad_status = "in_domain" if in_domain_leverage else "out_of_domain"

        return ADResult(
            smiles=smiles,
            ad_status=ad_status,
            leverage=round(h, 6),
            leverage_threshold=round(self._h_threshold, 6),
            confidence_interval_95=ci,
            predicted_mean=round(gp_mean, 4) if gp_mean is not None else None,
            warnings=warnings,
        )

    def check_batch(
        self,
        smiles_list: list[str],
        fps: "np.ndarray",
        gp_means: Optional["np.ndarray"] = None,
        gp_stds: Optional["np.ndarray"] = None,
    ) -> list[ADResult]:
        """
        Batch applicability domain check.

        Args:
            smiles_list: list of SMILES strings.
            fps: shape (N, F) fingerprint matrix.
            gp_means: optional shape (N,) GP posterior means.
            gp_stds: optional shape (N,) GP posterior standard deviations.

        Returns:
            List of ADResult, one per compound.
        """
        results = []
        for i, smiles in enumerate(smiles_list):
            mean = float(gp_means[i]) if gp_means is not None else None
            std  = float(gp_stds[i])  if gp_stds  is not None else None
            results.append(self.check(smiles, fps[i], mean, std))
        return results

    @staticmethod
    def fingerprint_from_smiles(smiles: str, radius: int = 2, n_bits: int = 2048) -> Optional["np.ndarray"]:
        """
        Compute a Morgan fingerprint bit vector for a SMILES string.

        Returns None if the SMILES is invalid.
        """
        if not _RDKIT_AVAILABLE:
            log.warning("RDKit not available — cannot compute fingerprints for AD check")
            return None
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            log.warning("Invalid SMILES for AD check: %s", smiles)
            return None
        fp = AllChem.GetMorganFingerprintAsBitVect(mol, radius, nBits=n_bits)
        return np.array(fp, dtype=float)

    @classmethod
    def from_smiles_list(
        cls,
        training_smiles: list[str],
        radius: int = 2,
        n_bits: int = 2048,
        leverage_factor: float = 3.0,
    ) -> "ApplicabilityDomainChecker":
        """
        Convenience constructor: build an AD checker directly from SMILES.

        Compounds with invalid SMILES are silently skipped.
        """
        if not _NUMPY_AVAILABLE:
            raise ImportError("numpy required")

        fps = []
        for s in training_smiles:
            fp = cls.fingerprint_from_smiles(s, radius, n_bits)
            if fp is not None:
                fps.append(fp)

        if not fps:
            raise ValueError("No valid SMILES in training set — cannot build AD checker")

        X = np.vstack(fps)
        return cls(X, leverage_factor=leverage_factor)
