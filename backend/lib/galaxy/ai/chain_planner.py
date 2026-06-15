"""
Typed-port chain planner (C2 prototype).

Given a starting input artifact type and (optionally) a goal output type or
keyword, search the workflow catalog for multi-step DAGs that join
`workflows.output_types` → `workflows.input_types` across the catalog.

This is an *additive* Tier 2.5 — it does not replace the curated chain
lookup in `unified_workflow_search.search_chains`. It is intended to be
called only when the curated lookup returns no high-confidence match,
and the result is returned to the user as a "planned chain" candidate.

Status: prototype. Runs against the existing partial typed-port coverage
(~54% input / 47% output). Quality of plans is bounded by that coverage.
Backfilling typed ports (proposal item C1) is the unlock for production.

Design notes:
- BFS over a workflow-level edge graph. No LLM in the inner loop.
- Edge A→B exists iff at least one of A's output_types satisfies one of
  B's input_types under the semantic alias table.
- Aliases are reused from `workflow_chain._TYPE_ALIASES` (single source of
  truth). We import lazily to avoid a hard dependency on the webapps layer
  when this module is imported standalone (e.g., from tests or CLI).
- Scoring is deliberately simple: shorter plans win ties; domain
  coherence and goal-keyword presence add small bonuses.
"""

from __future__ import annotations

import json
import logging
import os
import sqlite3
from collections import deque
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Set, Tuple

log = logging.getLogger(__name__)

_DEFAULT_DB_PATH = Path(
    os.environ.get(
        "BIOMATE_AI_TOOLS_DB",
        Path(__file__).resolve().parents[3] / "database" / "galaxy_ai_tools.db",
    )
)


def _load_type_aliases() -> Dict[str, List[str]]:
    """Reuse the canonical alias table from workflow_chain when available."""
    try:
        from galaxy.webapps.galaxy.api.workflow_chain import (  # type: ignore
            _TYPE_ALIASES as _ALIASES,
        )

        return dict(_ALIASES)
    except Exception:  # pragma: no cover - import fallback for standalone runs
        # Conservative built-in copy. Keep in sync with workflow_chain.py.
        return {
            "bam": ["bam", "input_bam", "alignments", "reads_bam", "input"],
            "vcf": ["vcf", "input_vcf", "variants", "variant_file"],
            "fastq": ["fastq", "reads", "input", "samplesheet"],
            "counts_matrix": ["counts_matrix", "counts", "matrix", "input", "samplesheet"],
            "tpm_matrix": ["tpm_matrix", "tpm", "expression_matrix", "counts_matrix"],
            "bed_peaks": ["bed_peaks", "peaks", "bed", "input"],
            "fasta": ["fasta", "genome", "reference", "input"],
            "fasta_assembly": ["fasta_assembly", "fasta", "assembly", "input"],
            "tsv_taxonomy": ["tsv_taxonomy", "taxonomy", "tsv", "input"],
            "h5ad": ["h5ad", "anndata", "input"],
            "csv": ["csv", "samplesheet", "input"],
            "tsv_proteins": ["tsv_proteins", "protein_groups", "input"],
            "bigwig": ["bigwig", "signal", "coverage"],
            "multiqc_report": ["multiqc_report", "qc_report"],
            "results_dir": ["results_dir", "outdir", "output_dir"],
        }


_ALIASES = _load_type_aliases()

# Aliases that are wrong-direction for planning: the production
# workflow_chain.py alias table is biased toward nf-core conventions where
# a "samplesheet" CSV *describes* fastqs/bams. That bias is correct when
# validating a curated chain's hand-authored handoffs but wrong for
# graph-search: it lets fastq spuriously satisfy a `samplesheet` input,
# letting the planner skip the actual upstream pipeline.
# We strip these at load time inside the planner only — production
# `_TYPE_ALIASES` is untouched.
_PLANNER_ALIAS_BLOCKLIST = {
    ("fastq", "samplesheet"),
    ("fastq", "input"),
    ("counts_matrix", "input"),
    ("counts_matrix", "samplesheet"),
    ("bam", "input"),
    ("vcf", "input"),
    ("fasta", "input"),
    ("h5ad", "input"),
    ("csv", "input"),
}


def _filter_aliases_for_planning(raw: Dict[str, List[str]]) -> Dict[str, List[str]]:
    out: Dict[str, List[str]] = {}
    for key, vals in raw.items():
        out[key] = [v for v in vals if (key, v) not in _PLANNER_ALIAS_BLOCKLIST]
    return out


_PLANNER_ALIASES = _filter_aliases_for_planning(_ALIASES)


def _type_satisfies(out_type: str, in_type: str) -> bool:
    """True iff `out_type` can feed `in_type` per the planner alias table.

    Strict matching: equality or explicit alias entry only. The loose
    bidirectional substring fallback that the prototype had caused too many
    spurious matches (e.g. "fastq" satisfying any input containing the
    substring "fastq", or vice versa). Production `_TYPE_ALIASES` is
    intentionally permissive for *validating* curated handoffs; the planner
    must be stricter because it is *discovering* handoffs.
    """
    if out_type == in_type:
        return True
    aliases = _PLANNER_ALIASES.get(out_type, [])
    return in_type in aliases


def _any_satisfies(out_types: Iterable[str], in_types: Iterable[str]) -> bool:
    return any(_type_satisfies(o, i) for o in out_types for i in in_types)


# Heuristic vocabulary of strings that look like parameter names rather
# than data type kinds. If >50% of a workflow's input_types match, we
# treat the workflow as unindexable for planning (drug-discovery indexer
# bug at index_all_workflows.py:309 — params being stored as input_types).
_PARAM_NAME_FRAGMENTS = (
    "_mode", "_file", "_path", "_threshold", "_cutoff", "_score",
    "_size", "_steps", "_routes", "_depth", "_dose", "max_", "min_",
    "n_cpus", "use_aws", "_seed", "_method", "_factor", "_weight",
    "_route", "_dir", "_unit", "_ratio", "_column", "_group",
    "publish_", "enable_", "outdir",
)


def _looks_like_param_name(token: str) -> bool:
    t = token.lower()
    if t in {"mock_mode", "gpu", "x", "_ecr", "_useaws", "chem_container"}:
        return True
    return any(frag in t for frag in _PARAM_NAME_FRAGMENTS)


def _is_meaningful_input_types(types: List[str]) -> bool:
    """Reject obvious garbage: placeholder ['input'] or majority-param-names."""
    if not types:
        return False
    if types == ["input"]:
        return False
    junk = sum(1 for t in types if _looks_like_param_name(t))
    # Require at least one non-junk token AND a junk ratio below 50%.
    return junk < len(types) / 2 and (len(types) - junk) >= 1


@dataclass
class WorkflowNode:
    id: int
    name: str
    domain: str
    description: str
    input_types: List[str]
    output_types: List[str]


@dataclass
class PlannedChain:
    """A candidate multi-step chain produced by the planner."""

    steps: List[Dict[str, Any]] = field(default_factory=list)
    connections: List[Dict[str, Any]] = field(default_factory=list)
    domains_covered: List[str] = field(default_factory=list)
    total_score: float = 0.0
    notes: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def _load_typed_workflows(db_path: Path) -> List[WorkflowNode]:
    """Pull all workflows that have *both* input and output types populated."""
    conn = sqlite3.connect(str(db_path))
    try:
        rows = conn.execute(
            "SELECT id, name, COALESCE(domain,''), COALESCE(description,''), "
            "       input_types, output_types "
            "FROM workflows "
            "WHERE input_types NOT IN ('','[]','null') "
            "  AND output_types NOT IN ('','[]','null') "
            "  AND executable=1"
        ).fetchall()
    finally:
        conn.close()

    nodes: List[WorkflowNode] = []
    for wid, name, domain, desc, in_raw, out_raw in rows:
        try:
            ins = [t for t in json.loads(in_raw) if isinstance(t, str)]
            outs = [t for t in json.loads(out_raw) if isinstance(t, str)]
        except Exception:
            continue
        if not ins or not outs:
            continue
        if not _is_meaningful_input_types(ins):
            # Workflows where input_types is a placeholder or list of param
            # names are unusable for graph-search planning. Skip them rather
            # than emit junk plans. The underlying indexer bug should be
            # fixed separately (see implementation notes doc).
            log.debug("chain_planner: skipping %s — input_types looks like params/placeholder: %s",
                      name, ins)
            continue
        nodes.append(
            WorkflowNode(
                id=wid,
                name=name,
                domain=domain,
                description=desc or "",
                input_types=ins,
                output_types=outs,
            )
        )
    return nodes


def _expand_types(types: Sequence[str]) -> Set[str]:
    """Closure of `types` under the alias table (treating each as a possible output)."""
    out: Set[str] = set()
    for t in types:
        out.add(t)
        out.update(_PLANNER_ALIASES.get(t, []))
    return out


def _score_chain(steps: List[WorkflowNode], goal_keyword: Optional[str]) -> Tuple[float, List[str]]:
    """Simple, defensible scoring. Lower step count wins ties; domain coherence + goal match add bonuses."""
    notes: List[str] = []
    base = 10.0 / max(1, len(steps))  # 10/1=10, 10/2=5, 10/3=3.33 — shorter beats longer
    domains = {s.domain for s in steps if s.domain}
    coherence_bonus = 0.5 if 1 < len(steps) and len(domains) <= 2 else 0.0
    if coherence_bonus:
        notes.append(f"domain_coherence_bonus(+{coherence_bonus}): domains={sorted(domains)}")
    goal_bonus = 0.0
    if goal_keyword:
        kw = goal_keyword.lower()
        for s in steps:
            if kw in (s.name or "").lower() or kw in (s.description or "").lower():
                goal_bonus = 1.0
                notes.append(f"goal_keyword_match(+1.0): step '{s.name}' matches '{kw}'")
                break
    return base + coherence_bonus + goal_bonus, notes


def _step_dict(node: WorkflowNode, order: int) -> Dict[str, Any]:
    return {
        "order": order,
        "workflow_id": node.id,
        "workflow_name": node.name,
        "domain": node.domain,
        "input_types": node.input_types,
        "output_types": node.output_types,
    }


def _connection_dict(prev: WorkflowNode, nxt: WorkflowNode) -> Dict[str, Any]:
    bridge = [
        (o, i)
        for o in prev.output_types
        for i in nxt.input_types
        if _type_satisfies(o, i)
    ]
    return {
        "from": prev.name,
        "to": nxt.name,
        "via": bridge[:3],  # cap noise
    }


def plan_chains(
    start_input_types: Sequence[str],
    goal: Optional[str] = None,
    goal_output_types: Optional[Sequence[str]] = None,
    max_steps: int = 4,
    top_k: int = 3,
    db_path: Optional[Path] = None,
) -> List[PlannedChain]:
    """
    Search for multi-step DAGs starting from `start_input_types`.

    Args:
        start_input_types: artifact types the user already has (e.g. ["fastq"]).
        goal: free-text goal hint used for keyword scoring (e.g. "differential expression").
        goal_output_types: terminate when a step produces any of these (e.g. ["enrichment_results"]).
        max_steps: cap on plan length to keep the search tractable.
        top_k: number of plans to return.
        db_path: override DB location (mainly for tests).

    Returns:
        Up to `top_k` PlannedChain objects, sorted by score descending.
    """
    if not start_input_types:
        return []
    if max_steps < 1:
        return []

    db_path = db_path or _DEFAULT_DB_PATH
    if not db_path.exists():
        log.warning("chain_planner: DB not found at %s", db_path)
        return []

    nodes = _load_typed_workflows(db_path)
    if not nodes:
        return []

    start_set = _expand_types(start_input_types)
    goal_set = set(goal_output_types or [])

    # Roots: workflows whose declared inputs are satisfied by what the user has.
    roots = [
        n for n in nodes
        if any(_type_satisfies(o, i) for o in start_set for i in n.input_types)
    ]

    # Build adjacency: prev → next when any output of prev satisfies any input of next.
    # Prebuilt as adjacency list, capped to keep BFS tractable.
    adj: Dict[int, List[WorkflowNode]] = {n.id: [] for n in nodes}
    by_input: Dict[str, List[WorkflowNode]] = {}
    for n in nodes:
        for i in n.input_types:
            by_input.setdefault(i, []).append(n)

    for n in nodes:
        seen_ids: Set[int] = set()
        for o in n.output_types:
            for alias in [o] + _PLANNER_ALIASES.get(o, []):
                for cand in by_input.get(alias, []):
                    if cand.id == n.id or cand.id in seen_ids:
                        continue
                    seen_ids.add(cand.id)
                    adj[n.id].append(cand)

    plans: List[PlannedChain] = []
    seen_signatures: Set[Tuple[int, ...]] = set()

    def _emit(path: List[WorkflowNode]) -> None:
        sig = tuple(n.id for n in path)
        if sig in seen_signatures:
            return
        seen_signatures.add(sig)
        score, notes = _score_chain(path, goal)
        chain = PlannedChain(
            steps=[_step_dict(n, i + 1) for i, n in enumerate(path)],
            connections=[_connection_dict(path[i], path[i + 1]) for i in range(len(path) - 1)],
            domains_covered=sorted({n.domain for n in path if n.domain}),
            total_score=score,
            notes=notes,
        )
        plans.append(chain)

    # BFS up to max_steps. Each path is a list of nodes.
    queue: deque = deque((n, [n]) for n in roots)
    while queue:
        node, path = queue.popleft()

        # A path is a candidate if (a) goal_output_types matches, or (b) no
        # goal_output_types given AND we're at >=1 step.
        matches_goal = (
            not goal_set
            or any(_type_satisfies(o, g) for o in node.output_types for g in goal_set)
            or any(o in goal_set for o in node.output_types)
        )
        if matches_goal:
            _emit(path)

        if len(path) >= max_steps:
            continue

        # Expand. Avoid cycles by skipping nodes already in path.
        in_path = {n.id for n in path}
        for nxt in adj.get(node.id, []):
            if nxt.id in in_path:
                continue
            queue.append((nxt, path + [nxt]))

    # Rank and trim. Tie-break: prefer fewer steps, then alphabetic for determinism.
    plans.sort(key=lambda c: (-c.total_score, len(c.steps), c.steps[0]["workflow_name"]))
    return plans[:top_k]


# CLI for quick exploration: python -m galaxy.ai.chain_planner --start fastq --goal "enrichment"
def _cli() -> None:  # pragma: no cover
    import argparse

    p = argparse.ArgumentParser()
    p.add_argument("--start", nargs="+", required=True, help="starting input types")
    p.add_argument("--goal", default=None, help="free-text goal keyword")
    p.add_argument("--goal-types", nargs="*", default=None, help="terminate when these output types reached")
    p.add_argument("--max-steps", type=int, default=4)
    p.add_argument("--top-k", type=int, default=3)
    args = p.parse_args()

    plans = plan_chains(
        start_input_types=args.start,
        goal=args.goal,
        goal_output_types=args.goal_types,
        max_steps=args.max_steps,
        top_k=args.top_k,
    )
    if not plans:
        print("no plans found")
        return
    for i, c in enumerate(plans, 1):
        print(f"\n=== Plan {i} (score={c.total_score:.2f}, steps={len(c.steps)}) ===")
        for s in c.steps:
            print(f"  {s['order']}. {s['workflow_name']:50s} [{s['domain']:18s}] in={s['input_types']} out={s['output_types']}")
        for note in c.notes:
            print(f"  · {note}")


if __name__ == "__main__":  # pragma: no cover
    _cli()
