"""Integrated apply-impact simulator.

Copies the catalog DB to a scratch file, applies ALL proposals generated
this session (domain reclassifications + curated chain grounding + new
hub-anchored curated chains), then exposes the path for downstream tools
to point at via the BIOMATE_AI_TOOLS_DB env var.

Output:
- Scratch DB at the chosen path (default: /tmp/galaxy_ai_tools_PROPOSED.db)
- Markdown summary of what was applied
- Counts: domain UPDATEs, chain step rewrites, new curated chains inserted

This does NOT touch the live DB. The scratch DB is for read-only audit
and calibration re-runs.

Usage:
    export PYTHONPATH=$PWD/backend/lib
    python -m galaxy.ai.chain_composer.apply_simulator \\
        --scratch-db /tmp/galaxy_ai_tools_PROPOSED.db \\
        --output docs/20260610_APPLY_IMPACT_SIMULATION.md
"""

from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import sys
from pathlib import Path
from typing import Dict, List, Tuple


def _load_jsonl(path: Path) -> List[Dict]:
    if not path.exists():
        return []
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def apply_domain_reclassifications(
    conn: sqlite3.Connection,
    proposals: List[Dict],
    min_confidence: float = 0.7,
) -> Tuple[int, int]:
    """Returns (applied, skipped)."""
    accepted = [
        p for p in proposals
        if p.get("confidence", 0.0) >= min_confidence
        and p.get("proposed_domain") not in (None, "", "general")
        and p.get("method") == "llm"
    ]
    cur = conn.cursor()
    applied = 0
    for p in accepted:
        cur.execute(
            "UPDATE workflows SET domain = ? "
            "WHERE name = ? AND domain = 'general'",
            (p["proposed_domain"], p["name"]),
        )
        applied += cur.rowcount
    conn.commit()
    return applied, len(proposals) - applied


def apply_placeholder_groundings(
    conn: sqlite3.Connection,
    proposals: List[Dict],
    min_confidence: float = 0.7,
) -> Tuple[int, int]:
    """For each accepted placeholder, rewrite workflow_chains.steps[].workflow_name.
    Returns (chain_steps_rewritten, placeholders_applied).
    """
    accepted = {
        p["name"]: p["proposed_workflow"]
        for p in proposals
        if p.get("confidence", 0.0) >= min_confidence
        and p.get("proposed_workflow")
        and p.get("method") == "llm"
    }
    if not accepted:
        return 0, 0

    cur = conn.cursor()
    chains_modified = 0
    steps_rewritten = 0
    for chain_name, raw in cur.execute("SELECT name, steps FROM workflow_chains").fetchall():
        try:
            steps = json.loads(raw or "[]")
        except Exception:
            continue
        changed = False
        for s in steps:
            if not isinstance(s, dict):
                continue
            wn = s.get("workflow_name")
            if wn in accepted:
                s["workflow_name"] = accepted[wn]
                changed = True
                steps_rewritten += 1
        if changed:
            cur.execute(
                "UPDATE workflow_chains SET steps = ? WHERE name = ?",
                (json.dumps(steps), chain_name),
            )
            chains_modified += 1
    conn.commit()
    return steps_rewritten, len(accepted)


def apply_proposed_chains(
    conn: sqlite3.Connection,
    proposed_dir: Path,
) -> int:
    """Insert the proposed_chains/*.json into the workflow_chains table.
    Returns count inserted."""
    if not proposed_dir.exists():
        return 0
    cur = conn.cursor()
    inserted = 0
    for f in sorted(proposed_dir.glob("*.json")):
        try:
            chain = json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            continue
        try:
            cur.execute(
                "INSERT INTO workflow_chains "
                "(name, display_name, domain, description, steps, connections, "
                " required_inputs, expected_outputs, example_queries, tags, source) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    chain["name"],
                    chain.get("display_name", chain["name"]),
                    chain.get("domain", "general"),
                    chain.get("description", ""),
                    json.dumps(chain.get("steps", [])),
                    json.dumps(chain.get("connections", [])),
                    json.dumps(chain.get("required_inputs", [])),
                    json.dumps(chain.get("expected_outputs", [])),
                    json.dumps(chain.get("example_queries", [])),
                    json.dumps(chain.get("tags", [])),
                    chain.get("source", "curated"),
                ),
            )
            inserted += 1
        except sqlite3.IntegrityError as exc:
            # Likely a UNIQUE constraint on name — chain already exists
            sys.stderr.write(f"skip {chain['name']}: {exc}\n")
            continue
    conn.commit()
    return inserted


def snapshot_counts(conn: sqlite3.Connection) -> Dict:
    cur = conn.cursor()
    out = {}
    out["executable_workflows"] = cur.execute(
        "SELECT COUNT(*) FROM workflows WHERE executable=1").fetchone()[0]
    out["general_domain"] = cur.execute(
        "SELECT COUNT(*) FROM workflows WHERE executable=1 AND domain='general'").fetchone()[0]
    out["curated_chains"] = cur.execute(
        "SELECT COUNT(*) FROM workflow_chains").fetchone()[0]
    # Step grounding %
    catalog = {r[0] for r in cur.execute("SELECT name FROM workflows WHERE executable=1") if r[0]}
    total_steps = grounded = 0
    for (raw,) in cur.execute("SELECT steps FROM workflow_chains").fetchall():
        try:
            steps = json.loads(raw or "[]")
        except Exception:
            continue
        for s in steps:
            if not isinstance(s, dict):
                continue
            wn = s.get("workflow_name")
            if not wn:
                continue
            total_steps += 1
            if wn in catalog:
                grounded += 1
    out["chain_step_references"] = total_steps
    out["chain_steps_grounded_in_catalog"] = grounded
    out["chain_step_grounding_pct"] = round(100 * grounded / max(1, total_steps), 1)
    return out


def render_summary(before: Dict, after: Dict, applied: Dict) -> str:
    lines = [
        "# Apply-Impact Simulation — Combined Proposals",
        "",
        "Built by copying the live catalog DB to a scratch path, then applying:",
        "- 5 hub-anchored curated chain proposals "
        "(`backend/lib/galaxy/ai/chain_composer/proposed_chains/*.json`)",
        "- High-confidence domain reclassifications "
        "(`docs/20260610_DOMAIN_RECLASSIFICATION_PROPOSAL.jsonl`, confidence ≥ 0.7, method=llm, target≠general)",
        "- High-confidence placeholder groundings "
        "(`docs/20260610_PLACEHOLDER_GROUNDING.jsonl`, confidence ≥ 0.7, method=llm)",
        "",
        "The original DB is **not modified**; this simulator is a read-only "
        "preview of what applying the proposals would change.",
        "",
        "## Operations applied",
        "",
        "| Operation | Count | Notes |",
        "|---|---|---|",
        f"| New curated chains inserted | {applied['chains_inserted']} | from `proposed_chains/` |",
        f"| Workflows relabeled out of `general` | {applied['domains_updated']} | confidence ≥ 0.7 |",
        f"| Placeholder names rewritten in `workflow_chains.steps` | {applied['steps_rewritten']} | confidence ≥ 0.7 |",
        f"| Distinct placeholders applied | {applied['placeholders_applied']} | ≤ steps_rewritten (some appear in multiple chains) |",
        "",
        "## Catalog state before vs after",
        "",
        "| Metric | Before | After | Δ |",
        "|---|---|---|---|",
    ]
    for k in ("executable_workflows", "general_domain", "curated_chains",
              "chain_step_references", "chain_steps_grounded_in_catalog",
              "chain_step_grounding_pct"):
        b, a = before[k], after[k]
        delta = a - b
        delta_str = f"+{delta}" if delta > 0 else str(delta) if delta < 0 else "—"
        if k == "chain_step_grounding_pct":
            lines.append(f"| {k} | {b}% | {a}% | {delta_str}pp |")
        else:
            lines.append(f"| {k} | {b:,} | {a:,} | {delta_str} |")
    lines.append("")

    # Concrete impact notes
    lines.append("## Concrete impact")
    lines.append("")
    gen_shrink = before["general_domain"] - after["general_domain"]
    lines.append(f"- **`general` bucket shrinks by {gen_shrink:,} workflows** "
                 f"({100*gen_shrink/max(1,before['general_domain']):.0f}% reduction). "
                 "Those workflows now reachable by domain-faceted features.")
    grounding_lift = after["chain_step_grounding_pct"] - before["chain_step_grounding_pct"]
    lines.append(f"- **Curated chain step grounding lifts {before['chain_step_grounding_pct']}% → "
                 f"{after['chain_step_grounding_pct']}% (+{grounding_lift:.1f}pp)**. "
                 "Each step now more likely to resolve to a real catalog workflow at execution time.")
    new_chains = applied["chains_inserted"]
    lines.append(f"- **{new_chains} new curated chains** add coverage for previously-uncovered "
                 "patterns (time_series_longitudinal, multi_method_consensus / piano, "
                 "cross_cohort_replication / bacon, scRNA-ADT multimodal, phylogenetic uncertainty).")
    lines.append("")

    lines.append("## Next: re-run calibration against the scratch DB")
    lines.append("")
    lines.append("```bash")
    lines.append("export PYTHONPATH=$PWD/backend/lib")
    lines.append("export BIOMATE_AI_TOOLS_DB=/tmp/galaxy_ai_tools_PROPOSED.db")
    lines.append("python -m galaxy.ai.chain_composer.catalog_audit "
                 "--output docs/20260610_CATALOG_AUDIT_AFTER_APPLY.md")
    lines.append("python -m galaxy.ai.chain_composer.calibrate "
                 "backend/lib/galaxy/ai/chain_composer/eval_queries.jsonl")
    lines.append("```")
    return "\n".join(lines)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="chain_composer.apply_simulator", description=__doc__)
    here = Path(__file__).resolve().parent
    repo_root = here.parents[4]
    default_src = repo_root / "backend" / "database" / "galaxy_ai_tools.db"
    p.add_argument("--src-db", default=str(default_src),
                   help="source DB (default: live catalog symlinked into worktree)")
    p.add_argument("--scratch-db", default="/tmp/galaxy_ai_tools_PROPOSED.db",
                   help="where to copy the DB before applying proposals")
    p.add_argument("--domain-jsonl",
                   default=str(repo_root / "docs" / "20260610_DOMAIN_RECLASSIFICATION_PROPOSAL.jsonl"))
    p.add_argument("--ground-jsonl",
                   default=str(repo_root / "docs" / "20260610_PLACEHOLDER_GROUNDING.jsonl"))
    p.add_argument("--proposed-chains-dir", default=str(here / "proposed_chains"))
    p.add_argument("--min-confidence", type=float, default=0.7)
    p.add_argument("--output", default=None, help="markdown summary path")
    args = p.parse_args(argv)

    src = Path(args.src_db).resolve()
    scratch = Path(args.scratch_db)
    # Resolve symlinks so shutil.copy gets the actual file
    sys.stderr.write(f"copying {src} → {scratch}\n")
    shutil.copy2(src, scratch)

    conn = sqlite3.connect(str(scratch))
    try:
        before = snapshot_counts(conn)
        sys.stderr.write(f"before: {before}\n")

        # Apply in order: chains insert → groundings → domain reclass.
        # (Order doesn't matter semantically; this ordering is intuitive for the report.)
        chains_inserted = apply_proposed_chains(
            conn, Path(args.proposed_chains_dir))
        steps_rewritten, placeholders_applied = apply_placeholder_groundings(
            conn,
            _load_jsonl(Path(args.ground_jsonl)),
            min_confidence=args.min_confidence,
        )
        domains_updated, _ = apply_domain_reclassifications(
            conn,
            _load_jsonl(Path(args.domain_jsonl)),
            min_confidence=args.min_confidence,
        )

        after = snapshot_counts(conn)
        sys.stderr.write(f"after:  {after}\n")
    finally:
        conn.close()

    applied = {
        "chains_inserted": chains_inserted,
        "domains_updated": domains_updated,
        "steps_rewritten": steps_rewritten,
        "placeholders_applied": placeholders_applied,
    }

    summary = render_summary(before, after, applied)
    if args.output:
        Path(args.output).write_text(summary, encoding="utf-8")
        sys.stderr.write(f"wrote {args.output}\n")
    else:
        sys.stdout.write(summary + "\n")
    sys.stderr.write(f"\nscratch DB ready at: {scratch}\n")
    sys.stderr.write("Set BIOMATE_AI_TOOLS_DB to this path to read it.\n")
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main(sys.argv[1:]))
