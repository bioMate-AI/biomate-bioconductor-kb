"""Track A — END-TO-END DMTA LOOP orchestrator (the compounding moat, skeleton form).

Per the execution plan (docs/20260925_PEPTIDE_EXECUTION_PLAN.md, Track A, "Sequencing"):
chain the already-built modules into ONE runnable Design-Make-Test-Analyze loop:

    generate  ->  A3 gate  ->  A1 verify  ->  A2 select  ->  A4 pair-emit (learn signal)
    (pluggable)   (cheap)      (expensive)   (Pareto+HVI)  (DPO pairs; training is separate)

    run_loop(config) -> LoopResult

Design contract — every stage is a PLUGGABLE, clean interface so a real implementation swaps in
without touching the orchestrator:

    Generator : (context, n) -> list[Candidate dict {identifier, seq, smiles}]
        STUB now: ``PoolGenerator`` just yields a supplied candidate pool. Later the frozen
        epoch-221 PepGLAD checkpoint (or any generator) plugs in here — see ``FrozenCheckpointGenerator``
        stub + the "How the frozen checkpoint plugs in" note at the bottom.
    Gate      : peptide_gate.gate_candidates                 (REAL — A3)
    Verify    : peptide_verify.verify_batch                   (REAL — A1; physics field ingests JSON)
    Select    : peptide_select.select_batch                   (REAL — A2)
    PairEmit  : dpo_pairs.emit_pairs                           (REAL — A4 emitter; NOT training)
    Learn     : LearnHook — a no-op that RECORDS the emitted pairs (stub). The real DPO fine-tune
        (dpo_peptide_trainer.py, TRL DPOTrainer, not built here) plugs in here.

Each stage is injectable (the ``*_fn`` config fields) so tests use mocks and production swaps reals.
The orchestrator only knows the INTERFACES, never the implementations — that is what makes the
skeleton real: A1/A2/A3/A4 already exist and compose today; generate + learn are the two seams the
model side (Track B / A4-trainer) fills later.

Modality-general: swap ``Generator`` + point verify/select at small-molecule scorers and the same
loop drives small molecules. The orchestration, provenance log, gate→verify cost saving, and pair
emission are chemistry-agnostic.

CPU only. The orchestrator never launches a GPU/AWS job; the physics ΔG field is INGESTED from a
result JSON (verify's contract), so a completed MM-GBSA/FEP run feeds the loop without the loop
paying for it.
"""
from __future__ import annotations

import importlib.util
import json
import logging
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Dict, List, Optional, Sequence

log = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parent


# --------------------------------------------------------------------------------------------
# lazy sibling-script loader (matches the pattern in verify/select/gate)
# --------------------------------------------------------------------------------------------
def _load(name: str):
    path = ROOT / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    import sys
    sys.modules[name] = mod  # dataclass introspection wants it registered
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


# --------------------------------------------------------------------------------------------
# Stage-1 interface: GENERATOR (pluggable). Contract:
#     generate(context: dict, n: int) -> list[dict]  each {identifier, seq?, smiles?}
# --------------------------------------------------------------------------------------------
class Generator:
    """Interface. Real generators (frozen epoch-221, REINVENT4, a DPO-tuned prior) implement this."""
    name: str = "generator"

    def generate(self, context: dict, n: int) -> List[dict]:  # pragma: no cover - interface
        raise NotImplementedError


class PoolGenerator(Generator):
    """STUB generator: yields a fixed candidate pool (optionally the first n). Lets the whole loop
    run end-to-end today with a supplied pool, before any real generator exists."""
    name = "pool_stub"

    def __init__(self, pool: Sequence[dict]):
        self._pool = [dict(c) for c in pool]

    def generate(self, context: dict, n: int) -> List[dict]:
        out = []
        for i, c in enumerate(self._pool[:n] if n else self._pool):
            c = dict(c)
            c.setdefault("identifier", f"cand_{i}")
            out.append(c)
        return out


class FrozenCheckpointGenerator(Generator):
    """STUB seam for the frozen epoch-221 PepGLAD checkpoint.

    The real implementation loads ``pepglad_ldm_epoch221`` and samples ``n`` peptides conditioned on
    ``context`` (target pocket / seed motif / non-canonical constraints), returning
    {identifier, seq, smiles}. That sampling is a GPU job and is intentionally NOT run here — this
    stub documents the exact interface the checkpoint must satisfy and raises if used without a real
    ``sample_fn`` injected. A DPO-tuned prior (A4 output consumed by dpo_peptide_trainer.py) is a
    drop-in replacement exposing the same ``generate`` method."""
    name = "frozen_epoch221_stub"

    def __init__(self, checkpoint: str = "pepglad_ldm_epoch221",
                 sample_fn: Optional[Callable[[dict, int], List[dict]]] = None):
        self.checkpoint = checkpoint
        self._sample_fn = sample_fn

    def generate(self, context: dict, n: int) -> List[dict]:
        if self._sample_fn is None:
            raise NotImplementedError(
                f"FrozenCheckpointGenerator({self.checkpoint}) is a seam: inject sample_fn "
                "(loads the checkpoint + samples on GPU) — not run in the CPU loop skeleton.")
        return self._sample_fn(context, n)


# --------------------------------------------------------------------------------------------
# Stage-5 interface: LEARN hook (pluggable). Records the emitted DPO pairs; real trainer swaps in.
# --------------------------------------------------------------------------------------------
class LearnHook:
    """Interface for the Learn phase. Contract: ``learn(pair_set, round_idx, config) -> dict``
    (a JSON-able record of what learning happened). The stub RECORDS/persists pairs only."""
    name = "learn"

    def learn(self, pair_set, round_idx: int, config: "LoopConfig") -> dict:  # pragma: no cover
        raise NotImplementedError


class RecordPairsLearnHook(LearnHook):
    """STUB learn phase: persists the versioned pair store and records counts. Does NOT train.
    The real DPO fine-tune (dpo_peptide_trainer.py using TRL DPOTrainer over the frozen prior)
    plugs in here — it would consume ``pair_set.to_trl_records()`` and emit a new prior checkpoint,
    which then becomes the next round's Generator."""
    name = "record_pairs_stub"

    def learn(self, pair_set, round_idx: int, config: "LoopConfig") -> dict:
        rec = {"trained": False, "reason": "stub learn hook — emitter only, no DPO training here",
               "n_pairs": len(getattr(pair_set, "pairs", [])),
               "stream_counts": pair_set.stream_counts() if hasattr(pair_set, "stream_counts") else {}}
        if config.out_dir:
            out = Path(config.out_dir) / f"round{round_idx}_dpo_pairs.jsonl"
            pair_set.write_jsonl(out)                         # full provenance moat store
            pair_set.write_jsonl(out.with_suffix(".trl.jsonl"), trl_only=True)  # TRL-ready
            rec["pairs_path"] = str(out)
            rec["trl_path"] = str(out.with_suffix(".trl.jsonl"))
        return rec


# --------------------------------------------------------------------------------------------
# Loop configuration + result
# --------------------------------------------------------------------------------------------
@dataclass
class LoopConfig:
    context: dict = field(default_factory=dict)     # generation conditioning (target/pocket/seed)
    n_generate: int = 0                              # 0 = "whatever the stub pool holds"
    n_select: int = 10                               # A2 batch size
    rounds: int = 1                                  # DMTA rounds
    # A3 gate thresholds (peptide_gate.GateThresholds fields; None -> module defaults)
    gate_thresholds: Optional[object] = None
    # A1 verify extras (physics_json for ΔG ingest, training CSV overrides)
    physics_json: Optional[str] = None
    perm_csv: Optional[str] = None
    perm_pred_csv: Optional[str] = None   # G4: precomputed per-candidate permeability CSV (lookup)
    stab_csv: Optional[str] = None
    # A2 select knobs
    diversity_weight: float = 0.25
    missing_policy: str = "impute_worst_observed"
    # A4 emit knobs
    prompt: str = ""                                 # DPO conditioning context string
    activity_exemplars: Optional[Sequence[object]] = None
    expert_exemplars: Optional[Sequence[object]] = None
    drop_weak_pairs: bool = False
    # output
    out_dir: Optional[str] = None

    # --- pluggable stage implementations (inject reals or mocks) ---
    generator: Optional[Generator] = None
    learn_hook: Optional[LearnHook] = None
    gate_fn: Optional[Callable] = None
    verify_fn: Optional[Callable] = None
    select_fn: Optional[Callable] = None
    emit_fn: Optional[Callable] = None


@dataclass
class RoundResult:
    round_idx: int
    n_generated: int
    gate: dict                     # GateResult.to_dict()
    n_gate_survivors: int
    n_expensive_verify_saved: int
    verified_ids: List[str]
    selection: dict                # SelectionResult.to_dict()
    selected_ids: List[str]
    learn: dict                    # learn-hook record
    n_pairs_emitted: int
    provenance: List[str]          # ordered per-stage log lines

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class LoopResult:
    rounds: List[RoundResult] = field(default_factory=list)
    config: dict = field(default_factory=dict)
    started_utc: str = ""
    finished_utc: str = ""
    summary: Dict[str, object] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "started_utc": self.started_utc,
            "finished_utc": self.finished_utc,
            "config": self.config,
            "summary": self.summary,
            "rounds": [r.to_dict() for r in self.rounds],
        }


# --------------------------------------------------------------------------------------------
# The orchestrator
# --------------------------------------------------------------------------------------------
def run_loop(config: LoopConfig) -> LoopResult:
    """Run the end-to-end DMTA loop for ``config.rounds`` rounds.

    Wiring (all real modules except generate + learn, which are the documented seams):
      generate (Generator, stub) -> gate (A3) -> verify (A1) -> select (A2) -> emit (A4) -> learn (stub)

    Fail-safe: a stage that returns nothing (empty gate survivors, empty selection) does NOT crash
    the loop — the round records the empty state and continues. Every stage appends to a per-round
    provenance log; a summary aggregates across rounds.
    """
    # resolve real modules for any stage not overridden
    gate_mod = _load("peptide_gate")
    verify_mod = _load("peptide_verify")
    select_mod = _load("peptide_select")
    dpo_mod = _load("dpo_pairs")

    generator = config.generator or PoolGenerator([])
    learn_hook = config.learn_hook or RecordPairsLearnHook()
    gate_fn = config.gate_fn or gate_mod.gate_candidates
    verify_fn = config.verify_fn or verify_mod.verify_batch
    select_fn = config.select_fn or select_mod.select_batch
    emit_fn = config.emit_fn or dpo_mod.emit_pairs
    gate_thresholds = config.gate_thresholds or gate_mod.GateThresholds()

    result = LoopResult(config=_config_summary(config),
                        started_utc=datetime.now(timezone.utc).isoformat())

    for r in range(config.rounds):
        prov: List[str] = []

        # ---- 1. GENERATE (pluggable stub) -------------------------------------------------
        pool = generator.generate(config.context, config.n_generate)
        prov.append(f"generate[{generator.name}]: {len(pool)} candidates")

        # ---- 2. A3 GATE (cheap; runs before expensive verify) -----------------------------
        gate_res = gate_fn(pool, gate_thresholds)
        survivors = gate_res.survivors()
        survivor_pool = [c for c in _with_ids(pool) if c["identifier"] in set(survivors)]
        prov.append(
            f"gate[A3]: {len(survivors)}/{gate_res.n_in} passed; "
            f"saved {gate_res.n_expensive_verify_saved} expensive verify calls")

        # ---- 3. A1 VERIFY (expensive; only survivors) -------------------------------------
        verify_kwargs = {}
        if config.physics_json:
            verify_kwargs["physics_json"] = config.physics_json
        if config.perm_csv:
            verify_kwargs["perm_csv"] = config.perm_csv
        if config.perm_pred_csv:
            verify_kwargs["perm_pred_csv"] = config.perm_pred_csv
        if config.stab_csv:
            verify_kwargs["stab_csv"] = config.stab_csv
        verified = verify_fn(survivor_pool, **verify_kwargs) if survivor_pool else []
        verified_ids = [getattr(p, "identifier", "") for p in verified]
        prov.append(f"verify[A1]: full property vector for {len(verified)} survivors")

        # ---- 4. A2 SELECT (Pareto + HVI + diversity) --------------------------------------
        sel = select_fn(verified, n_select=config.n_select,
                        diversity_weight=config.diversity_weight,
                        missing=config.missing_policy) if verified else _empty_selection(select_mod)
        selected_ids = list(getattr(sel, "selected", []) or [])
        prov.append(
            f"select[A2]: picked {len(selected_ids)} "
            f"(Pareto front {len(getattr(sel, 'pareto_front', []) or [])}, "
            f"diversity {getattr(sel, 'diversity_score', 0.0):.3f})")

        # ---- 5. A4 EMIT preference pairs (learn SIGNAL; not training) ----------------------
        pair_set = emit_fn(
            verified_pool=verified,
            selection_result=sel,
            gate_rejected_ids=gate_res.rejected_ids,
            prompt=config.prompt,
            activity_exemplars=config.activity_exemplars,
            expert_exemplars=config.expert_exemplars,
            drop_weak=config.drop_weak_pairs,
        )
        prov.append(f"emit[A4]: {len(pair_set.pairs)} DPO pairs {pair_set.stream_counts()}")

        # ---- 5b. LEARN (stub records pairs; real DPO trainer plugs in here) ----------------
        learn_rec = learn_hook.learn(pair_set, r, config)
        prov.append(f"learn[{learn_hook.name}]: trained={learn_rec.get('trained')}")

        result.rounds.append(RoundResult(
            round_idx=r,
            n_generated=len(pool),
            gate=gate_res.to_dict(),
            n_gate_survivors=len(survivors),
            n_expensive_verify_saved=gate_res.n_expensive_verify_saved,
            verified_ids=verified_ids,
            selection=sel.to_dict() if hasattr(sel, "to_dict") else {},
            selected_ids=selected_ids,
            learn=learn_rec,
            n_pairs_emitted=len(pair_set.pairs),
            provenance=prov,
        ))

    result.finished_utc = datetime.now(timezone.utc).isoformat()
    result.summary = _summarize(result)

    if config.out_dir:
        out = Path(config.out_dir) / "loop_result.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(result.to_dict(), indent=2) + "\n")

    return result


# --------------------------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------------------------
def _with_ids(pool: Sequence[dict]) -> List[dict]:
    out = []
    for i, c in enumerate(pool):
        c = dict(c)
        c.setdefault("identifier", f"cand_{i}")
        out.append(c)
    return out


def _empty_selection(select_mod):
    return select_mod.SelectionResult(
        objectives=[], directions={}, selected=[], pareto_front=[], hvi={}, acquisition={},
        diversity_score=1.0, diversity_metric="none", n_pool=0, n_dropped=0, dropped={},
        missing_policy="", notes=["no verified candidates to select from"])


def _config_summary(config: LoopConfig) -> dict:
    return {
        "n_generate": config.n_generate, "n_select": config.n_select, "rounds": config.rounds,
        "diversity_weight": config.diversity_weight, "missing_policy": config.missing_policy,
        "prompt": config.prompt, "physics_json": config.physics_json,
        "generator": (config.generator.name if config.generator else PoolGenerator([]).name),
        "learn_hook": (config.learn_hook.name if config.learn_hook else RecordPairsLearnHook().name),
    }


def _summarize(result: LoopResult) -> Dict[str, object]:
    total_gen = sum(r.n_generated for r in result.rounds)
    total_saved = sum(r.n_expensive_verify_saved for r in result.rounds)
    total_selected = sum(len(r.selected_ids) for r in result.rounds)
    total_pairs = sum(r.n_pairs_emitted for r in result.rounds)
    return {
        "rounds": len(result.rounds),
        "total_generated": total_gen,
        "total_expensive_verify_saved": total_saved,
        "total_selected": total_selected,
        "total_pairs_emitted": total_pairs,
    }


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Track A end-to-end DMTA loop (skeleton).")
    ap.add_argument("--pool-json", type=Path,
                    help="JSON list of {identifier,seq,smiles} — the stub generator's pool")
    ap.add_argument("--physics-json", help="MM-GBSA/FEP result JSON for the affinity field (A1)")
    ap.add_argument("--n-select", type=int, default=10)
    ap.add_argument("--rounds", type=int, default=1)
    ap.add_argument("--out-dir")
    args = ap.parse_args()

    pool = json.loads(args.pool_json.read_text()) if args.pool_json else []
    cfg = LoopConfig(
        n_select=args.n_select, rounds=args.rounds, physics_json=args.physics_json,
        out_dir=args.out_dir, generator=PoolGenerator(pool))
    res = run_loop(cfg)
    print(json.dumps(res.to_dict(), indent=2))
