"""LLM-judge extraction of canonical output types for Bioconductor workflows.

The catalog's `output_types` field is stubbed to `["table/csv", "plot/pdf",
"object/rds"]` for 2,775 of the 3,310 Bioc workflows. This stub defeats
typed-port chain discovery on 82% of the catalog (see
`docs/20260610_DEEP_WORKFLOW_SURVEY.md` finding 1).

This module uses LLM Haiku with `annotation_v2.when_to_use + description +
key_parameters` as context to assign 1-3 canonical output kinds per Bioc
workflow from a closed vocabulary.

Output: JSONL of `{name, current_outputs, proposed_outputs, confidence,
reason}`. NEVER writes to the live DB; that's a separate apply step.

Cost: ~$0.005/workflow × 2,775 stub rows = ~$14 total. Wall clock ~4 hours
sequential, billed to lifeifei163361@163.com via the canonical user binding.

Usage:
    set -a && . backend/.env && set +a
    export PYTHONPATH=$PWD/backend/lib

    # Dry-run on 50 workflows to validate approach:
    python -m galaxy.ai.chain_composer.bioc_output_extractor \\
        --limit 50 --output /tmp/output_sample.jsonl --summary /tmp/output_sample.md

    # Full run:
    python -m galaxy.ai.chain_composer.bioc_output_extractor \\
        --output docs/20260610_BIOC_OUTPUT_PROPOSAL.jsonl \\
        --summary docs/20260610_BIOC_OUTPUT_PROPOSAL.md
"""

from __future__ import annotations

import argparse
import json
import logging
import re
import sqlite3
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from .llm_adapter import default_ner_llm

log = logging.getLogger(__name__)

_DEFAULT_DB = Path(__file__).resolve().parents[4] / "database" / "galaxy_ai_tools.db"

# Closed vocabulary of output kinds canonical for Bioc. The LLM picks
# 1-3 of these per workflow. Anchored on existing _TYPE_ALIASES + common
# downstream-chainable Bioc outputs.
_OUTPUT_VOCABULARY = [
    # Counts / expression
    "counts_matrix",            # raw integer counts
    "expression_matrix",        # normalized / TPM / FPKM
    "summarizedexperiment",     # SE container
    "singlecellexperiment",     # SCE container
    "seurat_object",            # Seurat container
    # Differential analysis
    "de_table",                 # DE results table (genes/features × stats)
    "differential_abundance",   # DA for microbiome / cytof
    # Enrichment / annotation
    "enrichment_results",       # GO / KEGG / Reactome / MSigDB hits
    "pathway_results",
    "annotated_genes",          # functional annotation per gene
    # Variants
    "vcf",
    "annotated_vcf",
    "gwas_summary_statistics",
    "burden_test_results",
    "copy_number_segments",
    "mutational_signatures",
    # Single-cell specific
    "cell_type_annotations",
    "cluster_assignments",
    "pseudotime_trajectory",
    # Other
    "phylogenetic_tree",
    "network_graph",            # gene/protein regulatory networks
    "feature_selection",
    "consensus_score",
    "qc_report",
    "visualizations",           # plots only (when that's the whole output)
    "normalized_data",          # generic normalized container
    "general_rds",              # fallback when no specific kind fits
]


def parse_v2(text: str) -> Dict[str, str]:
    """Parse the `- field: ...` structured annotation_v2 format."""
    if not text:
        return {}
    out = {}
    for field in ("key_parameters", "alternatives", "when_to_use", "pitfalls"):
        m = re.search(rf"^- {field}: (.+?)(?=\n- |\Z)", text, re.MULTILINE | re.DOTALL)
        if m:
            v = m.group(1).strip()
            if v.lower().startswith(("none specified", "n/a", "none")):
                continue
            out[field] = v
    return out


_PROMPT_TMPL = """You are extracting canonical output data types for a Bioconductor workflow.

CURRENT OUTPUT_TYPES (stubbed by the indexer — replace with real kinds):
  ["table/csv", "plot/pdf", "object/rds"]

WORKFLOW NAME: {name}
DESCRIPTION: {description}
WHEN_TO_USE: {when}
KEY_PARAMETERS: {params}

Pick 1-3 canonical output kinds from this CLOSED VOCABULARY:
{vocab}

Be specific. If the workflow primarily produces a DE table, return
"de_table". If it's a generic container without a more specific kind,
return "general_rds". Do not invent kinds outside the vocabulary.

Output ONLY a single JSON object on one line:
{{"proposed_outputs": ["...", "..."], "confidence": <0.0-1.0>, "reason": "<one short phrase>"}}
"""


def _build_prompt(row: Dict[str, str]) -> str:
    v2 = parse_v2(row.get("annotation_v2") or "")
    return _PROMPT_TMPL.format(
        name=row["name"],
        description=(row["description"] or "")[:400],
        when=(v2.get("when_to_use") or "(none)")[:400],
        params=(v2.get("key_parameters") or "(none)")[:300],
        vocab=", ".join(_OUTPUT_VOCABULARY),
    )


def _parse_response(raw: str) -> Optional[Dict[str, Any]]:
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
    if not isinstance(d, dict):
        return None
    outs = d.get("proposed_outputs", [])
    if not isinstance(outs, list) or not outs:
        return None
    # Validate every proposed output is in the vocabulary
    clean = [o for o in outs if isinstance(o, str) and o in _OUTPUT_VOCABULARY]
    if not clean:
        return None
    d["proposed_outputs"] = clean[:3]  # cap at 3
    return d


def _classify_one(row: Dict[str, str], llm: Optional[Callable[[str], str]]) -> Dict[str, Any]:
    if llm is None:
        # Offline path: return general_rds as a safe placeholder
        return {
            "name": row["name"],
            "current_outputs": ["table/csv", "plot/pdf", "object/rds"],
            "proposed_outputs": ["general_rds"],
            "confidence": 0.2,
            "reason": "offline_fallback_no_llm",
            "method": "offline",
        }
    try:
        raw = llm(_build_prompt(row))
        parsed = _parse_response(raw)
    except Exception as exc:
        log.warning("LLM call failed for %s: %s", row["name"], exc)
        parsed = None
    if not parsed:
        return {
            "name": row["name"],
            "current_outputs": ["table/csv", "plot/pdf", "object/rds"],
            "proposed_outputs": ["general_rds"],
            "confidence": 0.0,
            "reason": "llm_failed_or_invalid_response",
            "method": "offline_fallback",
        }
    return {
        "name": row["name"],
        "current_outputs": ["table/csv", "plot/pdf", "object/rds"],
        "proposed_outputs": parsed["proposed_outputs"],
        "confidence": float(parsed.get("confidence", 0.5)),
        "reason": parsed.get("reason", ""),
        "method": "llm",
    }


def extract_outputs(
    db_path: Optional[Path] = None,
    limit: Optional[int] = None,
    offline: bool = False,
) -> List[Dict[str, Any]]:
    db_path = db_path or _DEFAULT_DB
    conn = sqlite3.connect(str(db_path))
    try:
        rows = conn.execute(
            "SELECT name, COALESCE(description,''), COALESCE(annotation_v2,'') "
            "FROM workflows WHERE source='bioconductor' AND executable=1 "
            "AND output_types = '[\"table/csv\", \"plot/pdf\", \"object/rds\"]' "
            "ORDER BY name"
        ).fetchall()
    finally:
        conn.close()

    if limit:
        rows = rows[:limit]

    llm = None if offline else default_ner_llm()
    if not offline and llm is None:
        sys.stderr.write("(no API key → offline path)\n")

    out: List[Dict[str, Any]] = []
    for i, (name, desc, anno_v2) in enumerate(rows, 1):
        result = _classify_one(
            {"name": name, "description": desc, "annotation_v2": anno_v2},
            llm,
        )
        out.append(result)
        if i % 25 == 0:
            sys.stderr.write(f"  [{i}/{len(rows)}] processed\n")
    return out


def render_summary(proposals: List[Dict[str, Any]]) -> str:
    n = len(proposals)
    high = [p for p in proposals if p["confidence"] >= 0.7]
    low = [p for p in proposals if p["confidence"] < 0.4]
    method_counts = Counter(p["method"] for p in proposals)
    # Per-output kind frequency (over high-confidence only)
    kind_counts: Counter = Counter()
    for p in high:
        for k in p["proposed_outputs"]:
            kind_counts[k] += 1

    lines = [
        "# Bioc Output-Type Re-Extraction — Proposal",
        "",
        f"For each of the {n} Bioconductor workflows whose `output_types` is the indexer stub "
        "`['table/csv', 'plot/pdf', 'object/rds']`, LLM Haiku picks 1-3 canonical output kinds "
        "from a closed vocabulary.",
        "",
        "## Aggregate",
        "",
        f"- Workflows considered: **{n:,}**",
        f"- Method distribution: {dict(method_counts)}",
        f"- High-confidence proposals (≥0.7): **{len(high):,}** ({100*len(high)//max(1,n)}%)",
        f"- Low-confidence (<0.4) — flag for review: **{len(low):,}**",
        "",
        "## Proposed output kind distribution (high-confidence only)",
        "",
        "| Output kind | Count | Share |",
        "|---|---|---|",
    ]
    total_assignments = sum(kind_counts.values())
    for k, c in kind_counts.most_common():
        lines.append(f"| `{k}` | {c:,} | {100*c/max(1,total_assignments):.1f}% |")
    lines.append("")

    lines.append("## To apply")
    lines.append("")
    lines.append("Filter to `confidence >= 0.7` and `method == 'llm'`, then UPDATE workflows "
                 "SET output_types per accepted row. After applying, re-run the type-flow "
                 "graph analysis from the deep survey to confirm Bioc connectivity is now visible.")
    return "\n".join(lines)


def _cli(argv=None) -> int:
    p = argparse.ArgumentParser(prog="chain_composer.bioc_output_extractor", description=__doc__)
    p.add_argument("--limit", type=int, default=None)
    p.add_argument("--offline", action="store_true")
    p.add_argument("--output", default=None)
    p.add_argument("--summary", default=None)
    args = p.parse_args(argv)

    t0 = time.time()
    proposals = extract_outputs(limit=args.limit, offline=args.offline)
    dt = time.time() - t0
    sys.stderr.write(f"\nProcessed {len(proposals)} workflows in {dt:.1f}s.\n")
    sys.stderr.write(f"  high-confidence: {sum(1 for p in proposals if p['confidence'] >= 0.7)}\n")
    sys.stderr.write(f"  method mix: {dict(Counter(p['method'] for p in proposals))}\n")

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
