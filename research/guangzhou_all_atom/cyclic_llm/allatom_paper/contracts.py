"""Interface contracts for the all-atom hybrid-LLM paper (workstreams I-A, I-B, U1, U2, U3, E).

Normative text: docs/20261031_ALLATOM_IMPLEMENTATION_PLAN.md section 2; design: docs/20261031_ALLATOM_LLM_PAPER_DESIGN.md.
Every workstream codes against THESE Protocols; changing a signature requires an amendment commit + a message to the
affected owners. This module has no heavy imports (no torch, no rdkit) so it can be imported anywhere; it defines types only.

Roles of a verifier (enforced by allatom_paper/pmo_harness.py):
  train     budgeted optimisation oracle (every optimiser gets the same number of calls)
  stop      used ONLY by the StopMonitor to decide early stopping; never an optimisation oracle, never in the final report
  heldout   applied ONLY to the final top-k of a run; never an oracle; independent of train and stop (names AND fit sources)
  constraint  free hard-rule filter (no oracle call is charged for a rule failure)
Independence is checked by pmo_harness.check_independent / check_three_way (fit_sources are `Verifier.trained_on`).
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Dict, FrozenSet, List, Optional, Protocol, Sequence, Tuple, runtime_checkable

try:  # package import (pytest from the repo root / installed package)
    from .pmo_harness import BudgetExhausted, BudgetedOracle, HeldOutVerifierError, Verifier  # noqa: F401
except ImportError:  # flat import (scripts run from inside allatom_paper/)
    from pmo_harness import BudgetExhausted, BudgetedOracle, HeldOutVerifierError, Verifier  # noqa: F401

ROLES: Tuple[str, ...] = ("train", "stop", "heldout", "constraint")
CONTRACT_VERSION = "1.0"


# ------------------------------------------------------------------------------------------------ prompt context
@dataclass
class PromptContext:
    """What the generator is conditioned on (built by the Retriever / prompt builder, consumed by the Generator)."""
    objective: str = ""                                   # objective-family id, e.g. "F1" | "F2"
    seed_smiles: Sequence[str] = ()                       # optional seeds / parents
    retrieved: Sequence[Tuple[str, Dict[str, float]]] = ()  # (smiles, {verifier_name: score}) from the Retriever
    rules_text: str = ""                                  # human-readable rule summary (optional, for prompting)
    extra: Dict[str, Any] = field(default_factory=dict)


# ------------------------------------------------------------------------------------------------ generator
@runtime_checkable
class Generator(Protocol):
    """Existing causal chemical LM (ChemFM-1B) + LoRA delta, or any stand-in with the same surface (toy generators too)."""

    def sample(self, n: int, ctx: "PromptContext", temperature: float, seed: int,
               constraint: Optional["Constraint"] = None) -> List[str]:
        """Return n SMILES (may contain invalid / duplicate strings; the harness decides what is charged). If `constraint`
        is given, decoding must apply its mask at every step (hard rules => rule satisfaction by construction)."""

    def logprobs(self, smiles_list: Sequence[str], ctx: "PromptContext") -> List[float]:
        """Sequence log-probabilities under the CURRENT policy (needed by the preference updater)."""

    def load_lora(self, path: str) -> None:
        """Load a LoRA delta checkpoint (path local or s3://). Idempotent."""

    def lora_state(self) -> bytes:
        """Serialised current LoRA delta (for resumable checkpoints); empty bytes for generators without a delta."""

    def kl_to_reference(self, smiles_list: Sequence[str], ctx: "PromptContext") -> float:
        """Mean sequence-level KL estimate (policy vs frozen reference) on the given samples; 0.0 for a frozen generator."""


# ------------------------------------------------------------------------------------------------ constraint (rule automaton)
@runtime_checkable
class Constraint(Protocol):
    """Rule automaton over the generator's token vocabulary (U1). `state` is opaque to callers."""

    def init_state(self) -> Any:
        """Fresh decoding state."""

    def mask(self, state: Any, vocab: Sequence[str]) -> Sequence[bool]:
        """True for tokens that keep the prefix FEASIBLE (prefix-feasibility look-ahead: a token is allowed only if some
        completion can still satisfy every hard rule)."""

    def advance(self, state: Any, token: str) -> Any:
        """State after emitting `token` (must be a masked-in token)."""

    def is_complete(self, state: Any) -> bool:
        """True if the string so far is a complete molecule satisfying all hard rules."""

    def soft_logits(self, state: Any, vocab: Sequence[str]) -> Sequence[float]:
        """Additive log-linear potentials for soft rules (product-of-experts); zeros when there are none."""

    def check(self, smiles: str) -> bool:
        """Post-hoc hard-rule check on a finished SMILES (the free constraint filter used by BudgetedOracle)."""


# ------------------------------------------------------------------------------------------------ retrieval
@runtime_checkable
class Retriever(Protocol):
    """Store of known / already-scored peptides; stereo-aware nearest-neighbour search (I-B)."""

    def build(self, rows: Sequence[Dict[str, Any]]) -> None:
        """rows: {smiles, scores: {verifier_name: float}, doc: optional document id, source: optional lab id}."""

    def query(self, smiles: str, k: int, exclude_docs: Optional[FrozenSet[str]] = None) -> List[Tuple[str, Dict[str, float]]]:
        """k nearest by stereo-aware Tanimoto; rows whose `doc` is in `exclude_docs` are never returned (blind rule, arm G)."""

    def add(self, smiles: str, scores: Dict[str, float], doc: Optional[str] = None, source: Optional[str] = None) -> None:
        """Insert a newly scored molecule (feedback loop)."""


# ------------------------------------------------------------------------------------------------ preference update
@dataclass
class PreferencePair:
    chosen: str
    rejected: str
    margin: float            # rank/score gap that defined the pair
    group: str = ""          # group id (e.g. round + prompt) for variance diagnostics


@runtime_checkable
class PreferenceUpdater(Protocol):
    """Graded preference / policy update (U3). Fixes the zero-variance-group stall of the earlier GRPO attempt."""

    def make_pairs(self, samples: Sequence[str], scores: Sequence[Optional[float]], margin: float,
                   group_by: Optional[Sequence[str]] = None) -> Tuple[List[PreferencePair], Dict[str, float]]:
        """Rank-ordered pairs with a margin; returns (pairs, diagnostics) where diagnostics include at least
        `frac_zero_variance_groups`, `n_pairs`, `mean_margin`, `n_groups_kept`."""

    def step(self, pairs: Sequence[PreferencePair], lr: float, beta: float) -> Dict[str, float]:
        """One update of the generator's LoRA delta; returns metrics incl. `loss`, `kl`, `weight_delta_rel`."""


# ------------------------------------------------------------------------------------------------ stop monitor
@runtime_checkable
class StopMonitorLike(Protocol):
    """Goodhart-gap early stopping (U2). Receives train-verifier and STOP-verifier scores of the same top-k; never held-out."""

    def update(self, round_idx: int, train_scores: Sequence[float], stop_scores: Sequence[float]) -> Dict[str, Any]:
        """Return {gap, trend, should_stop, ...}."""


# ------------------------------------------------------------------------------------------------ logging schema
@dataclass
class OracleCallRow:
    """One JSONL row per ORACLE call (charged call). Uploaded to S3 every 60 s by the orchestrator."""
    run_id: str
    method: str
    objective: str
    seed: int
    round: int
    call_index: int
    verifier: str
    smiles_hash: str          # sha256(canonical SMILES)[:16]; the SMILES itself goes only into the per-run results file
    score: float
    calls_used: int
    t_unix: float


@dataclass
class RoundRow:
    """One JSONL row per feedback round."""
    run_id: str
    method: str
    objective: str
    seed: int
    round: int
    n_sampled: int
    n_invalid: int
    n_dup: int
    n_constraint_fail: int
    calls_used: int
    train_topk_mean: float
    stop_topk_mean: Optional[float] = None
    gap: Optional[float] = None
    should_stop: Optional[bool] = None
    kl: Optional[float] = None
    weight_delta_rel: Optional[float] = None
    frac_zero_variance_groups: Optional[float] = None
    n_pairs: Optional[int] = None
    t_unix: float = 0.0


def row_to_dict(row) -> Dict[str, Any]:
    d = asdict(row)
    d["_type"] = type(row).__name__
    return d


# ------------------------------------------------------------------------------------------------ known issues recorded with the contract
KNOWN_ISSUES = (
    # 2026-10-29 (I-A): kb_audit/peptide_sar_rules_v1.json was mined from ALL 21 training sources, so it cannot be used as a
    # train/stop verifier or soft rule for an experiment whose held-out verifiers are fitted on a subset of those sources:
    # ihlm.symbolic.assert_priors_clean(rules, heldout_sources) raises. A re-mining restricted to the TRAIN source group
    # (group A in verifiers.source_groups) is required before the soft-rule component is used in a comparison.
    "SAR rules file mined on all 21 sources: re-mine on train group A before use as soft rule/verifier",
)
