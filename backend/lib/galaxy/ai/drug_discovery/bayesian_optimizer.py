"""
Multi-objective Bayesian optimisation for BioMate drug discovery campaigns.

Fits a Gaussian-process surrogate per objective, then proposes the next
synthesis batch via expected hypervolume improvement + diversity penalty,
closing the DMTA (Design–Make–Test–Analyse) loop.
"""
import json
import logging
import sqlite3
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

log = logging.getLogger(__name__)

try:
    import numpy as np
    _NUMPY_AVAILABLE = True
except ImportError:
    _NUMPY_AVAILABLE = False
    np = None  # type: ignore[assignment]

try:
    from sklearn.gaussian_process import GaussianProcessRegressor
    from sklearn.gaussian_process.kernels import Matern
    from sklearn.preprocessing import MinMaxScaler
    _SKLEARN_AVAILABLE = True
except ImportError:
    _SKLEARN_AVAILABLE = False

try:
    from rdkit import Chem
    from rdkit.Chem import AllChem, DataStructs
    _RDKIT_AVAILABLE = True
except ImportError:
    _RDKIT_AVAILABLE = False


# ---------------------------------------------------------------------------
# Data containers
# ---------------------------------------------------------------------------

@dataclass
class CampaignDataset:
    """Holds all observed data for one campaign round."""
    compound_ids: list[str]
    smiles_list: list[str]
    features: "np.ndarray"                  # shape N×F
    objectives: dict[str, "np.ndarray"]     # e.g. {'potency': array, ...}
    objective_directions: dict[str, str]    # 'maximize' or 'minimize'


@dataclass
class RoundProposal:
    """Output of a single BO proposal round."""
    campaign_id: str
    round_number: int
    proposed_compounds: list[str]           # SMILES strings
    scores: dict[str, list[float]]          # {objective: [score per compound]}
    acquisition_values: list[float]
    pareto_front_smiles: list[str]
    diversity_score: float
    timestamp: str


# ---------------------------------------------------------------------------
# Optimizer
# ---------------------------------------------------------------------------

class BayesianOptimizer:
    """
    Multi-objective Bayesian optimizer for drug discovery campaigns.

    Maintains one GP surrogate per objective.  All objectives are internally
    normalised to [0, 1] with 'higher = better' polarity so that HVI and
    Pareto logic are consistent regardless of the original direction.
    """

    def __init__(
        self,
        campaign_id: str,
        db_path: str = "galaxy_ai_tools.db",
        n_initial: int = 16,
    ):
        if not _NUMPY_AVAILABLE:
            raise ImportError(
                "numpy is required for BayesianOptimizer. "
                "Install it with: pip install numpy"
            )
        if not _SKLEARN_AVAILABLE:
            raise ImportError(
                "scikit-learn is required for BayesianOptimizer. "
                "Install it with: pip install scikit-learn"
            )

        self.campaign_id = campaign_id
        self.db_path = db_path
        self.n_initial = n_initial

        # Reproducible RNG seeded from the campaign id
        seed = abs(hash(campaign_id)) % (2 ** 31)
        self._rng = np.random.RandomState(seed)

        self._gp_models: dict[str, "GaussianProcessRegressor"] = {}
        self._scalers: dict[str, "MinMaxScaler"] = {}
        self._objective_directions: dict[str, str] = {}
        self._dataset: Optional[CampaignDataset] = None
        self._round_number: int = 0
        self._n_features: int = 2048  # updated after first fit()

        self._ensure_schema()

    # ------------------------------------------------------------------
    # Schema management
    # ------------------------------------------------------------------

    def _ensure_schema(self):
        """Create the bo_proposals table if it does not already exist."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS bo_proposals (
                    id                       INTEGER PRIMARY KEY AUTOINCREMENT,
                    campaign_id              TEXT NOT NULL,
                    round_number             INTEGER NOT NULL,
                    proposed_smiles          TEXT NOT NULL,
                    scores_json              TEXT NOT NULL,
                    acquisition_values_json  TEXT NOT NULL,
                    pareto_front_smiles_json TEXT NOT NULL,
                    diversity_score          REAL NOT NULL,
                    timestamp                TEXT NOT NULL
                )
            """)
            conn.commit()

    # ------------------------------------------------------------------
    # Featurisation
    # ------------------------------------------------------------------

    def _featurise(self, smiles_list: list[str]) -> "np.ndarray":
        """
        Convert SMILES to Morgan fingerprints (radius=2, nBits=2048).

        Falls back to seeded random vectors if RDKit is not available so that
        the rest of the pipeline remains functional for unit tests.
        """
        n = len(smiles_list)
        if _RDKIT_AVAILABLE:
            fps: list[np.ndarray] = []
            for smi in smiles_list:
                mol = Chem.MolFromSmiles(smi)
                if mol is None:
                    fps.append(np.zeros(2048, dtype=np.float64))
                    continue
                fp = AllChem.GetMorganFingerprintAsBitVect(mol, radius=2, nBits=2048)
                arr = np.zeros(2048, dtype=np.float32)
                DataStructs.ConvertToNumpyArray(fp, arr)
                fps.append(arr.astype(np.float64))
            return np.array(fps, dtype=np.float64)

        log.warning("RDKit not available; using seeded random vectors for featurisation.")
        seed = abs(hash(tuple(smiles_list[:5]))) % (2 ** 31)
        rng = np.random.RandomState(seed)
        return rng.rand(n, self._n_features)

    # ------------------------------------------------------------------
    # Pareto front
    # ------------------------------------------------------------------

    def _compute_pareto_front(self, scores: "np.ndarray") -> "np.ndarray":
        """
        Return a boolean mask identifying Pareto-dominant compounds.

        Assumes all columns are already oriented as 'higher = better'.
        Compound i is on the Pareto front if no other compound j satisfies
        scores[j] >= scores[i] on every objective and scores[j] > scores[i]
        on at least one.

        Args:
            scores: N×M array of (normalised, all-maximise) objective scores.

        Returns:
            Boolean array of length N.
        """
        n = scores.shape[0]
        is_pareto = np.ones(n, dtype=bool)
        for i in range(n):
            if not is_pareto[i]:
                continue
            for j in range(n):
                if i == j or not is_pareto[j]:
                    continue
                if np.all(scores[j] >= scores[i]) and np.any(scores[j] > scores[i]):
                    is_pareto[i] = False
                    break
        return is_pareto

    # ------------------------------------------------------------------
    # Hypervolume improvement (Monte Carlo)
    # ------------------------------------------------------------------

    def _hypervolume_improvement(
        self,
        candidate_scores: "np.ndarray",
        pareto_front: "np.ndarray",
        reference_point: "np.ndarray",
    ) -> "np.ndarray":
        """
        Approximate hypervolume improvement (HVI) for each candidate via MC.

        Samples 1 000 random points uniformly between reference_point and
        np.ones(n_obj) and estimates the fraction newly dominated after
        adding each candidate to the current Pareto front.

        Args:
            candidate_scores: N_cand × M array of candidate objective scores.
            pareto_front:     N_pareto × M array of current Pareto-front scores.
            reference_point:  M-dimensional nadir / reference point.

        Returns:
            N_cand array of approximate HVI values in [0, 1].
        """
        n_samples = 1000
        n_obj = candidate_scores.shape[1]

        # Guard: if reference_point == 1 everywhere, no volume to gain
        upper = np.ones(n_obj)
        if np.all(reference_point >= upper):
            return np.zeros(len(candidate_scores))

        mc_samples = self._rng.uniform(
            low=reference_point, high=upper, size=(n_samples, n_obj)
        )

        # Which MC samples are already dominated by the current Pareto front?
        dominated_by_front = np.zeros(n_samples, dtype=bool)
        for pf_point in pareto_front:
            dominated_by_front |= np.all(mc_samples <= pf_point, axis=1)

        hvi = np.zeros(len(candidate_scores))
        for i, cand in enumerate(candidate_scores):
            dominated_by_cand = np.all(mc_samples <= cand, axis=1)
            hvi[i] = (dominated_by_cand & ~dominated_by_front).sum() / n_samples

        return hvi

    # ------------------------------------------------------------------
    # Diversity helper
    # ------------------------------------------------------------------

    def _tanimoto_distance(self, fp_a: "np.ndarray", fp_b: "np.ndarray") -> float:
        """Binary Tanimoto distance between two binary fingerprint vectors."""
        a = fp_a.astype(bool)
        b = fp_b.astype(bool)
        intersection = np.logical_and(a, b).sum()
        union = np.logical_or(a, b).sum()
        if union == 0:
            return 0.0
        return 1.0 - float(intersection) / float(union)

    # ------------------------------------------------------------------
    # Fitting
    # ------------------------------------------------------------------

    def fit(self, dataset: CampaignDataset):
        """
        Fit one GP surrogate per objective using a Matérn-5/2 kernel.

        Each objective is normalised to [0, 1].  Objectives with direction
        'minimize' are additionally flipped so that higher GP output always
        corresponds to a better compound.

        Args:
            dataset: Observed campaign data with feature matrix and objectives.
        """
        X = dataset.features  # N×F
        self._dataset = dataset
        self._objective_directions = dict(dataset.objective_directions)
        self._n_features = X.shape[1]

        for obj_name, y_raw in dataset.objectives.items():
            direction = dataset.objective_directions.get(obj_name, "maximize")

            scaler = MinMaxScaler()
            y_scaled = scaler.fit_transform(y_raw.reshape(-1, 1)).ravel()

            if direction == "minimize":
                y_scaled = 1.0 - y_scaled

            self._scalers[obj_name] = scaler

            kernel = Matern(nu=2.5)
            gp = GaussianProcessRegressor(
                kernel=kernel,
                n_restarts_optimizer=3,
                random_state=self._rng.randint(0, 2 ** 31),
                normalize_y=True,
            )
            gp.fit(X, y_scaled)
            self._gp_models[obj_name] = gp

        # Sync round counter with persisted proposals
        existing = self.load_proposals(self.campaign_id)
        self._round_number = len(existing)

        log.info(
            "BayesianOptimizer.fit: campaign=%s n_compounds=%d objectives=%s round=%d",
            self.campaign_id,
            len(dataset.compound_ids),
            list(dataset.objectives.keys()),
            self._round_number,
        )

    # ------------------------------------------------------------------
    # Proposal generation
    # ------------------------------------------------------------------

    def propose_next_round(
        self,
        virtual_library_smiles: list[str],
        n_propose: int = 10,
        diversity_weight: float = 0.2,
    ) -> RoundProposal:
        """
        Score the virtual library under the surrogate and select the best
        n_propose compounds using HVI acquisition + Tanimoto diversity penalty.

        Selection is greedy: at each step the compound maximising

            (1 - diversity_weight) * HVI
            + diversity_weight * min_tanimoto_dist_from_selected

        is chosen and added to the batch.

        Args:
            virtual_library_smiles: SMILES strings of candidate compounds.
            n_propose:              How many compounds to propose.
            diversity_weight:       Weight [0, 1] given to diversity term.

        Returns:
            RoundProposal with selected compounds and metadata.

        Raises:
            ValueError: If fewer than n_initial training observations exist.
        """
        if self._dataset is None:
            raise ValueError(
                f"Insufficient data: need at least {self.n_initial} observations "
                "to fit surrogate. Call fit() first."
            )
        n_obs = len(self._dataset.compound_ids)
        if n_obs < self.n_initial:
            raise ValueError(
                f"Insufficient data: need at least {self.n_initial} observations "
                f"to fit surrogate, but only {n_obs} are available."
            )

        obj_names = list(self._gp_models.keys())
        n_obj = len(obj_names)

        # Featurise virtual library
        X_lib = self._featurise(virtual_library_smiles)

        # GP mean predictions for each objective over the virtual library
        pred_scores = np.zeros((len(virtual_library_smiles), n_obj))
        for j, obj_name in enumerate(obj_names):
            mu, _ = self._gp_models[obj_name].predict(X_lib, return_std=True)
            pred_scores[:, j] = mu
        pred_scores = np.clip(pred_scores, 0.0, 1.0)

        # Current Pareto front from training observations
        train_preds = np.column_stack([
            np.clip(self._gp_models[obj_name].predict(self._dataset.features), 0.0, 1.0)
            for obj_name in obj_names
        ])
        pareto_mask_train = self._compute_pareto_front(train_preds)
        pareto_front_scores = train_preds[pareto_mask_train]

        reference_point = np.zeros(n_obj)
        hvi = self._hypervolume_improvement(pred_scores, pareto_front_scores, reference_point)

        # Greedy batch construction with diversity bonus
        selected_indices: list[int] = []
        selected_fps: list[np.ndarray] = []
        acq_values: list[float] = []
        remaining = list(range(len(virtual_library_smiles)))

        for _ in range(min(n_propose, len(virtual_library_smiles))):
            if not remaining:
                break

            best_idx: Optional[int] = None
            best_score = -np.inf

            for idx in remaining:
                diversity = (
                    min(self._tanimoto_distance(X_lib[idx], sfp) for sfp in selected_fps)
                    if selected_fps
                    else 1.0
                )
                combined = (1.0 - diversity_weight) * hvi[idx] + diversity_weight * diversity
                if combined > best_score:
                    best_score = combined
                    best_idx = idx

            selected_indices.append(best_idx)
            selected_fps.append(X_lib[best_idx])
            acq_values.append(float(best_score))
            remaining.remove(best_idx)

        proposed_smiles = [virtual_library_smiles[i] for i in selected_indices]

        scores_dict: dict[str, list[float]] = {
            obj_name: [float(pred_scores[i, j]) for i in selected_indices]
            for j, obj_name in enumerate(obj_names)
        }

        pareto_smiles = [
            self._dataset.smiles_list[i]
            for i, flag in enumerate(pareto_mask_train)
            if flag
        ]

        if len(selected_fps) >= 2:
            pairwise = [
                self._tanimoto_distance(selected_fps[a], selected_fps[b])
                for a in range(len(selected_fps))
                for b in range(a + 1, len(selected_fps))
            ]
            diversity_score = float(np.mean(pairwise))
        else:
            diversity_score = 1.0

        self._round_number += 1

        return RoundProposal(
            campaign_id=self.campaign_id,
            round_number=self._round_number,
            proposed_compounds=proposed_smiles,
            scores=scores_dict,
            acquisition_values=acq_values,
            pareto_front_smiles=pareto_smiles,
            diversity_score=diversity_score,
            timestamp=datetime.now(timezone.utc).isoformat(),
        )

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def save_proposal(self, proposal: RoundProposal):
        """Persist a RoundProposal to the bo_proposals SQLite table."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO bo_proposals
                (campaign_id, round_number, proposed_smiles, scores_json,
                 acquisition_values_json, pareto_front_smiles_json,
                 diversity_score, timestamp)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                proposal.campaign_id,
                proposal.round_number,
                json.dumps(proposal.proposed_compounds),
                json.dumps(proposal.scores),
                json.dumps(proposal.acquisition_values),
                json.dumps(proposal.pareto_front_smiles),
                proposal.diversity_score,
                proposal.timestamp,
            ))
            conn.commit()

    def load_proposals(self, campaign_id: str) -> list[RoundProposal]:
        """Load all proposals for a campaign ordered by round number."""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cur = conn.execute("""
                SELECT * FROM bo_proposals
                WHERE campaign_id = ?
                ORDER BY round_number
            """, (campaign_id,))
            rows = cur.fetchall()

        return [
            RoundProposal(
                campaign_id=row["campaign_id"],
                round_number=row["round_number"],
                proposed_compounds=json.loads(row["proposed_smiles"]),
                scores=json.loads(row["scores_json"]),
                acquisition_values=json.loads(row["acquisition_values_json"]),
                pareto_front_smiles=json.loads(row["pareto_front_smiles_json"]),
                diversity_score=row["diversity_score"],
                timestamp=row["timestamp"],
            )
            for row in rows
        ]

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------

    def get_pareto_summary(self, dataset: CampaignDataset) -> dict:
        """
        Compute and return a summary of the current Pareto front.

        Returns a dict with keys:
            n_compounds, n_pareto, pareto_smiles, objective_ranges, round_number
        """
        obj_names = list(dataset.objectives.keys())
        n_obj = len(obj_names)

        score_matrix = np.zeros((len(dataset.compound_ids), n_obj))
        for j, obj_name in enumerate(obj_names):
            y = dataset.objectives[obj_name].copy().astype(float)
            direction = dataset.objective_directions.get(obj_name, "maximize")
            lo, hi = y.min(), y.max()
            span = (hi - lo) if hi != lo else 1.0
            y_norm = (y - lo) / span
            if direction == "minimize":
                y_norm = 1.0 - y_norm
            score_matrix[:, j] = y_norm

        pareto_mask = self._compute_pareto_front(score_matrix)
        pareto_smiles = [
            dataset.smiles_list[i]
            for i, flag in enumerate(pareto_mask)
            if flag
        ]

        objective_ranges = {
            obj_name: {
                "min": float(dataset.objectives[obj_name].min()),
                "max": float(dataset.objectives[obj_name].max()),
            }
            for obj_name in obj_names
        }

        return {
            "n_compounds": len(dataset.compound_ids),
            "n_pareto": int(pareto_mask.sum()),
            "pareto_smiles": pareto_smiles,
            "objective_ranges": objective_ranges,
            "round_number": self._round_number,
        }
