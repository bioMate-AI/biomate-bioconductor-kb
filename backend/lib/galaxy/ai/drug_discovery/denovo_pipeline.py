"""
Closed in-silico de-novo generation loop for BioMate drug discovery.

Wires the generator swap-point (``generators.Generator``) into the EXISTING
multi-objective Bayesian optimizer (``bayesian_optimizer.BayesianOptimizer``)
so that affinity / ADMET are IN-LOOP acquisition signals rather than a post-hoc
filter:

    generate            (Generator.propose)                -> candidate SMILES
      -> predict         (affinity + ADMET predictors)     -> per-objective scores
      -> score + select  (GP surrogate + HVI acquisition)  -> next batch
      -> rank                                              -> ranked shortlist

The optimizer is REUSED as-is — this module does not reimplement any GP,
hypervolume, or Pareto logic.  It only:

  1. asks a ``Generator`` for a virtual library,
  2. featurises + labels a small *seed / training* set (the observed data the
     GP is fit on) using the same predictors,
  3. fits ``BayesianOptimizer`` on that seed set,
  4. calls ``propose_next_round`` over the generated virtual library so the GP's
     expected-hypervolume-improvement acquisition selects the batch,
  5. ranks the selected batch by mean predicted objective score.

Predictors are injected as callables ``predict(smiles_list) -> {smiles: value}``
(same contract as ``custom_model_wrapper.PythonFunctionWrapper``), so real
affinity / ADMET models — or stubs — drop in without touching the loop.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Callable, Optional

from .generators import Generator, GenerationSpec
from .bayesian_optimizer import BayesianOptimizer, CampaignDataset, RoundProposal

log = logging.getLogger(__name__)

try:
    import numpy as np
    _NUMPY_AVAILABLE = True
except ImportError:  # pragma: no cover
    _NUMPY_AVAILABLE = False
    np = None  # type: ignore[assignment]


# A predictor maps a list of SMILES to {smiles: numeric value} for one objective.
Predictor = Callable[[list], dict]


@dataclass
class ObjectiveSpec:
    """One in-loop objective backed by a predictor."""
    name: str
    predictor: Predictor          # smiles_list -> {smiles: value}
    direction: str = "maximize"   # 'maximize' | 'minimize'


@dataclass
class LoopResult:
    """Output of one closed generate->score->rank iteration."""
    campaign_id: str
    generator_name: str
    generator_is_learned: bool
    generator_status: dict
    n_generated: int
    n_scored: int
    proposal: Optional[RoundProposal]
    # Ranked shortlist: list of {smiles, rank, mean_score, <obj>: score, ...}
    ranked: list = field(default_factory=list)
    notes: list = field(default_factory=list)


class DeNovoPipeline:
    """
    Generator-agnostic closed loop around the existing BayesianOptimizer.

    Args:
        campaign_id:   campaign identifier (also seeds the optimizer RNG).
        generator:     any :class:`generators.Generator` (BRICS, BioNeMo, ...).
        objectives:    in-loop objectives (affinity / ADMET / etc.).
        db_path:       SQLite path for the optimizer's proposal persistence.
        n_initial:     min seed observations the GP requires before proposing.
    """

    def __init__(
        self,
        campaign_id: str,
        generator: Generator,
        objectives: list[ObjectiveSpec],
        db_path: str = "galaxy_ai_tools.db",
        n_initial: int = 8,
    ):
        if not objectives:
            raise ValueError("DeNovoPipeline requires at least one objective")
        self.campaign_id = campaign_id
        self.generator = generator
        self.objectives = objectives
        self.db_path = db_path
        self.n_initial = n_initial

    # ------------------------------------------------------------------
    # Prediction helper — runs every objective predictor over a SMILES list
    # ------------------------------------------------------------------

    def _predict_all(self, smiles_list: list) -> dict:
        """
        Run each objective predictor over ``smiles_list``.

        Returns ``{objective_name: np.ndarray aligned with smiles_list}``.
        Molecules a predictor omits are dropped from the returned alignment;
        the caller filters the SMILES list to the fully-scored intersection.
        """
        raw: dict[str, dict] = {}
        for obj in self.objectives:
            scores = obj.predictor(smiles_list)
            if not isinstance(scores, dict):
                raise ValueError(
                    f"Predictor for objective {obj.name!r} must return a dict, "
                    f"got {type(scores)}"
                )
            raw[obj.name] = {str(k): float(v) for k, v in scores.items()}
        return raw

    def _align(self, smiles_list: list, raw: dict) -> tuple:
        """
        Keep only SMILES scored by EVERY objective; build aligned arrays.

        Returns (kept_smiles, {objective: np.ndarray}).
        """
        kept = [s for s in smiles_list
                if all(s in raw[obj.name] for obj in self.objectives)]
        arrays = {
            obj.name: np.array([raw[obj.name][s] for s in kept], dtype=np.float64)
            for obj in self.objectives
        }
        return kept, arrays

    # ------------------------------------------------------------------
    # Main entry point — one closed loop iteration
    # ------------------------------------------------------------------

    def run_round(
        self,
        spec: GenerationSpec,
        seed_smiles: list,
        n_propose: int = 10,
        diversity_weight: float = 0.2,
    ) -> LoopResult:
        """
        Execute one generate -> predict -> score+select -> rank iteration.

        Args:
            spec:            what to generate (passed to the Generator).
            seed_smiles:     labelled seed/training compounds the GP is fit on.
                             These are scored by the SAME predictors so the
                             surrogate learns the in-loop objectives.  Must
                             contain >= ``n_initial`` predictable molecules.
            n_propose:       size of the selected next batch.
            diversity_weight: diversity term weight passed to the optimizer.

        Returns:
            :class:`LoopResult` with the ranked shortlist and full provenance.
        """
        if not _NUMPY_AVAILABLE:
            raise ImportError("numpy is required for DeNovoPipeline")

        notes: list[str] = []

        # ── 1. GENERATE ────────────────────────────────────────────────────
        generated = self.generator.propose(spec)
        gen_status = dict(getattr(self.generator, "last_status", {}))
        if not generated:
            notes.append(
                f"generator produced 0 molecules "
                f"(status={gen_status.get('reason', 'unknown')})"
            )
            return LoopResult(
                campaign_id=self.campaign_id,
                generator_name=self.generator.name,
                generator_is_learned=self.generator.is_learned,
                generator_status=gen_status,
                n_generated=0,
                n_scored=0,
                proposal=None,
                ranked=[],
                notes=notes,
            )

        # ── 2. PREDICT (seed set -> GP training labels) ────────────────────
        seed_raw = self._predict_all(seed_smiles)
        seed_kept, seed_objs = self._align(seed_smiles, seed_raw)
        if len(seed_kept) < self.n_initial:
            notes.append(
                f"insufficient labelled seed compounds: {len(seed_kept)} < "
                f"n_initial={self.n_initial}; cannot fit surrogate"
            )
            return LoopResult(
                campaign_id=self.campaign_id,
                generator_name=self.generator.name,
                generator_is_learned=self.generator.is_learned,
                generator_status=gen_status,
                n_generated=len(generated),
                n_scored=0,
                proposal=None,
                ranked=[],
                notes=notes,
            )

        # ── 3. SCORE + SELECT (reuse BayesianOptimizer GP + HVI) ───────────
        optimizer = BayesianOptimizer(
            campaign_id=self.campaign_id,
            db_path=self.db_path,
            n_initial=self.n_initial,
        )
        features = optimizer._featurise(seed_kept)  # shared featuriser (Morgan FP)
        dataset = CampaignDataset(
            compound_ids=[f"seed_{i}" for i in range(len(seed_kept))],
            smiles_list=seed_kept,
            features=features,
            objectives=seed_objs,
            objective_directions={o.name: o.direction for o in self.objectives},
        )
        optimizer.fit(dataset)

        # The generated molecules ARE the virtual library the GP scores.
        proposal = optimizer.propose_next_round(
            virtual_library_smiles=generated,
            n_propose=min(n_propose, len(generated)),
            diversity_weight=diversity_weight,
        )

        # ── 4. RANK (by mean predicted objective score across objectives) ──
        ranked = self._rank_proposal(proposal)

        return LoopResult(
            campaign_id=self.campaign_id,
            generator_name=self.generator.name,
            generator_is_learned=self.generator.is_learned,
            generator_status=gen_status,
            n_generated=len(generated),
            n_scored=len(proposal.proposed_compounds),
            proposal=proposal,
            ranked=ranked,
            notes=notes,
        )

    # ------------------------------------------------------------------
    # Ranking
    # ------------------------------------------------------------------

    @staticmethod
    def _rank_proposal(proposal: RoundProposal) -> list:
        """
        Rank the proposed compounds by the mean of their (already normalised,
        higher-is-better) per-objective GP scores.

        The optimizer returns ``proposal.scores`` as
        ``{objective: [score per proposed compound]}`` — all oriented so higher
        is better.  We average across objectives for a single ranking key while
        keeping every per-objective value for transparency.
        """
        smiles = proposal.proposed_compounds
        obj_names = list(proposal.scores.keys())
        rows = []
        for i, smi in enumerate(smiles):
            per_obj = {name: proposal.scores[name][i] for name in obj_names}
            mean_score = (
                sum(per_obj.values()) / len(per_obj) if per_obj else 0.0
            )
            row = {"smiles": smi, "mean_score": round(mean_score, 4)}
            for name, val in per_obj.items():
                row[name] = round(val, 4)
            if i < len(proposal.acquisition_values):
                row["acquisition"] = round(proposal.acquisition_values[i], 4)
            rows.append(row)

        rows.sort(key=lambda r: -r["mean_score"])
        for rank, row in enumerate(rows, 1):
            row["rank"] = rank
        return rows
