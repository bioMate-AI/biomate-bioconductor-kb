"""Track A / A4 — DPO PREFERENCE-PAIR EMITTER (schema + emitter + provenance; NO training).

Per the execution plan (docs/20260925_PEPTIDE_EXECUTION_PLAN.md, item A4 — "the single most
defensible step") and the data-sourcing contract (docs/20260926_NEGATIVE_AND_EXPERT_DATA_SOURCING.md,
Part 4 A4): turn verify+select verdicts and the sourced negative/expert data into standard
``(chosen, rejected)`` preference pairs, ready to hand to a HuggingFace **TRL ``DPOTrainer``**.

    emit_pairs(...) -> PairSet    # then PairSet.to_trl_records() -> [{"prompt","chosen","rejected"}]

THIS MODULE DOES NOT TRAIN. It is the emitter + the schema + provenance only. The frozen
epoch-221 prior and the DPO fine-tune (``dpo_peptide_trainer.py``, not built here) consume this
module's output. Keeping emission separate from training is deliberate: the same pairs feed any
recipe, the emission is CPU-cheap and testable, and the moat (accumulating proprietary preference
data) lives in a versioned, provenance-tagged store — not baked into a training script.

Three preference STREAMS (per the sourcing doc, Part 4 A4)
---------------------------------------------------------
  1. VERIFY_SELECT — from THIS loop's own A1/A2 verdicts: a selected/Pareto candidate (chosen) vs
     a same-pool gated-out or dominated candidate (rejected). The signal we generate every round.
  2. ACTIVITY      — measured active ≻ inactive, from public bioactivity DBs (ExCAPE/ChEMBL/
     PubChem inactives). Steers generation away from inactive regions.
  3. EXPERT        — advanced ≻ abandoned, the crown jewel: within-patent hard negatives
     (SureChEMBL ⋈ ChEMBL max_phase). Also carries the customer's own accept/reject logs — the moat.

Each stream is emitted through the SAME schema + provenance so the trainer sees one uniform pair
contract. The data CONTRACT (what fields each source must provide) is defined below as
``PairSource`` inputs; the real ETL that fills them (ExCAPE/SureChEMBL/patent joins) plugs in by
handing this module lists of ``ExemplarPair`` seeds or A1/A2 objects — no scraper lives here.

Modality-general note
---------------------
The pair schema keys on ``prompt`` + a candidate REPRESENTATION (``chosen``/``rejected`` strings)
— by default the peptide sequence or SMILES. For small molecules, hand it SMILES and point the
downstream trainer at the small-molecule prior; nothing here is peptide-specific. The stream
definitions, dedup, conflict-resolution, and provenance are chemistry-agnostic.

CPU only. No training, no GPU, no network.
"""
from __future__ import annotations

import hashlib
import json
import logging
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

log = logging.getLogger(__name__)

SCHEMA_VERSION = "dpo-pairs/1.0"

# Preference streams (see module docstring / sourcing doc Part 4 A4).
STREAM_VERIFY_SELECT = "verify_select"    # this loop's own A1/A2 verdicts
STREAM_ACTIVITY = "activity"              # measured active >- inactive (public DBs)
STREAM_EXPERT = "expert"                  # advanced >- abandoned (patents) + customer accept/reject


# --------------------------------------------------------------------------------------------
# The standard preference-pair schema (TRL DPOTrainer contract + our provenance envelope)
# --------------------------------------------------------------------------------------------
@dataclass
class PreferencePair:
    """One (chosen >- rejected) pair, provenance-tagged and versioned.

    TRL ``DPOTrainer`` needs exactly ``{"prompt", "chosen", "rejected"}``. Everything else here is
    our provenance/versioning envelope that ``to_trl_record()`` strips off. The moat is that this
    envelope is retained + versioned in the pair store even though the trainer ignores it."""
    prompt: str                       # conditioning context (target/pocket/task); "" if unconditional
    chosen: str                       # preferred candidate representation (seq or SMILES)
    rejected: str                     # dispreferred candidate representation

    # --- provenance envelope (NOT fed to the trainer) ---
    stream: str = STREAM_VERIFY_SELECT
    chosen_id: str = ""
    rejected_id: str = ""
    margin: Optional[float] = None            # scalar preference strength if the source has one
    reason: str = ""                          # why chosen >- rejected (audit)
    provenance: Dict[str, str] = field(default_factory=dict)   # e.g. {"chosen":"measured","source":"ChEMBL"}
    weak: bool = False                        # patent-only negatives etc. are NOISY (weak label)
    schema_version: str = SCHEMA_VERSION
    created_utc: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    def pair_key(self) -> Tuple[str, str, str]:
        """Identity for dedup/conflict detection: (prompt, chosen-repr, rejected-repr)."""
        return (self.prompt, self.chosen, self.rejected)

    def to_trl_record(self) -> dict:
        """The exact record TRL DPOTrainer consumes."""
        return {"prompt": self.prompt, "chosen": self.chosen, "rejected": self.rejected}

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass
class ExemplarPair:
    """Data-contract INPUT for the activity/expert streams: a preference already known upstream.
    The real ETL (ExCAPE/ChEMBL/SureChEMBL joins) produces these; this module wraps them into the
    uniform ``PreferencePair`` schema with provenance. This is the seam where data sources plug in."""
    chosen: str                       # active / advanced compound (seq or SMILES)
    rejected: str                     # inactive / abandoned compound
    prompt: str = ""
    chosen_id: str = ""
    rejected_id: str = ""
    source: str = ""                  # "ExCAPE" | "ChEMBL" | "SureChEMBL_within_patent" | "customer_log" ...
    chosen_provenance: str = "measured"
    rejected_provenance: str = "measured"
    margin: Optional[float] = None
    weak: bool = False
    reason: str = ""


@dataclass
class PairSet:
    """A versioned, deduped set of preference pairs ready for TRL. This IS the moat artifact:
    provenance-tagged, per-stream, append-only in production."""
    pairs: List[PreferencePair] = field(default_factory=list)
    schema_version: str = SCHEMA_VERSION
    dropped_conflicts: List[dict] = field(default_factory=list)   # symmetric-conflict audit
    n_duplicates_merged: int = 0
    notes: List[str] = field(default_factory=list)

    def stream_counts(self) -> Dict[str, int]:
        c: Dict[str, int] = {}
        for p in self.pairs:
            c[p.stream] = c.get(p.stream, 0) + 1
        return c

    def to_trl_records(self) -> List[dict]:
        """The list you hand straight to ``datasets.Dataset.from_list(...)`` for TRL DPOTrainer."""
        return [p.to_trl_record() for p in self.pairs]

    def to_dict(self) -> dict:
        return {
            "schema_version": self.schema_version,
            "n_pairs": len(self.pairs),
            "stream_counts": self.stream_counts(),
            "n_duplicates_merged": self.n_duplicates_merged,
            "dropped_conflicts": self.dropped_conflicts,
            "pairs": [p.to_dict() for p in self.pairs],
            "notes": self.notes,
        }

    def write_jsonl(self, path: Path, *, trl_only: bool = False) -> None:
        """Persist. ``trl_only`` writes just {prompt,chosen,rejected} (feed to Dataset.from_json);
        otherwise writes the full provenance envelope per line (the versioned moat store)."""
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w") as fh:
            for p in self.pairs:
                rec = p.to_trl_record() if trl_only else p.to_dict()
                fh.write(json.dumps(rec) + "\n")


# --------------------------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------------------------
def _repr_of(candidate) -> Optional[str]:
    """Candidate representation string used as chosen/rejected: prefer SMILES (needed for
    non-canonical macrocycles), fall back to sequence, then id. Accepts a dict, an A2 Candidate,
    or an A1 PeptideProperties (duck-typed)."""
    if isinstance(candidate, dict):
        return candidate.get("smiles") or candidate.get("seq") or candidate.get("identifier")
    smiles = getattr(candidate, "smiles", None)
    seq = getattr(candidate, "sequence", None) or getattr(candidate, "seq", None)
    ident = getattr(candidate, "identifier", None)
    return smiles or seq or ident


def _id_of(candidate) -> str:
    if isinstance(candidate, dict):
        return candidate.get("identifier", "") or ""
    return getattr(candidate, "identifier", "") or ""


# --------------------------------------------------------------------------------------------
# Stream 1 — VERIFY_SELECT: pairs from THIS loop's A1 verify + A2 select verdicts.
# --------------------------------------------------------------------------------------------
def pairs_from_selection(
    verified_pool: Sequence[object],
    selection_result: object,
    *,
    prompt: str = "",
    gate_rejected_ids: Optional[Sequence[str]] = None,
    max_pairs: Optional[int] = None,
    require_provenance: Optional[str] = None,
) -> List[PreferencePair]:
    """Emit chosen>-rejected pairs from an A2 ``SelectionResult`` over an A1-verified pool.

    Preference logic (honest, non-fabricating):
      * CHOSEN  = ids in ``selection_result.selected`` (the picked batch) — the loop preferred them.
      * REJECTED = same-pool candidates the loop did NOT pick, preferring the strongest negatives:
          (a) candidates gated out before verify (``gate_rejected_ids``) — hard fails, cleanest negs,
          (b) then dominated (non-Pareto) candidates.
        We deliberately do NOT pair a chosen against another chosen (no within-batch ordering is
        claimed) and do NOT invent a margin the data doesn't support.
      * margin = HVI(chosen) - HVI(rejected) when both are in ``selection_result.hvi`` (a real,
        observed acquisition gap); else None.

    Parameters
    ----------
    verified_pool : the A1 PeptideProperties list (for representation + provenance lookup).
    selection_result : A2 SelectionResult (uses ``.selected``, ``.pareto_front``, ``.hvi``).
    prompt : conditioning context string (target/pocket) — "" for unconditional priors.
    gate_rejected_ids : ids rejected by A3 gate (strongest, cleanest negatives).
    max_pairs : cap the emitted count (batch-budget the DPO set).
    require_provenance : if set (e.g. "measured"), only emit a pair when the CHOSEN candidate's
        driving objective has that provenance — lets you restrict to physics-backed preferences.
    """
    by_id = {_id_of(p): p for p in verified_pool}
    selected = list(getattr(selection_result, "selected", []) or [])
    pareto = set(getattr(selection_result, "pareto_front", []) or [])
    hvi = dict(getattr(selection_result, "hvi", {}) or {})
    gate_rejected = list(gate_rejected_ids or [])

    # negatives, strongest first: gate-rejected, then dominated (non-Pareto, non-selected)
    selected_set = set(selected)
    dominated = [i for i in by_id
                 if i not in selected_set and i not in pareto and i not in set(gate_rejected)]
    negatives = gate_rejected + dominated
    if not negatives:
        # last resort: any non-selected pool member (weak negative — Pareto but not picked)
        negatives = [i for i in by_id if i not in selected_set]

    out: List[PreferencePair] = []
    for cid in selected:
        cpos = by_id.get(cid)
        pos_repr = _repr_of(cpos) if cpos is not None else cid
        if not pos_repr:
            continue
        if require_provenance is not None and cpos is not None:
            provs = {getattr(pv, "provenance", "") for pv in
                     (cpos.scored_fields().values() if hasattr(cpos, "scored_fields") else [])}
            if require_provenance not in provs:
                continue
        for nid in negatives:
            if nid == cid:
                continue
            cneg = by_id.get(nid)
            neg_repr = _repr_of(cneg) if cneg is not None else nid
            if not neg_repr or neg_repr == pos_repr:
                continue
            margin = None
            if cid in hvi and nid in hvi:
                margin = float(hvi[cid] - hvi[nid])
            weak = nid not in set(gate_rejected)   # gate-fails are clean; dominated are weaker
            reason = ("selected over gate-rejected" if nid in set(gate_rejected)
                      else "selected over dominated")
            prov = {"stream": STREAM_VERIFY_SELECT}
            if cpos is not None:
                prov["chosen"] = _dominant_provenance(cpos)
            if cneg is not None:
                prov["rejected"] = _dominant_provenance(cneg)
            out.append(PreferencePair(
                prompt=prompt, chosen=pos_repr, rejected=neg_repr,
                stream=STREAM_VERIFY_SELECT, chosen_id=cid, rejected_id=nid,
                margin=margin, reason=reason, provenance=prov, weak=weak))
            if max_pairs and len(out) >= max_pairs:
                return out
    return out


def _dominant_provenance(props) -> str:
    """Coarse provenance tag for a verified candidate = the 'best' provenance present
    (measured > predicted > proxy > unavailable)."""
    order = {"measured": 3, "predicted": 2, "proxy": 1, "unavailable": 0}
    best, best_rank = "unavailable", 0
    fields = props.scored_fields().values() if hasattr(props, "scored_fields") else []
    for pv in fields:
        p = getattr(pv, "provenance", "unavailable")
        if order.get(p, 0) > best_rank:
            best, best_rank = p, order.get(p, 0)
    return best


# --------------------------------------------------------------------------------------------
# Streams 2 & 3 — ACTIVITY / EXPERT: wrap upstream ExemplarPairs into the uniform schema.
# --------------------------------------------------------------------------------------------
def pairs_from_exemplars(
    exemplars: Sequence[ExemplarPair],
    stream: str,
) -> List[PreferencePair]:
    """Wrap already-known preferences (active>-inactive, advanced>-abandoned, customer accept>-reject)
    into the uniform ``PreferencePair`` schema. This is the seam where external data sources plug in:
    the ETL (ExCAPE filter, SureChEMBL⋈max_phase within-patent join, customer log parser) produces
    ``ExemplarPair``s; this function attaches stream + provenance and normalizes them."""
    out: List[PreferencePair] = []
    for ex in exemplars:
        if not ex.chosen or not ex.rejected or ex.chosen == ex.rejected:
            continue
        out.append(PreferencePair(
            prompt=ex.prompt, chosen=ex.chosen, rejected=ex.rejected,
            stream=stream, chosen_id=ex.chosen_id, rejected_id=ex.rejected_id,
            margin=ex.margin,
            reason=ex.reason or f"{stream}: {ex.source}",
            provenance={"chosen": ex.chosen_provenance, "rejected": ex.rejected_provenance,
                        "source": ex.source},
            weak=ex.weak))
    return out


# --------------------------------------------------------------------------------------------
# Assembly: dedup + symmetric-conflict resolution -> the final versioned PairSet.
# --------------------------------------------------------------------------------------------
def emit_pairs(
    *,
    verified_pool: Optional[Sequence[object]] = None,
    selection_result: Optional[object] = None,
    gate_rejected_ids: Optional[Sequence[str]] = None,
    prompt: str = "",
    activity_exemplars: Optional[Sequence[ExemplarPair]] = None,
    expert_exemplars: Optional[Sequence[ExemplarPair]] = None,
    max_verify_select_pairs: Optional[int] = None,
    require_provenance: Optional[str] = None,
    drop_weak: bool = False,
) -> PairSet:
    """Emit a deduped, conflict-resolved ``PairSet`` across all three streams.

    Any subset of inputs may be provided:
      * verified_pool + selection_result (+ gate_rejected_ids) -> STREAM_VERIFY_SELECT
      * activity_exemplars -> STREAM_ACTIVITY
      * expert_exemplars   -> STREAM_EXPERT

    Post-processing (chemistry-agnostic):
      * DEDUP identical (prompt, chosen, rejected) triples (keep first, count merges).
      * SYMMETRIC-CONFLICT resolution: if both (A>-B) and (B>-A) appear (contradictory preference),
        BOTH are dropped into ``dropped_conflicts`` — never silently pick one. (Common when a noisy
        patent-only negative contradicts a measured-activity pair.)
      * ``drop_weak`` optionally removes weak-labelled pairs (patent-only negatives, dominated negs).

    Returns a ``PairSet`` (its ``.to_trl_records()`` is the DPOTrainer input; ``.write_jsonl()``
    persists the versioned moat store). Never trains.
    """
    collected: List[PreferencePair] = []

    if selection_result is not None and verified_pool is not None:
        collected += pairs_from_selection(
            verified_pool, selection_result, prompt=prompt,
            gate_rejected_ids=gate_rejected_ids, max_pairs=max_verify_select_pairs,
            require_provenance=require_provenance)
    if activity_exemplars:
        collected += pairs_from_exemplars(activity_exemplars, STREAM_ACTIVITY)
    if expert_exemplars:
        collected += pairs_from_exemplars(expert_exemplars, STREAM_EXPERT)

    notes: List[str] = []
    if drop_weak:
        before = len(collected)
        collected = [p for p in collected if not p.weak]
        if before != len(collected):
            notes.append(f"dropped {before - len(collected)} weak-labelled pairs (drop_weak=True)")

    # dedup + symmetric-conflict detection
    seen: Dict[Tuple[str, str, str], PreferencePair] = {}
    reverse_keys = set()
    n_dupes = 0
    conflicts: List[dict] = []
    kept: List[PreferencePair] = []
    for p in collected:
        key = p.pair_key()
        rev = (p.prompt, p.rejected, p.chosen)
        if key in seen:
            n_dupes += 1
            continue
        if rev in seen:
            # contradictory preference — drop both
            other = seen.pop(rev)
            if other in kept:
                kept.remove(other)
            conflicts.append({
                "prompt": p.prompt, "a": p.chosen, "b": p.rejected,
                "reason": "symmetric conflict: both (a>-b) and (b>-a) present",
                "streams": [other.stream, p.stream]})
            continue
        seen[key] = p
        kept.append(p)

    if conflicts:
        notes.append(f"dropped {len(conflicts)} symmetric-conflict pair(s)")

    return PairSet(pairs=kept, dropped_conflicts=conflicts,
                   n_duplicates_merged=n_dupes, notes=notes)


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(
        description="A4 DPO preference-pair emitter (schema + emitter + provenance; NO training).")
    ap.add_argument("--exemplars-json", type=Path,
                    help="JSON list of ExemplarPair dicts (activity or expert stream)")
    ap.add_argument("--stream", default=STREAM_ACTIVITY,
                    choices=[STREAM_ACTIVITY, STREAM_EXPERT])
    ap.add_argument("--out", type=Path, help="write full provenance JSONL")
    ap.add_argument("--trl-out", type=Path, help="write TRL {prompt,chosen,rejected} JSONL")
    args = ap.parse_args()

    exemplars: List[ExemplarPair] = []
    if args.exemplars_json:
        for r in json.loads(args.exemplars_json.read_text()):
            exemplars.append(ExemplarPair(**r))
    ps = emit_pairs(**{f"{args.stream}_exemplars": exemplars})
    if args.out:
        ps.write_jsonl(args.out)
    if args.trl_out:
        ps.write_jsonl(args.trl_out, trl_only=True)
    print(json.dumps(ps.to_dict(), indent=2))
