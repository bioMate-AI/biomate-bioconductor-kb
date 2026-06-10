"""LLM-judge grounding of curated-chain placeholder names.

The 29 curated chains in `workflow_chains` reference 53 unique workflow
names that DON'T exist in the `workflows` table — they're descriptive
placeholders (e.g. `vep_annotation`, `gene_set_enrichment_analysis`,
`pocket_detection_druggability`). The verifier handles this by treating
them as known regardless, but it's debt: the chains can't actually
execute end-to-end without manual substitution at run time.

This script proposes a real catalog workflow for each placeholder by:
1. Retrieving top BM25 candidates from the workflows catalog using the
   placeholder name + role + upstream/downstream neighbor context.
2. Asking an LLM (Haiku) to pick the best fit + confidence + reason.

Output: JSONL of `{placeholder, proposed_workflow, confidence, reason,
chains, role, upstream, downstream}`.

Cost: ~$0.005/placeholder × 53 = ~$0.25 total. Wall clock ~5 min.

Usage:
    export PYTHONPATH=$PWD/backend/lib
    set -a && . backend/.env && set +a
    python -m galaxy.ai.chain_composer.placeholder_grounder \
        --output docs/20260610_PLACEHOLDER_GROUNDING_PROPOSAL.jsonl \
        --summary docs/20260610_PLACEHOLDER_GROUNDING_SUMMARY.md
"""

from __future__ import annotations

import argparse
import json
import logging
import sqlite3
import sys
import time
from collections import defaultdict
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from .llm_adapter import default_ner_llm
from .retrieval import retrieve_workflows

log = logging.getLogger(__name__)

_DEFAULT_DB = Path(__file__).resolve().parents[4] / "database" / "galaxy_ai_tools.db"


def _inventory_placeholders(db_path: Path) -> List[Dict[str, Any]]:
    """Collect all placeholder step names + their contextual neighbors."""
    conn = sqlite3.connect(str(db_path))
    try:
        catalog = {r[0] for r in conn.execute(
            "SELECT name FROM workflows WHERE executable=1") if r[0]}
        rows = conn.execute("SELECT name, steps FROM workflow_chains").fetchall()
    finally:
        conn.close()

    placeholders: Dict[str, Dict[str, Any]] = {}
    for chain_name, raw in rows:
        try:
            steps = json.loads(raw or "[]")
        except Exception:
            continue
        names = [s.get("workflow_name") for s in steps if isinstance(s, dict)]
        for i, s in enumerate(steps):
            wn = s.get("workflow_name") if isinstance(s, dict) else None
            if not wn or wn in catalog:
                continue
            p = placeholders.setdefault(wn, {
                "name": wn,
                "chains": [],
                "roles": set(),
                "upstream": set(),
                "downstream": set(),
            })
            p["chains"].append(chain_name)
            if s.get("role"):
                p["roles"].add(s["role"])
            if i > 0 and names[i-1]:
                p["upstream"].add(names[i-1])
            if i + 1 < len(names) and names[i+1]:
                p["downstream"].add(names[i+1])
    # Convert sets to sorted lists for JSON output
    out = []
    for p in placeholders.values():
        out.append({
            "name": p["name"],
            "chains": p["chains"],
            "roles": sorted(p["roles"]),
            "upstream": sorted(p["upstream"]),
            "downstream": sorted(p["downstream"]),
        })
    return out


_PROMPT_TMPL = """You are grounding a placeholder workflow name in a curated
chain by picking the best matching REAL workflow from the BioMate catalog.

PLACEHOLDER NAME: {name}
ROLES IN CHAIN(S): {roles}
UPSTREAM NEIGHBOR(S): {upstream}
DOWNSTREAM NEIGHBOR(S): {downstream}
USED IN CURATED CHAIN(S): {chains}

CATALOG CANDIDATES (top BM25 hits, name + score + brief description):
{candidates}

Pick the SINGLE best fit from CATALOG CANDIDATES (or return "" if NONE of
the candidates are a sensible substitute — sometimes the placeholder is
genuinely unique and we should leave it as a chain-only name).

The picked workflow should:
- semantically perform the placeholder's role
- be compatible with the upstream/downstream context (data flows make sense)
- exist in the candidate list (no inventing names)

Output ONLY a single JSON object on one line:
{{"proposed_workflow": "<exact catalog name OR empty string>", "confidence": <0.0-1.0>, "reason": "<one short phrase>"}}
"""


def _build_prompt(p: Dict[str, Any], candidates: List[Any]) -> str:
    cand_block = "\n".join(
        f"  - `{c.name}` (BM25 {c.score:.1f}, domain {c.domain or 'general'}): "
        f"{(c.description or '')[:120]}"
        for c in candidates
    )
    return _PROMPT_TMPL.format(
        name=p["name"],
        roles=", ".join(p["roles"]) or "(unspecified)",
        upstream=", ".join(p["upstream"]) or "(none)",
        downstream=", ".join(p["downstream"]) or "(none)",
        chains=", ".join(p["chains"]),
        candidates=cand_block or "  (none retrieved)",
    )


def _parse(raw: str) -> Optional[Dict[str, Any]]:
    raw = (raw or "").strip()
    if raw.startswith("```"):
        raw = raw.strip("`")
        if raw.startswith("json"):
            raw = raw[4:].strip()
    if not raw.startswith("{"):
        i = raw.find("{")
        if i == -1:
            return None
        raw = raw[i:]
    try:
        d = json.loads(raw)
    except Exception:
        return None
    return d if isinstance(d, dict) else None


def _ground_one(
    placeholder: Dict[str, Any],
    catalog_names: set,
    llm: Optional[Callable[[str], str]],
    top_k: int = 8,
) -> Dict[str, Any]:
    # Use the placeholder name + role + neighbors as the retrieval query.
    query_parts = [placeholder["name"].replace("_", " ").replace("/", " ")]
    query_parts.extend(placeholder["roles"])
    query_parts.extend(placeholder["upstream"])
    query_parts.extend(placeholder["downstream"])
    query = " ".join(query_parts)

    candidates = retrieve_workflows(query, top_k=top_k)
    candidate_names = [c.name for c in candidates]

    base = {
        **placeholder,
        "candidates": candidate_names,
        "method": "offline" if llm is None else "llm",
    }

    if llm is None:
        # Offline fallback: pick top-1 if any
        if candidates:
            return {
                **base,
                "proposed_workflow": candidates[0].name,
                "confidence": 0.4 if candidates[0].score >= 30 else 0.2,
                "reason": "offline_top_bm25",
            }
        return {**base, "proposed_workflow": "", "confidence": 0.0, "reason": "no candidates"}

    try:
        prompt = _build_prompt(placeholder, candidates)
        raw = llm(prompt)
        parsed = _parse(raw)
    except Exception as exc:
        log.warning("LLM call failed for %s: %s", placeholder["name"], exc)
        parsed = None

    if not parsed:
        # Fall back to top-1
        if candidates:
            return {
                **base,
                "method": "offline_fallback",
                "proposed_workflow": candidates[0].name,
                "confidence": 0.3,
                "reason": "llm_failed_offline_top_bm25",
            }
        return {**base, "method": "offline_fallback",
                "proposed_workflow": "", "confidence": 0.0,
                "reason": "llm_failed_no_candidates"}

    proposed = parsed.get("proposed_workflow", "")
    # Validate: must be empty OR in candidates OR in catalog
    if proposed and proposed not in candidate_names and proposed not in catalog_names:
        # LLM hallucinated a name not in the candidates or catalog
        return {
            **base,
            "method": "llm_rejected_hallucination",
            "proposed_workflow": "",
            "confidence": 0.0,
            "reason": f"LLM proposed `{proposed}` but it's not in candidates or catalog",
        }
    return {
        **base,
        "proposed_workflow": proposed,
        "confidence": float(parsed.get("confidence", 0.5)),
        "reason": parsed.get("reason", ""),
    }


def ground_placeholders(
    db_path: Optional[Path] = None,
    offline: bool = False,
) -> List[Dict[str, Any]]:
    db_path = db_path or _DEFAULT_DB
    placeholders = _inventory_placeholders(db_path)

    conn = sqlite3.connect(str(db_path))
    try:
        catalog_names = {r[0] for r in conn.execute(
            "SELECT name FROM workflows WHERE executable=1") if r[0]}
    finally:
        conn.close()

    llm = None if offline else default_ner_llm()
    if not offline and llm is None:
        sys.stderr.write("(no API key → running offline path)\n")

    out: List[Dict[str, Any]] = []
    for i, p in enumerate(placeholders, 1):
        out.append(_ground_one(p, catalog_names, llm))
        if i % 10 == 0:
            sys.stderr.write(f"  [{i}/{len(placeholders)}] processed\n")
    return out


def render_summary(proposals: List[Dict[str, Any]]) -> str:
    n = len(proposals)
    grounded = [p for p in proposals if p["proposed_workflow"]]
    high_conf = [p for p in proposals if p["confidence"] >= 0.7]
    low_conf = [p for p in proposals if 0 < p["confidence"] < 0.4]
    no_proposal = [p for p in proposals if not p["proposed_workflow"]]

    lines = [
        "# Curated-Chain Placeholder Grounding — Proposal",
        "",
        f"Generated by `python -m galaxy.ai.chain_composer.placeholder_grounder`.",
        "",
        "## Aggregate",
        "",
        f"- Placeholder names: **{n}**",
        f"- With proposed catalog workflow: **{len(grounded)}** ({100*len(grounded)//max(1,n)}%)",
        f"- High confidence (≥0.7): **{len(high_conf)}** ({100*len(high_conf)//max(1,n)}%)",
        f"- Low confidence (<0.4): **{len(low_conf)}**",
        f"- No proposal (model declined): **{len(no_proposal)}**",
        "",
        "## High-confidence proposals (≥0.7)",
        "",
        "| Placeholder | → Proposed | Conf | Role | Chains | Reason |",
        "|---|---|---|---|---|---|",
    ]
    for p in sorted(high_conf, key=lambda x: -x["confidence"]):
        roles = ",".join(p["roles"])[:30]
        chains = ",".join(p["chains"])[:50]
        lines.append(f"| `{p['name']}` | `{p['proposed_workflow']}` | "
                     f"{p['confidence']:.2f} | {roles} | {chains} | "
                     f"{p['reason'][:80]} |")
    lines.append("")

    if low_conf:
        lines.append("## Low-confidence (review needed)")
        lines.append("")
        for p in low_conf:
            lines.append(f"- `{p['name']}` → `{p['proposed_workflow']}` "
                         f"(conf {p['confidence']:.2f}): {p['reason']}")
        lines.append("")

    if no_proposal:
        lines.append("## No proposal (placeholder unique / no fit)")
        lines.append("")
        for p in no_proposal:
            lines.append(f"- `{p['name']}` (chains: {','.join(p['chains'])}): {p['reason']}")
        lines.append("")

    lines.append("## Application path")
    lines.append("")
    lines.append("For each accepted proposal, update `workflow_chains.steps[].workflow_name` "
                 "from placeholder → proposed catalog name. This makes the curated chains "
                 "actually executable end-to-end.")
    lines.append("")
    lines.append("```python")
    lines.append("# Pseudo-code, NOT executed by this script:")
    lines.append("import json, sqlite3")
    lines.append('proposals = [json.loads(l) for l in open("docs/.../GROUNDING_PROPOSAL.jsonl")]')
    lines.append("accepted = [p for p in proposals if p['confidence'] >= 0.7 and p['proposed_workflow']]")
    lines.append("conn = sqlite3.connect('backend/database/galaxy_ai_tools.db')")
    lines.append("for chain_name, steps_json in conn.execute('SELECT name, steps FROM workflow_chains'):")
    lines.append("    steps = json.loads(steps_json or '[]')")
    lines.append("    changed = False")
    lines.append("    for s in steps:")
    lines.append("        for p in accepted:")
    lines.append("            if s.get('workflow_name') == p['name']:")
    lines.append("                s['workflow_name'] = p['proposed_workflow']")
    lines.append("                changed = True")
    lines.append("    if changed:")
    lines.append("        conn.execute('UPDATE workflow_chains SET steps=? WHERE name=?',")
    lines.append("                     (json.dumps(steps), chain_name))")
    lines.append("conn.commit()")
    lines.append("```")
    return "\n".join(lines)


def _cli(argv=None) -> int:
    p = argparse.ArgumentParser(prog="chain_composer.placeholder_grounder", description=__doc__)
    p.add_argument("--offline", action="store_true")
    p.add_argument("--output", default=None)
    p.add_argument("--summary", default=None)
    args = p.parse_args(argv)

    t0 = time.time()
    proposals = ground_placeholders(offline=args.offline)
    dt = time.time() - t0
    sys.stderr.write(f"\nGrounded {len(proposals)} placeholders in {dt:.1f}s.\n")
    grounded = [p for p in proposals if p["proposed_workflow"]]
    high = [p for p in proposals if p["confidence"] >= 0.7]
    sys.stderr.write(f"  with proposal: {len(grounded)}, high-confidence: {len(high)}\n")

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            for p in proposals:
                f.write(json.dumps(p) + "\n")
        sys.stderr.write(f"wrote {args.output}\n")
    if args.summary:
        Path(args.summary).write_text(render_summary(proposals), encoding="utf-8")
        sys.stderr.write(f"wrote {args.summary}\n")
    if not args.output and not args.summary:
        for p in proposals:
            sys.stdout.write(json.dumps(p) + "\n")
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(_cli(sys.argv[1:]))
