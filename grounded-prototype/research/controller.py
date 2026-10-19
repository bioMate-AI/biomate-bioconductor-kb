"""
Deep-research controller — the HARNESS-owned loop.

Division of labour (the whole point):
  * HARNESS (this file): owns the loop + invariants — budget, PARALLEL fan-out,
    dedup, a deterministic verifier (did this round yield NEW authoritative
    evidence, or are we spinning?), termination. Deterministic, bounded, auditable.
  * LLM (injected `decompose_fn` / `assess_fn`): owns judgment — break the
    question into sub-questions, and judge sufficiency / name the gaps to drill.
  * SKILLS (registry playbooks + router): per-source query idioms and the
    use-case -> source-set mapping.
  * FUSION/SYNTHESIS: the existing Grounded engine (trust lattice + citations +
    boundary) — the controller gathers evidence, the engine grounds the answer.

Two axes of "deeper": BREADTH (parallel sub-questions x routed sources, here) and
DEPTH (drill into gaps across rounds, here). Both are budget-bounded.

retrieve_fn(source_id, subquestion) -> List[Source] is injected: production wires
it to federated_query / query_database / ich_corpus / the Grounded retrievers;
tests inject a fake, so the loop is verifiable with no network or LLM.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional

from engine.answer import assemble
from engine.models import GroundedAnswer, Source
from engine.retrieve import retrieve

from . import router


@dataclass
class Budget:
    max_rounds: int = 3          # how DEEP (drill iterations)
    max_breadth: int = 4         # sub-questions per round
    max_parallel: int = 6        # concurrent retrievals
    max_evidence: int = 40       # stop once this much evidence is gathered
    max_sources_per_subq: int = 5


@dataclass
class Verdict:
    sufficient: bool
    gaps: List[str] = field(default_factory=list)
    follow_up: List[str] = field(default_factory=list)


@dataclass
class RoundTrace:
    round: int
    subquestions: List[str]
    intents: List[str]
    retrievals: int               # (subq x source) fan-out size this round
    new_evidence: int
    new_authoritative: int
    sufficient: bool
    gaps: List[str]


@dataclass
class ResearchResult:
    question: str
    answer: GroundedAnswer
    rounds: int
    trace: List[RoundTrace]
    sources_used: List[str]
    stop_reason: str


# ── default judgment nodes (rule stand-ins; production injects the LLM) ───────

def _default_decompose(question: str) -> List[str]:
    return [question]


def _default_assess(question: str, evidence: List[Source]) -> Verdict:
    # Rule stand-in: sufficient once >=2 authoritative sources are gathered.
    authoritative = [s for s in evidence if s.tier.is_authoritative]
    return Verdict(sufficient=len(authoritative) >= 2)


def research(
    question: str,
    user: str,
    *,
    retrieve_fn: Callable[[str, str], List[Source]],
    decompose_fn: Optional[Callable[[str], List[str]]] = None,
    assess_fn: Optional[Callable[[str, List[Source]], Verdict]] = None,
    intent_fn: Optional[Callable[[str], str]] = None,
    budget: Optional[Budget] = None,
) -> ResearchResult:
    budget = budget or Budget()
    decompose_fn = decompose_fn or _default_decompose
    assess_fn = assess_fn or _default_assess

    collected: Dict[str, Source] = {}     # id -> Source (dedup)
    trace: List[RoundTrace] = []
    stop_reason = "max_rounds"

    subqs = decompose_fn(question)[: budget.max_breadth]
    round_no = 0

    while subqs and round_no < budget.max_rounds and len(collected) < budget.max_evidence:
        round_no += 1

        # Plan this round: route each sub-question to its source set.
        tasks = []           # (subq, source_id)
        intents: List[str] = []
        for sq in subqs:
            srcs, intent = router.route(sq, intent_fn=intent_fn,
                                        max_sources=budget.max_sources_per_subq)
            intents.append(intent)
            for s in srcs:
                tasks.append((sq, s.id))

        # PARALLEL fan-out (breadth) — retrieve all (subq x source) concurrently.
        new_sources: List[Source] = []
        if tasks:
            with ThreadPoolExecutor(max_workers=budget.max_parallel) as ex:
                futs = {ex.submit(_safe_retrieve, retrieve_fn, sid, sq): (sq, sid)
                        for (sq, sid) in tasks}
                for fut in as_completed(futs):
                    for src in fut.result():
                        if src.id not in collected:
                            collected[src.id] = src
                            new_sources.append(src)

        # Deterministic verifier (harness): new AUTHORITATIVE evidence this round?
        new_auth = [s for s in new_sources if s.tier.is_authoritative]

        # LLM judgment: sufficiency + gaps.
        verdict = assess_fn(question, list(collected.values()))

        trace.append(RoundTrace(
            round=round_no, subquestions=list(subqs), intents=intents,
            retrievals=len(tasks), new_evidence=len(new_sources),
            new_authoritative=len(new_auth), sufficient=verdict.sufficient,
            gaps=verdict.gaps,
        ))

        if verdict.sufficient:
            stop_reason = "sufficient"; break
        if not new_auth:
            # Anti-spin: a round that added no new authoritative evidence won't be
            # rescued by drilling the same gaps — stop rather than burn budget.
            stop_reason = "no_new_evidence"; break
        subqs = verdict.follow_up[: budget.max_breadth]   # DEPTH: drill the gaps
        if not subqs:
            stop_reason = "no_follow_up"; break

    # Final synthesis via the Grounded engine: trust lattice + citations + boundary.
    # min_score=0: the gathered evidence is ALREADY curated (each item was retrieved
    # for a sub-question), so we don't re-apply the lexical relevance floor against
    # the top-level question — that would drop evidence relevant to a sub-question.
    # The isolation gate + tier lattice still apply; scoring only orders the set.
    gathered = list(collected.values())
    scored, isolation = retrieve(question, gathered, requesting_user=user,
                                 limit=max(8, len(gathered)), min_score=0.0)
    answer = assemble(question, scored, isolation, requesting_user=user)

    return ResearchResult(
        question=question, answer=answer, rounds=round_no, trace=trace,
        sources_used=[s.id for s in gathered], stop_reason=stop_reason,
    )


def _safe_retrieve(fn: Callable[[str, str], List[Source]], source_id: str,
                   subq: str) -> List[Source]:
    """A dead source must not kill the round."""
    try:
        return list(fn(source_id, subq) or [])
    except Exception:
        return []
