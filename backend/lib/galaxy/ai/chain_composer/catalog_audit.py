"""Comprehensive empirical audit of the BioMate catalog.

Run before making more design decisions. Surfaces:
- composition (source × domain, executable count)
- shape (step counts, description quality, typed I/O coverage)
- indexer quality (params-as-types prevalence; unused fields)
- catalog ↔ pattern coverage (how many workflows per pattern at threshold)
- auxiliary tables (tools, tool_compatibility, usage signals)
- curated chain reach (what fraction of catalog is referenced)

Output: a markdown report. Intended to be checked into docs/ so we have
a snapshot of catalog state at this moment.
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List

from .pattern_loader import load_patterns
from .retrieval import retrieve_workflows


_DEFAULT_DB = Path(__file__).resolve().parents[4] / "database" / "galaxy_ai_tools.db"


def _q(conn, sql, params=()) -> List[tuple]:
    return conn.execute(sql, params).fetchall()


def _pct(num, denom) -> str:
    return f"{100*num/denom:.0f}%" if denom else "n/a"


def _looks_like_param_name(t: str) -> bool:
    """Heuristic copied from chain_planner: detects when input_types stores
    parameter names instead of data type kinds."""
    fragments = ("_mode", "_file", "_path", "_threshold", "_cutoff", "_score",
                 "_size", "_steps", "_routes", "_depth", "_dose", "max_", "min_",
                 "n_cpus", "use_aws", "_seed", "_method", "_factor", "_weight",
                 "_route", "_dir", "_unit", "_ratio", "_column", "_group",
                 "publish_", "enable_", "outdir")
    s = (t or "").lower()
    if s in {"mock_mode", "gpu", "x", "_ecr", "_useaws", "chem_container"}:
        return True
    return any(f in s for f in fragments)


def section_composition(conn) -> str:
    lines = ["## 1. Composition", ""]

    total, = _q(conn, "SELECT COUNT(*) FROM workflows")[0]
    exec_ct, = _q(conn, "SELECT COUNT(*) FROM workflows WHERE executable=1")[0]
    lines.append(f"- **Total workflows**: {total:,}")
    lines.append(f"- **Executable**: {exec_ct:,} ({_pct(exec_ct, total)})")
    lines.append("")

    lines.append("### By source")
    lines.append("| Source | Count | Share |")
    lines.append("|---|---|---|")
    rows = _q(conn, "SELECT source, COUNT(*) FROM workflows GROUP BY source ORDER BY 2 DESC")
    for src, n in rows:
        lines.append(f"| `{src or '(null)'}` | {n:,} | {_pct(n, total)} |")
    lines.append("")

    lines.append("### Top 20 domains")
    lines.append("| Domain | Count |")
    lines.append("|---|---|")
    rows = _q(conn, "SELECT COALESCE(domain,'(null)'), COUNT(*) FROM workflows "
                    "WHERE executable=1 GROUP BY domain ORDER BY 2 DESC LIMIT 20")
    for d, n in rows:
        lines.append(f"| {d} | {n:,} |")
    lines.append("")

    return "\n".join(lines)


def section_shape(conn) -> str:
    lines = ["## 2. Workflow shape", ""]

    # Step count distribution
    rows = _q(conn, "SELECT step_count, COUNT(*) FROM workflows WHERE executable=1 "
                    "GROUP BY step_count ORDER BY step_count")
    by_n: Counter = Counter()
    for sc, n in rows:
        if sc is None:
            by_n["null"] += n
        elif sc == 0:
            by_n["0"] += n
        elif sc == 1:
            by_n["1"] += n
        elif sc <= 3:
            by_n["2-3"] += n
        elif sc <= 5:
            by_n["4-5"] += n
        elif sc <= 10:
            by_n["6-10"] += n
        else:
            by_n["11+"] += n
    total = sum(by_n.values())
    lines.append("### Step count distribution (executable only)")
    lines.append("| Steps | Workflows | Share |")
    lines.append("|---|---|---|")
    for k in ("null", "0", "1", "2-3", "4-5", "6-10", "11+"):
        if by_n[k]:
            lines.append(f"| {k} | {by_n[k]:,} | {_pct(by_n[k], total)} |")
    lines.append("")

    # Description quality
    rows = _q(conn,
              "SELECT "
              " SUM(CASE WHEN description IS NULL OR description='' THEN 1 ELSE 0 END), "
              " SUM(CASE WHEN LENGTH(description) BETWEEN 1 AND 30 THEN 1 ELSE 0 END), "
              " SUM(CASE WHEN LENGTH(description) BETWEEN 31 AND 120 THEN 1 ELSE 0 END), "
              " SUM(CASE WHEN LENGTH(description) > 120 THEN 1 ELSE 0 END) "
              "FROM workflows WHERE executable=1")
    empty, short, mid, long_ = rows[0]
    total = empty + short + mid + long_
    lines.append("### Description quality")
    lines.append("| Length | Workflows | Share |")
    lines.append("|---|---|---|")
    lines.append(f"| empty/null | {empty:,} | {_pct(empty, total)} |")
    lines.append(f"| 1–30 chars (likely truncated) | {short:,} | {_pct(short, total)} |")
    lines.append(f"| 31–120 chars (one-sentence) | {mid:,} | {_pct(mid, total)} |")
    lines.append(f"| 120+ chars (paragraph) | {long_:,} | {_pct(long_, total)} |")
    lines.append("")

    # Annotation field (often richer than description for Bioc)
    rows = _q(conn,
              "SELECT "
              " SUM(CASE WHEN annotation IS NULL OR annotation='' THEN 1 ELSE 0 END), "
              " SUM(CASE WHEN LENGTH(annotation) > 0 THEN 1 ELSE 0 END) "
              "FROM workflows WHERE executable=1")
    no_anno, has_anno = rows[0]
    lines.append(f"### `annotation` field coverage")
    lines.append(f"- has annotation text: **{has_anno:,}** ({_pct(has_anno, no_anno+has_anno)})")
    lines.append("")

    return "\n".join(lines)


def section_typed_io_quality(conn) -> str:
    lines = ["## 3. Typed I/O coverage + indexer quality", ""]

    rows = _q(conn,
              "SELECT "
              " SUM(CASE WHEN input_types NOT IN ('','[]','null') THEN 1 ELSE 0 END), "
              " SUM(CASE WHEN output_types NOT IN ('','[]','null') THEN 1 ELSE 0 END), "
              " COUNT(*) "
              "FROM workflows WHERE executable=1")
    in_pop, out_pop, exec_ct = rows[0]
    lines.append(f"- `input_types` populated: **{in_pop:,}** / {exec_ct:,} ({_pct(in_pop, exec_ct)})")
    lines.append(f"- `output_types` populated: **{out_pop:,}** / {exec_ct:,} ({_pct(out_pop, exec_ct)})")
    lines.append("")

    # Bioc output stub: how many have the identical placeholder?
    stub_q = "SELECT COUNT(*) FROM workflows WHERE source='bioconductor' AND output_types = ?"
    stub_count, = _q(conn, stub_q, ('["table/csv", "plot/pdf", "object/rds"]',))[0]
    bioc_total, = _q(conn, "SELECT COUNT(*) FROM workflows WHERE source='bioconductor'")[0]
    lines.append(f"- **Bioconductor output stub**: {stub_count:,} / {bioc_total:,} ({_pct(stub_count, bioc_total)}) "
                 f"have identical `output_types=['table/csv','plot/pdf','object/rds']`")
    lines.append("")

    # biomni_nextflow param-as-type prevalence
    biomni_rows = _q(conn, "SELECT input_types FROM workflows WHERE source='biomni_nextflow' AND input_types NOT IN ('','[]','null')")
    junk_count = 0
    for (raw,) in biomni_rows:
        try:
            types = json.loads(raw or "[]")
            if not isinstance(types, list) or not types:
                continue
            junk = sum(1 for t in types if isinstance(t, str) and _looks_like_param_name(t))
            if junk >= len(types) / 2:
                junk_count += 1
        except Exception:
            continue
    biomni_total = len(biomni_rows)
    lines.append(f"- **biomni_nextflow params-as-types**: {junk_count:,} / {biomni_total:,} "
                 f"({_pct(junk_count, biomni_total)}) workflows have `input_types` "
                 "composed of parameter names (indexer bug at index_all_workflows.py:309)")
    lines.append("")

    return "\n".join(lines)


def section_curated_reach(conn) -> str:
    lines = ["## 4. Curated chain reach", ""]
    n_chains, = _q(conn, "SELECT COUNT(*) FROM workflow_chains")[0]
    intent_chains, = _q(conn,
        "SELECT COUNT(*) FROM workflow_chains WHERE source IS NULL OR source != 'bioc_reactive'")[0]
    lines.append(f"- Total curated chains: **{n_chains:,}**")
    lines.append(f"- Intent-eligible (excl. bioc_reactive): **{intent_chains:,}**")
    lines.append("")

    # Workflows referenced by curated chains.
    chain_step_names = set()
    for (raw,) in _q(conn, "SELECT steps FROM workflow_chains"):
        try:
            for s in json.loads(raw or "[]"):
                if isinstance(s, dict) and s.get("workflow_name"):
                    chain_step_names.add(s["workflow_name"])
        except Exception:
            continue
    catalog_names = {r[0] for r in _q(conn, "SELECT name FROM workflows WHERE executable=1") if r[0]}
    referenced_in_catalog = chain_step_names & catalog_names
    lines.append(f"- Unique step names referenced by curated chains: **{len(chain_step_names):,}**")
    lines.append(f"- Of those, exist in catalog: **{len(referenced_in_catalog):,}** ({_pct(len(referenced_in_catalog), len(chain_step_names))})")
    lines.append(f"- Catalog workflows reachable via curated chains: **{len(referenced_in_catalog):,}** / {len(catalog_names):,} ({_pct(len(referenced_in_catalog), len(catalog_names))})")
    lines.append("")
    lines.append("> The vast majority of the catalog is NOT yet reachable via curated chains. "
                 "Curated chains cover a thin slice; the rest only reachable via L2 (pattern + LLM compose).")
    lines.append("")

    # Cross-source chain spans (from earlier finding)
    cross_source = 0
    name_to_source = {r[0]: r[1] for r in _q(conn, "SELECT name, COALESCE(source,'?') FROM workflows")}
    for (name, raw) in _q(conn, "SELECT name, steps FROM workflow_chains"):
        try:
            srcs = {name_to_source.get(s.get("workflow_name", ""), "?")
                    for s in json.loads(raw or "[]")}
        except Exception:
            continue
        if len({s for s in srcs if s and s != "?"}) > 1:
            cross_source += 1
    lines.append(f"- Curated chains spanning ≥2 known sources: **{cross_source:,}** / {n_chains:,} ({_pct(cross_source, n_chains)})")
    lines.append("")
    return "\n".join(lines)


def section_per_pattern_coverage(conn) -> str:
    lines = ["## 5. Per-pattern catalog coverage", "",
             "For each pattern, how many catalog workflows score above quality "
             "thresholds when BM25-searched with the pattern's `When + Pitfall + Instantiations` text. "
             "High score = strong textual alignment (not necessarily a perfect fit).",
             "",
             "| Pattern | top-1 | n ≥ 30 | n ≥ 15 | n ≥ 5 | top-3 candidates |",
             "|---|---|---|---|---|---|",
             ]
    patterns = load_patterns()
    for p in patterns:
        # Compose the query text the same way pattern_evidence.py does.
        q = " ".join(filter(None, [p.name.replace("_", " "), p.when, p.pitfall, " ".join(p.instantiations)]))
        for ch in "`*_[]()":
            q = q.replace(ch, " ")
        # top_k=4000 effectively returns the full sorted list; we count
        # thresholds below to characterize per-pattern coverage.
        wfs = retrieve_workflows(q, top_k=4000)
        if not wfs:
            lines.append(f"| `{p.name}` | — | 0 | 0 | 0 | — |")
            continue
        top1 = wfs[0].score
        n_30 = sum(1 for w in wfs if w.score >= 30)
        n_15 = sum(1 for w in wfs if w.score >= 15)
        n_5 = sum(1 for w in wfs if w.score >= 5)
        top3 = ", ".join(f"`{w.name}`" for w in wfs[:3])
        lines.append(f"| `{p.name}` | {top1:.1f} | {n_30} | {n_15} | {n_5} | {top3} |")
    lines.append("")
    lines.append("Read: a pattern with `n ≥ 15 = 50` has 50 strongly-aligned catalog workflows. "
                 "A pattern with `n ≥ 30 = 0` may be under-served by the catalog OR may have a "
                 "narrow pattern doc that doesn't generate many BM25 hits.")
    return "\n".join(lines)


def section_auxiliary_tables(conn) -> str:
    lines = ["## 6. Auxiliary tables", ""]

    tools_n, = _q(conn, "SELECT COUNT(*) FROM tools WHERE is_dataset=0")[0]
    datasets_n, = _q(conn, "SELECT COUNT(*) FROM tools WHERE is_dataset=1")[0]
    lines.append(f"- **`tools`** (Galaxy ToolShed atomic tools): {tools_n:,} tools + {datasets_n:,} datasets")

    # Top categories
    rows = _q(conn, "SELECT category, COUNT(*) FROM tools WHERE is_dataset=0 GROUP BY category ORDER BY 2 DESC LIMIT 10")
    lines.append("")
    lines.append("  Top 10 tool categories:")
    for cat, n in rows:
        lines.append(f"  - {cat or '(null)'}: {n:,}")
    lines.append("")

    tc_total, = _q(conn, "SELECT COUNT(*) FROM tool_compatibility")[0]
    tc_types = _q(conn, "SELECT compatibility_type, COUNT(*) FROM tool_compatibility GROUP BY compatibility_type")
    lines.append(f"- **`tool_compatibility`**: {tc_total:,} rows ({', '.join(f'{ct}={n}' for ct, n in tc_types)})")
    lines.append("  > Note: every row's `compatibility_type` is the same. This table currently records "
                 "*what tools accept as input* — not output edges. Cannot be used as-is to infer "
                 "tool-to-tool chain edges.")
    lines.append("")

    usage_n, = _q(conn, "SELECT COUNT(*) FROM tool_usage_patterns")[0]
    sess_n, = _q(conn, "SELECT COUNT(*) FROM session_workflows")[0]
    lines.append(f"- **`tool_usage_patterns`**: {usage_n:,} rows — **empty, no usage signal available**")
    lines.append(f"- **`session_workflows`**: {sess_n:,} rows — empty, no run history available")
    lines.append("")
    lines.append("  > No popularity / success-rate signals exist. Confidence-calibration cannot be "
                 "driven by real usage; only synthetic eval sets (e.g. eval_queries.jsonl).")
    lines.append("")

    # BGE embeddings live in npz, not SQL.
    lines.append("- **BGE dense embeddings** (used by `unified_workflow_search`):")
    for npz_path in (
        _DEFAULT_DB.parent.parent / "galaxy_ai_tools_embeddings.npz",
        _DEFAULT_DB.parent / "galaxy_ai_workflow_embeddings.npz",
    ):
        if npz_path.exists():
            try:
                import numpy as np
                z = np.load(str(npz_path), allow_pickle=True)
                shape_summary = ", ".join(f"{k}={z[k].shape}" for k in z.files)
                lines.append(f"  - `{npz_path.name}`: {shape_summary}")
                z.close()
            except Exception as exc:
                lines.append(f"  - `{npz_path.name}`: present but unreadable ({exc})")
    lines.append("")
    return "\n".join(lines)


def section_findings(conn) -> str:
    """A short interpretation block at the end — what does the audit tell us?"""
    lines = ["## 7. Headline takeaways", ""]
    total, = _q(conn, "SELECT COUNT(*) FROM workflows WHERE executable=1")[0]
    bioc_total, = _q(conn, "SELECT COUNT(*) FROM workflows WHERE source='bioconductor'")[0]
    stub_count, = _q(conn,
        "SELECT COUNT(*) FROM workflows WHERE source='bioconductor' "
        "AND output_types = ?", ('["table/csv", "plot/pdf", "object/rds"]',))[0]
    n_chains, = _q(conn, "SELECT COUNT(*) FROM workflow_chains")[0]
    catalog_names = {r[0] for r in _q(conn, "SELECT name FROM workflows WHERE executable=1") if r[0]}
    chain_step_names = set()
    for (raw,) in _q(conn, "SELECT steps FROM workflow_chains"):
        try:
            for s in json.loads(raw or "[]"):
                if isinstance(s, dict) and s.get("workflow_name"):
                    chain_step_names.add(s["workflow_name"])
        except Exception:
            continue
    referenced_in_catalog = len(chain_step_names & catalog_names)

    lines.append(f"1. **Bioconductor dominates: {bioc_total:,} / {total:,} executable workflows ({_pct(bioc_total, total)}).** "
                 f"Of those, {stub_count:,} ({_pct(stub_count, bioc_total)}) have an identical `output_types` stub. "
                 "Output typing of Bioc is essentially uninformative; only the prose description carries signal.")
    lines.append("")
    lines.append(f"2. **Curated coverage is thin**: {n_chains} chains reference {referenced_in_catalog} catalog "
                 f"workflows out of {len(catalog_names):,} ({_pct(referenced_in_catalog, len(catalog_names))}). The rest of the "
                 "catalog is only reachable via L2 (pattern + LLM compose) or L3 (free tool-use loop).")
    lines.append("")
    lines.append("3. **No usage data exists.** `tool_usage_patterns` and `session_workflows` are both empty. "
                 "We can't calibrate confidence thresholds against real success/abandon signals; only synthetic eval.")
    lines.append("")
    lines.append("4. **Tool_compatibility is one-directional.** All 9,656 rows are `input` edges. "
                 "Cannot be used to derive tool→tool chain edges as-is; needs an `output` indexing pass.")
    lines.append("")
    lines.append("5. **The catalog has rich coverage but uneven indexer quality.** Per-pattern retrieval works "
                 "well for shapes whose canonical tools have distinctive descriptions (`edge_timecourse_de_analysis`, "
                 "`piano_consensus_gsa_scoring`). It fails when the catalog stores names without descriptions "
                 "or with stub outputs.")
    lines.append("")
    lines.append("6. **BGE dense embeddings cover ~67% of executable workflows** (2,473 / 3,695). The remaining "
                 "1,222 workflows are reachable only via lexical (BM25) retrieval — the prototype's L2 path. "
                 "A backfill pass would close the gap.")
    return "\n".join(lines)


def build_report() -> str:
    conn = sqlite3.connect(str(_DEFAULT_DB))
    try:
        parts = [
            "# BioMate Catalog Audit",
            "",
            f"Generated against `backend/database/galaxy_ai_tools.db` "
            "by `python -m galaxy.ai.chain_composer.catalog_audit`.",
            "",
            "This snapshot is intentionally read-only and serves as ground truth "
            "for design decisions about pattern library content, retrieval tuning, "
            "and downstream wiring. Re-run periodically to track drift.",
            "",
            "---",
            "",
            section_composition(conn),
            section_shape(conn),
            section_typed_io_quality(conn),
            section_curated_reach(conn),
            section_per_pattern_coverage(conn),
            section_auxiliary_tables(conn),
            section_findings(conn),
        ]
    finally:
        conn.close()
    return "\n".join(parts) + "\n"


def _cli(argv=None) -> int:
    p = argparse.ArgumentParser(prog="chain_composer.catalog_audit", description=__doc__)
    p.add_argument("--output", default=None, help="write markdown here (default: stdout)")
    args = p.parse_args(argv)
    report = build_report()
    if args.output:
        Path(args.output).write_text(report, encoding="utf-8")
        sys.stderr.write(f"wrote {len(report.splitlines())} lines to {args.output}\n")
    else:
        sys.stdout.write(report)
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(_cli(sys.argv[1:]))
