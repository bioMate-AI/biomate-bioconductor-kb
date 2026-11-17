"""
Multi-objective Bayesian optimisation for BioMate drug discovery campaigns.

Fits a Gaussian-process surrogate per objective (Tanimoto kernel on Morgan
fingerprints, see fingerprint_surrogate.py), then proposes the next synthesis
batch via expected (hypervolume) improvement + diversity penalty, closing the
DMTA (Design–Make–Test–Analyse) loop. Every proposal states whether the
surrogate can actually discriminate between the candidates.
"""
import hashlib
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
    from .fingerprint_surrogate import (
        SMALL_TRAINING_SET,
        MorganFeaturizer,
        TanimotoGP,
        _RDKIT_AVAILABLE,
        assess_discrimination,
        expected_hypervolume_improvement,
        expected_improvement,
        tanimoto_similarity,
    )
    # Sequence (peptide / biologic) featuriser + Matern GP — same interface as
    # MorganFeaturizer / TanimotoGP, selected per modality in __init__.
    from .sequence_surrogate import SequenceFeaturizer, SequenceGP
    _SKLEARN_AVAILABLE = True
except ImportError:
    _SKLEARN_AVAILABLE = False
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
    # Confidence intervals from GP posterior std — Phase 1 CRO readiness
    confidence_intervals: dict[str, list[tuple[float, float]]] = field(default_factory=dict)
    # Applicability domain status per proposed compound
    ad_statuses: list[str] = field(default_factory=list)
    gp_stds: dict[str, list[float]] = field(default_factory=dict)
    # False when the posterior cannot confidently order any candidate pair:
    # the scores then carry no ranking information beyond their uncertainty.
    can_discriminate: Optional[bool] = None
    # Kernel, featuriser, fitted noise, discrimination evidence, excluded
    # candidates and warnings for this round.
    surrogate_report: dict = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Optimizer
# ---------------------------------------------------------------------------

class BayesianOptimizer:
    """
    Multi-objective Bayesian optimizer for drug discovery campaigns.

    Maintains one GP surrogate per objective.  All objectives are internally
    normalised to [0, 1] over the observed range with 'higher = better'
    polarity so that HVI and Pareto logic are consistent regardless of the
    original direction.  Predicted scores are on that normalised scale and may
    fall outside [0, 1] for candidates predicted beyond the observed range.

    Features must come from ``featurise`` (one shared featuriser for fit and
    predict); ``fit`` rejects datasets whose features were built otherwise.
    """

    #: Modalities whose entities are amino-acid sequences (dense-descriptor GP)
    #: rather than small-molecule SMILES (Morgan/Tanimoto GP).
    SEQUENCE_MODALITIES = ("peptide", "biologic")

    #: Soft bonus added to a candidate's selection score when it is inside the
    #: applicability domain. acq_norm and diversity are each in [0, 1], so this
    #: breaks ties toward trustworthy candidates without overriding a clearly
    #: better-acquisition out-of-domain candidate (and has no effect when no
    #: candidate is in-domain). Tuned to surface actionable proposals without
    #: killing exploration.
    _AD_SELECTION_BONUS = 0.25

    def __init__(
        self,
        campaign_id: str,
        db_path: str = "galaxy_ai_tools.db",
        n_initial: int = 16,
        modality: str = "small_molecule",
    ):
        if not _NUMPY_AVAILABLE:
            raise ImportError(
                "numpy is required for BayesianOptimizer. "
                "Install it with: pip install numpy"
            )
        if not _SKLEARN_AVAILABLE:
            raise ImportError(
                "scikit-learn and scipy are required for BayesianOptimizer. "
                "Install them with: pip install scikit-learn scipy"
            )
        self.modality = modality
        # Featuriser + GP are selected by modality; both expose the same
        # featurise()/fit()/predict() contract, so everything downstream
        # (featurise, _fit_surrogates, propose_next_round, discrimination,
        # acquisition) is modality-agnostic.
        if modality in self.SEQUENCE_MODALITIES:
            self._featurizer = SequenceFeaturizer(modality)
            self._gp_class = SequenceGP
            self._entity_kind = "sequence"
        else:
            self._featurizer = MorganFeaturizer()
            self._gp_class = TanimotoGP
            self._entity_kind = "smiles"

        self.campaign_id = campaign_id
        self.db_path = db_path
        self.n_initial = n_initial

        # Reproducible across processes (str hash() is salted per process).
        self._seed = int.from_bytes(
            hashlib.sha256(campaign_id.encode("utf-8")).digest()[:4], "big") % (2 ** 31)
        self._rng = np.random.RandomState(self._seed)

        self._gp_models: dict = {}  # str -> TanimotoGP | SequenceGP (by modality)
        self._observed_scaled: dict[str, "np.ndarray"] = {}
        self._objective_directions: dict[str, str] = {}
        self._dataset: Optional[CampaignDataset] = None
        self._round_number: int = 0
        # MorganFeaturizer exposes n_bits; SequenceFeaturizer exposes N_FEATURES.
        self._n_features: int = getattr(self._featurizer, "n_bits", None) or self._featurizer.N_FEATURES

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
                    timestamp                TEXT NOT NULL,
                    surrogate_report_json    TEXT NOT NULL DEFAULT '{}'
                )
            """)
            cols = {r[1] for r in conn.execute("PRAGMA table_info(bo_proposals)")}
            if "surrogate_report_json" not in cols:
                conn.execute("ALTER TABLE bo_proposals "
                             "ADD COLUMN surrogate_report_json TEXT NOT NULL DEFAULT '{}'")
            conn.commit()

    # ------------------------------------------------------------------
    # Featurisation
    # ------------------------------------------------------------------

    def featurise(self, smiles_list: list[str]) -> "np.ndarray":
        """Morgan fingerprints (radius 2, 2048 bits) — the only feature space
        the surrogate is fitted and queried in. Unparsable SMILES give
        all-zero rows; ``fit`` rejects them and proposals exclude them."""
        X, _invalid = self._featurizer.featurise(smiles_list)
        return X

    _featurise = featurise

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
    # Fitting
    # ------------------------------------------------------------------

    def fit(self, dataset: CampaignDataset):
        """
        Fit one Tanimoto-kernel GP surrogate per objective.

        Each objective is min-max normalised to [0, 1] over the observed
        values; 'minimize' objectives are flipped so that higher is better.

        Raises:
            ValueError: if a training SMILES cannot be parsed, or if
                ``dataset.features`` are not this optimizer's fingerprints of
                ``dataset.smiles_list`` (fit and predict must share features).
        """
        n = len(dataset.smiles_list)
        X, invalid = self._featurizer.featurise(dataset.smiles_list)
        if invalid:
            bad = [dataset.smiles_list[i] for i in invalid]
            raise ValueError(f"cannot featurise training SMILES {bad!r}")
        given = np.asarray(dataset.features, dtype=np.float64)
        if given.shape != X.shape or not np.array_equal(given, X):
            raise ValueError(
                f"dataset.features (shape {given.shape}) are not the optimizer's "
                f"{self._featurizer.signature} fingerprints of dataset.smiles_list "
                f"(shape {X.shape}); build them with BayesianOptimizer.featurise() so "
                "training and candidate compounds share one feature space"
            )
        for obj_name, y_raw in dataset.objectives.items():
            if len(y_raw) != n:
                raise ValueError(f"objective {obj_name!r} has {len(y_raw)} values for {n} compounds")

        self._dataset = dataset
        self._objective_directions = dict(dataset.objective_directions)
        self._n_features = X.shape[1]
        self._gp_models = {}
        self._observed_scaled = {}

        for obj_name, y_raw in dataset.objectives.items():
            direction = dataset.objective_directions.get(obj_name, "maximize")
            y = np.asarray(y_raw, dtype=np.float64)
            lo, hi = float(y.min()), float(y.max())
            y_scaled = (y - lo) / (hi - lo) if hi > lo else np.zeros_like(y)
            if direction == "minimize":
                y_scaled = 1.0 - y_scaled
            self._observed_scaled[obj_name] = y_scaled

            gp = self._gp_class(random_state=self._rng.randint(0, 2 ** 31 - 1))
            gp.fit(X, y_scaled)
            for msg in gp.fit_warnings:
                log.warning("BayesianOptimizer.fit[%s/%s]: %s", self.campaign_id, obj_name, msg)
            self._gp_models[obj_name] = gp

        # Sync round counter with the persisted round ledger (bo_proposals).
        self._round_number = self.latest_round()

        log.info(
            "BayesianOptimizer.fit: campaign=%s n_compounds=%d objectives=%s round=%d "
            "noise=%s",
            self.campaign_id,
            n,
            list(dataset.objectives.keys()),
            self._round_number,
            {k: round(m.noise_level, 4) for k, m in self._gp_models.items()},
        )

    # ------------------------------------------------------------------
    # Proposal generation
    # ------------------------------------------------------------------

    def _screen_candidates(self, smiles_list: list[str]) -> "tuple[list[int], list[dict]]":
        """Indices of usable candidates, plus the excluded ones with reasons.

        Excludes unparsable SMILES, repeats of an earlier candidate (same
        canonical structure) and compounds already measured in training.
        """
        measured = {self._featurizer.canonical(s) for s in self._dataset.smiles_list}
        seen: dict[str, int] = {}
        keep: list[int] = []
        excluded: list[dict] = []
        for i, smi in enumerate(smiles_list):
            can = self._featurizer.canonical(smi)
            if can is None:
                excluded.append({"smiles": smi, "reason": "invalid_smiles"})
            elif can in measured:
                excluded.append({"smiles": smi, "reason": "already_measured"})
            elif can in seen:
                excluded.append({"smiles": smi, "reason": "duplicate_structure",
                                 "duplicate_of": smiles_list[seen[can]]})
            else:
                seen[can] = i
                keep.append(i)
        return keep, excluded

    def _ad_mask(self, n_cand, cand_smiles, X_lib, pred_scores, pred_stds):
        """Applicability-domain in/out for every candidate, via the checker that
        matches the modality. Returns (in_domain: np.ndarray[bool], status_by_index:
        dict[int, str]). Non-fatal: on any failure every candidate is treated as
        in-domain (status "unknown") so the loop still proposes."""
        import numpy as np
        in_domain = np.ones(n_cand, dtype=bool)
        status: dict[int, str] = {}
        if n_cand == 0:
            return in_domain, status
        try:
            if self._entity_kind == "sequence":
                from .sequence_surrogate import SequenceApplicabilityDomain
                seq_ad = SequenceApplicabilityDomain().fit(self._dataset.features)
                results = seq_ad.check(X_lib, list(cand_smiles))
                for i, r in enumerate(results):
                    in_domain[i] = bool(r.in_domain)
                    status[i] = "in_domain" if r.in_domain else "out_of_domain"
            else:
                from .applicability_domain import ApplicabilityDomainChecker
                chk = ApplicabilityDomainChecker(self._dataset.features)
                for i in range(n_cand):
                    r = chk.check(cand_smiles[i], X_lib[i],
                                  gp_mean=float(pred_scores[i, 0]),
                                  gp_std=float(pred_stds[i, 0]))
                    in_domain[i] = (r.ad_status == "in_domain")
                    status[i] = r.ad_status
        except Exception as exc:  # noqa: BLE001 — AD is advisory, never fatal
            log.warning("AD precompute failed (non-fatal): %s", exc)
            in_domain = np.ones(n_cand, dtype=bool)
            status = {i: "unknown" for i in range(n_cand)}
        return in_domain, status

    def propose_next_round(
        self,
        virtual_library_smiles: list[str],
        n_propose: int = 10,
        diversity_weight: float = 0.2,
    ) -> RoundProposal:
        """
        Score the virtual library under the surrogate and select the best
        n_propose compounds by acquisition + Tanimoto diversity.

        Acquisition uses posterior mean and uncertainty: analytic expected
        improvement over the best observed compound for one objective, Monte
        Carlo expected hypervolume improvement over the observed Pareto front
        for several. Selection is greedy: at each step the compound maximising

            (1 - diversity_weight) * acquisition / max(acquisition)
            + diversity_weight * min_tanimoto_dist_from_selected

        is chosen and added to the batch.

        ``can_discriminate`` / ``surrogate_report`` state whether the
        posterior can confidently order any candidate pair; when it cannot,
        predicted score differences are within uncertainty and the batch is
        exploratory.

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

        keep, excluded = self._screen_candidates(virtual_library_smiles)
        cand_smiles = [virtual_library_smiles[i] for i in keep]
        X_lib = self.featurise(cand_smiles)
        n_cand = len(cand_smiles)

        pred_scores = np.zeros((n_cand, n_obj))
        pred_stds = np.zeros((n_cand, n_obj))
        for j, obj_name in enumerate(obj_names):
            if n_cand:
                mu, sigma = self._gp_models[obj_name].predict(X_lib, return_std=True)
                pred_scores[:, j] = mu
                pred_stds[:, j] = sigma

        observed = np.column_stack([self._observed_scaled[o] for o in obj_names])
        pareto_mask_train = self._compute_pareto_front(observed)

        if n_cand == 0:
            acquisition = np.zeros(0)
            acquisition_kind = "none"
        elif n_obj == 1:
            acquisition = expected_improvement(pred_scores[:, 0], pred_stds[:, 0],
                                               float(observed[:, 0].max()))
            acquisition_kind = "expected_improvement"
        else:
            acquisition = expected_hypervolume_improvement(
                pred_scores, pred_stds, observed[pareto_mask_train],
                reference_point=np.zeros(n_obj), rng=self._rng,
            )
            acquisition_kind = "expected_hypervolume_improvement"
        acq_max = float(acquisition.max()) if n_cand else 0.0
        acq_norm = acquisition / acq_max if acq_max > 0 else np.zeros(n_cand)

        # Applicability-domain status for ALL candidates, using the
        # modality-appropriate checker: sequences use the distance-based
        # SequenceApplicabilityDomain (the fingerprint hat-matrix leverage is
        # degenerate for the 31-dim descriptors when n<p), small molecules keep
        # the leverage checker. Computed up front so selection can prefer
        # in-domain candidates — otherwise acquisition (which rewards
        # uncertainty) selects exactly the extrapolations the AD then flags, and
        # every proposal comes back "out of domain".
        ad_in_domain, ad_status_by_index = self._ad_mask(
            n_cand, cand_smiles, X_lib, pred_scores, pred_stds)

        # Greedy batch construction with a diversity bonus and a soft preference
        # for in-domain candidates. The AD bonus only breaks ties toward
        # trustworthy candidates; when none are in-domain it is uniform (all
        # False) and has no effect, so early exploratory rounds still propose the
        # best-acquisition extrapolations.
        selected_indices: list[int] = []
        selection_scores: list[float] = []
        remaining = list(range(n_cand))
        for _ in range(min(n_propose, n_cand)):
            if selected_indices:
                sim = tanimoto_similarity(X_lib[remaining], X_lib[selected_indices])
                diversity = 1.0 - sim.max(axis=1)
            else:
                diversity = np.ones(len(remaining))
            combined = ((1.0 - diversity_weight) * acq_norm[remaining]
                        + diversity_weight * diversity
                        + self._AD_SELECTION_BONUS * ad_in_domain[remaining].astype(float))
            k = int(np.argmax(combined))
            selected_indices.append(remaining.pop(k))
            selection_scores.append(round(float(combined[k]), 6))

        proposed_smiles = [cand_smiles[i] for i in selected_indices]

        scores_dict: dict[str, list[float]] = {
            obj_name: [float(pred_scores[i, j]) for i in selected_indices]
            for j, obj_name in enumerate(obj_names)
        }

        # 95% intervals of the predicted (latent) score: mean ± 1.96 × posterior std.
        ci_dict: dict[str, list[tuple[float, float]]] = {}
        std_dict: dict[str, list[float]] = {}
        for j, obj_name in enumerate(obj_names):
            cis = []
            stds = []
            for i in selected_indices:
                mu_i = float(pred_scores[i, j])
                s_i = float(pred_stds[i, j])
                half = 1.96 * s_i
                cis.append((round(mu_i - half, 4), round(mu_i + half, 4)))
                stds.append(round(s_i, 6))
            ci_dict[obj_name] = cis
            std_dict[obj_name] = stds

        # Applicability-domain statuses for the selected batch (precomputed above
        # with the modality-appropriate checker).
        ad_statuses: list[str] = [ad_status_by_index.get(i, "unknown") for i in selected_indices]

        pareto_smiles = [
            self._dataset.smiles_list[i]
            for i, flag in enumerate(pareto_mask_train)
            if flag
        ]

        if len(selected_indices) >= 2:
            sim = tanimoto_similarity(X_lib[selected_indices], X_lib[selected_indices])
            iu = np.triu_indices(len(selected_indices), k=1)
            diversity_score = float(np.mean(1.0 - sim[iu]))
        else:
            diversity_score = 1.0

        report = self._surrogate_report(X_lib, obj_names, excluded, acquisition_kind,
                                        selection_scores, n_requested=n_propose)

        self._round_number += 1

        return RoundProposal(
            campaign_id=self.campaign_id,
            round_number=self._round_number,
            proposed_compounds=proposed_smiles,
            scores=scores_dict,
            acquisition_values=[float(acquisition[i]) for i in selected_indices],
            pareto_front_smiles=pareto_smiles,
            diversity_score=diversity_score,
            timestamp=datetime.now(timezone.utc).isoformat(),
            confidence_intervals=ci_dict,
            ad_statuses=ad_statuses,
            gp_stds=std_dict,
            can_discriminate=report["can_discriminate"],
            surrogate_report=report,
        )

    def _surrogate_report(self, X_lib: "np.ndarray", obj_names: list[str],
                          excluded: list[dict], acquisition_kind: str,
                          selection_scores: list[float], n_requested: int) -> dict:
        n_train = len(self._dataset.compound_ids)
        warnings: list[str] = []
        objectives: dict[str, dict] = {}
        for obj_name in obj_names:
            gp = self._gp_models[obj_name]
            disc = assess_discrimination(gp, X_lib)
            objectives[obj_name] = {
                "noise_level": round(gp.noise_level, 6),
                "log_marginal_likelihood": round(gp.log_marginal_likelihood_value_, 6),
                "discrimination": disc,
            }
            if gp.constant_labels:
                warnings.append(f"{obj_name}: constant_labels — all observed values are identical")
            if gp.noise_at_upper_bound:
                warnings.append(f"{obj_name}: noise_at_upper_bound — fingerprint similarity "
                                "explains none of the label variance")
            warnings.extend(f"{obj_name}: {m}" for m in gp.fit_warnings)
            if not disc["can_discriminate"]:
                warnings.append(f"{obj_name}: cannot_discriminate — {disc['reason']}")
        if n_train < SMALL_TRAINING_SET:
            warnings.append(f"small_training_set: {n_train} compounds (< {SMALL_TRAINING_SET}); "
                            "the fitted noise level and all uncertainties are rough")
        if excluded:
            warnings.append(f"{len(excluded)} virtual-library entries excluded")
        n_proposed = len(selection_scores)
        if n_proposed < n_requested:
            warnings.append(f"fewer_than_requested: {n_proposed} of {n_requested} proposed; "
                            f"only {X_lib.shape[0]} usable virtual-library entries")
        can = any(o["discrimination"]["can_discriminate"] for o in objectives.values())
        return {
            "model": "gaussian_process",
            "kernel": ("1.0 * Matern(nu=2.5) + White(noise)"
                       if self.modality in self.SEQUENCE_MODALITIES
                       else "1.0 * Tanimoto + White(noise)"),
            "featurizer": self._featurizer.signature,
            "score_scale": "observed range min-max normalised, higher = better",
            "acquisition": acquisition_kind,
            "selection_scores": selection_scores,
            "n_train": n_train,
            "n_requested": int(n_requested),
            "n_proposed": n_proposed,
            "n_candidates_scored": int(X_lib.shape[0]),
            "can_discriminate": bool(can),
            "objectives": objectives,
            "excluded_candidates": excluded,
            "warnings": warnings,
        }

    # ------------------------------------------------------------------
    # Persistence
    # ------------------------------------------------------------------

    def latest_round(self, conn: Optional[sqlite3.Connection] = None) -> int:
        """Highest persisted round for this campaign (0 if none).

        bo_proposals is the single source of truth for round numbers; every
        persisted proposal (including auto-retrain rounds) is recorded here.
        """
        sql = "SELECT COALESCE(MAX(round_number), 0) FROM bo_proposals WHERE campaign_id = ?"
        if conn is not None:
            return int(conn.execute(sql, (self.campaign_id,)).fetchone()[0])
        with sqlite3.connect(self.db_path) as own:
            return int(own.execute(sql, (self.campaign_id,)).fetchone()[0])

    def save_proposal(self, proposal: RoundProposal,
                      conn: Optional[sqlite3.Connection] = None) -> int:
        """Persist a RoundProposal to bo_proposals and return its round number.

        The round is allocated at commit time as MAX(round_number) + 1 inside a
        write-locked transaction, so concurrent writers (background retrain loop
        vs. a manual trigger) can never persist the same round twice.
        ``proposal.round_number`` is updated in place to the allocated value.

        When ``conn`` is given the caller owns the transaction (it must already
        hold a write lock, e.g. via ``BEGIN IMMEDIATE``) and commits it.
        """
        if proposal.campaign_id != self.campaign_id:
            raise ValueError(
                f"proposal campaign {proposal.campaign_id!r} does not match "
                f"optimizer campaign {self.campaign_id!r}"
            )
        if conn is not None:
            return self._insert_proposal(conn, proposal)
        own = sqlite3.connect(self.db_path, isolation_level=None)
        try:
            own.execute("BEGIN IMMEDIATE")
            try:
                round_number = self._insert_proposal(own, proposal)
            except Exception:
                own.execute("ROLLBACK")
                raise
            own.execute("COMMIT")
            return round_number
        finally:
            own.close()

    def _insert_proposal(self, conn: sqlite3.Connection, proposal: RoundProposal) -> int:
        round_number = self.latest_round(conn) + 1
        conn.execute("""
            INSERT INTO bo_proposals
            (campaign_id, round_number, proposed_smiles, scores_json,
             acquisition_values_json, pareto_front_smiles_json,
             diversity_score, timestamp, surrogate_report_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            proposal.campaign_id,
            round_number,
            json.dumps(proposal.proposed_compounds),
            json.dumps(proposal.scores),
            json.dumps(proposal.acquisition_values),
            json.dumps(proposal.pareto_front_smiles),
            proposal.diversity_score,
            proposal.timestamp,
            json.dumps(proposal.surrogate_report),
        ))
        proposal.round_number = round_number
        self._round_number = max(self._round_number, round_number)
        return round_number

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
                can_discriminate=report.get("can_discriminate"),
                surrogate_report=report,
            )
            for row in rows
            for report in [json.loads(row["surrogate_report_json"] or "{}")]
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
