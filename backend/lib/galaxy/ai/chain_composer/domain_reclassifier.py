"""LLM-judge re-classification of workflows currently tagged `domain='general'`.

Many catalog workflows landed in `general` because the indexer's domain
classifier missed clear signals in the description / annotation. This
module passes each general-domain workflow's text to an LLM Haiku-tier
call and asks it to pick the single best domain from the existing
taxonomy (no new domains invented).

Output: JSONL of proposed reassignments + aggregated summary. The output
is NEVER applied to the live DB by this script — it's a proposal artifact
for human review and a targeted re-indexer pass.

Cost: ~$0.005/workflow at Haiku rates → ~$3 for all 636 general workflows.
Wall clock: ~15-30 minutes (one LLM call per workflow, sequential).

Usage:
    # Dry-run on 20 workflows (offline path only — no LLM):
    python -m galaxy.ai.chain_composer.domain_reclassifier --limit 20 --offline

    # Real LLM pass (requires API key):
    set -a && . backend/.env && set +a
    python -m galaxy.ai.chain_composer.domain_reclassifier \\
        --limit 50 --output /tmp/reclass_sample.jsonl

    # Full run (all 636):
    python -m galaxy.ai.chain_composer.domain_reclassifier \\
        --output docs/20260610_DOMAIN_RECLASSIFICATION_PROPOSAL.jsonl \\
        --summary docs/20260610_DOMAIN_RECLASSIFICATION_SUMMARY.md
"""

from __future__ import annotations

import argparse
import json
import logging
import sqlite3
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

from .llm_adapter import default_ner_llm

log = logging.getLogger(__name__)

_DEFAULT_DB = Path(__file__).resolve().parents[4] / "database" / "galaxy_ai_tools.db"

# Existing domain taxonomy (from audit, executable workflow counts).
# The LLM may pick "general" if no specific domain truly fits.
_DOMAIN_TAXONOMY = [
    "transcriptomics", "genomics", "epigenomics", "variant_calling",
    "proteomics", "drug_discovery", "imaging", "metagenomics",
    "single_cell", "metabolomics", "molecular_biology", "pharmacology",
    "bioimaging", "microbiology", "physiology", "immunology",
    "bioengineering", "systems_biology", "synthetic_biology", "genetics",
    "cryo_em", "biochemistry", "pathology", "lab_automation",
    "structural_biology",  # exists in catalog at low frequency
    "general",  # last-resort, "no specific domain fits"
]


# Lightweight offline reclassifier — keyword heuristics, used when no LLM.
# Far less accurate than the LLM path but fast and free; gives a baseline.
_OFFLINE_KEYWORD_HINTS: Dict[str, List[str]] = {
    "transcriptomics": ["rna-seq", "rnaseq", "rna seq", "expression", "transcript", "isoform", "differential expression"],
    "genomics": ["genome", "wgs", "wes", "alignment", "variant", "snp", "sequence", "fasta", "bam"],
    "epigenomics": ["chip-seq", "chipseq", "atac-seq", "atacseq", "methylation", "wgbs", "rrbs", "histone"],
    "variant_calling": ["variant calling", "snv", "indel", "mutect", "gatk", "haplotypecaller", "deepvariant", "strelka"],
    "proteomics": ["proteomic", "mass spec", "peptide", "protein abundance", "maxquant", "openms"],
    "single_cell": ["single-cell", "scrna", "single cell", "cellranger", "h5ad", "anndata"],
    "drug_discovery": ["drug", "compound", "ligand", "smiles", "admet", "docking", "screening", "molecule"],
    "imaging": ["microscop", "imaging", "fluorescence", "spot detection"],
    "metagenomics": ["metagenom", "microbiome", "amplicon", "16s", "shotgun"],
    "metabolomics": ["metabolomic", "metabolite", "lc-ms", "gc-ms"],
    "pharmacology": ["pharmacokinetic", "pbpk", "pk/pd", "dose-response", "dose response"],
    "cryo_em": ["cryo-em", "cryoem", "cryosparc", "relion", "particle pick"],
    "phylogenetics": ["phylogen", "tree", "mafft", "iqtree", "ortholog"],
    "molecular_biology": ["assay", "qpcr", "western", "elisa"],
    "biochemistry": ["enzyme", "kinetic", "circular dichroism", "itc"],
    "systems_biology": ["network", "pathway model", "ode", "kinetic model"],
    "immunology": ["immun", "antibody", "tcell", "bcell", "epitope"],
    "physiology": ["physiology", "ecg", "in vivo measurement"],
    "lab_automation": ["liquid handler", "robot", "automated"],
    "structural_biology": ["structure", "pdb", "alphafold", "docking pose", "homology model"],
}


def _offline_classify(text: str) -> Tuple[str, float]:
    """Score each domain by keyword hits; return (best_domain, hit_count_normalized).

    Filtered to only emit domains in the canonical taxonomy so the offline
    fallback can't propose labels (e.g. `phylogenetics`) that the catalog
    doesn't actually use.
    """
    t = (text or "").lower()
    scores: Dict[str, int] = {}
    for d, kws in _OFFLINE_KEYWORD_HINTS.items():
        if d not in _DOMAIN_TAXONOMY:
            continue
        scores[d] = sum(1 for kw in kws if kw in t)
    if not scores:
        return "general", 0.0
    best = max(scores, key=lambda d: scores[d])
    if scores[best] == 0:
        return "general", 0.0
    # Normalize: 2+ hits → 1.0, 1 hit → 0.5
    return best, min(1.0, scores[best] / 2.0)


# LLM prompt — kept short for Haiku throughput
_PROMPT_TMPL = """You are a domain classifier for a bioinformatics workflow catalog.

CURRENT DOMAIN: general (catch-all — likely a classification miss)
WORKFLOW NAME: {name}
SOURCE: {source}
DESCRIPTION: {description}
ANNOTATION: {annotation}

Pick the SINGLE best domain from this closed list. If no specific domain
truly fits, return "general".

ALLOWED DOMAINS:
{taxonomy}

Output ONLY a single JSON object on one line:
{{"proposed_domain": "<one of the allowed domains>", "confidence": <0.0-1.0>, "reason": "<one short phrase>"}}
"""


def _build_prompt(row: Dict[str, str]) -> str:
    return _PROMPT_TMPL.format(
        name=row["name"],
        source=row["source"] or "unknown",
        description=(row["description"] or "")[:500],
        annotation=(row["annotation"] or "")[:500],
        taxonomy=", ".join(_DOMAIN_TAXONOMY),
    )


def _parse_llm_response(raw: str) -> Optional[Dict[str, Any]]:
    raw = (raw or "").strip()
    # Strip code fences if present
    if raw.startswith("```"):
        raw = raw.strip("`")
        if raw.startswith("json"):
            raw = raw[4:].strip()
    # Greedy extract first {...} block
    if not raw.startswith("{"):
        i = raw.find("{")
        if i == -1:
            return None
        raw = raw[i:]
    try:
        data = json.loads(raw)
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    if data.get("proposed_domain") not in _DOMAIN_TAXONOMY:
        return None
    return data


def _classify_one(
    row: Dict[str, str],
    llm: Optional[Callable[[str], str]],
) -> Dict[str, Any]:
    if llm is None:
        d, c = _offline_classify(
            (row["description"] or "") + " " + (row["annotation"] or "")
        )
        return {
            "name": row["name"],
            "current_domain": row["current_domain"],
            "proposed_domain": d,
            "confidence": c,
            "reason": "offline_keyword_match",
            "method": "offline",
        }

    try:
        prompt = _build_prompt(row)
        raw = llm(prompt)
        parsed = _parse_llm_response(raw)
    except Exception as exc:
        log.warning("classification call failed for %s: %s", row["name"], exc)
        parsed = None

    if parsed is None:
        # Fall back to offline so every row gets a row in the output
        d, c = _offline_classify(
            (row["description"] or "") + " " + (row["annotation"] or "")
        )
        return {
            "name": row["name"],
            "current_domain": row["current_domain"],
            "proposed_domain": d,
            "confidence": c * 0.5,  # damp since LLM failed
            "reason": "llm_failed_offline_fallback",
            "method": "offline_fallback",
        }

    return {
        "name": row["name"],
        "current_domain": row["current_domain"],
        "proposed_domain": parsed["proposed_domain"],
        "confidence": float(parsed.get("confidence", 0.5)),
        "reason": parsed.get("reason", ""),
        "method": "llm",
    }


def reclassify(
    db_path: Optional[Path] = None,
    limit: Optional[int] = None,
    offline: bool = False,
) -> List[Dict[str, Any]]:
    db_path = db_path or _DEFAULT_DB
    conn = sqlite3.connect(str(db_path))
    try:
        sql = ("SELECT name, COALESCE(source,''), COALESCE(description,''), "
               "       COALESCE(annotation,'') "
               "FROM workflows WHERE executable=1 AND domain='general' "
               "ORDER BY name")
        rows = conn.execute(sql).fetchall()
    finally:
        conn.close()

    if limit:
        rows = rows[:limit]

    llm = None if offline else default_ner_llm()
    if not offline and llm is None:
        sys.stderr.write("(no API key → running offline keyword path)\n")

    out: List[Dict[str, Any]] = []
    for i, (name, source, desc, anno) in enumerate(rows, 1):
        row = {
            "name": name,
            "source": source,
            "description": desc,
            "annotation": anno,
            "current_domain": "general",
        }
        result = _classify_one(row, llm)
        out.append(result)
        if i % 25 == 0:
            sys.stderr.write(f"  [{i}/{len(rows)}] processed\n")
    return out


def render_summary(proposals: List[Dict[str, Any]]) -> str:
    n = len(proposals)
    method_counts = Counter(p["method"] for p in proposals)
    target_counts = Counter(p["proposed_domain"] for p in proposals)
    high_conf = sum(1 for p in proposals if p["confidence"] >= 0.7)
    low_conf = sum(1 for p in proposals if p["confidence"] < 0.4)
    stay_general = sum(1 for p in proposals if p["proposed_domain"] == "general")

    lines = [
        "# Domain Reclassification Proposal — `general` bucket",
        "",
        f"Generated by `python -m galaxy.ai.chain_composer.domain_reclassifier`.",
        f"Source: workflows with `domain='general' AND executable=1`.",
        "",
        "## Aggregate",
        "",
        f"- Workflows considered: **{n:,}**",
        f"- Method distribution: {dict(method_counts)}",
        f"- High-confidence proposals (≥0.7): **{high_conf:,}** ({100*high_conf/max(1,n):.0f}%)",
        f"- Low-confidence (<0.4) — flag for human review: **{low_conf:,}** ({100*low_conf/max(1,n):.0f}%)",
        f"- Workflows the model says SHOULD stay `general`: **{stay_general:,}** ({100*stay_general/max(1,n):.0f}%)",
        "",
        "## Proposed target distribution",
        "",
        "| Target domain | Count | Share |",
        "|---|---|---|",
    ]
    for d, c in sorted(target_counts.items(), key=lambda x: -x[1]):
        lines.append(f"| `{d}` | {c:,} | {100*c/n:.1f}% |")
    lines.append("")

    # Per-target samples (5 each) at high confidence
    lines.append("## Samples per target domain (high-confidence only)")
    lines.append("")
    for d in sorted(target_counts):
        samples = [p for p in proposals if p["proposed_domain"] == d and p["confidence"] >= 0.7][:5]
        if not samples:
            continue
        lines.append(f"### → `{d}` ({target_counts[d]} total)")
        for s in samples:
            lines.append(f"- `{s['name']}` (conf {s['confidence']:.2f}): {s['reason']}")
        lines.append("")

    # Low-confidence flagged
    lc = [p for p in proposals if p["confidence"] < 0.4][:30]
    if lc:
        lines.append("## Low-confidence sample (flagged for human review)")
        lines.append("")
        for s in lc:
            lines.append(f"- `{s['name']}` → `{s['proposed_domain']}` (conf {s['confidence']:.2f}): {s['reason']}")
        lines.append("")

    lines.append("## To apply (NOT done by this script)")
    lines.append("")
    lines.append("Review the JSONL, drop low-confidence entries, then for each accepted row:")
    lines.append("")
    lines.append("```sql")
    lines.append("-- Per name, applied via indexer migration or one-off script:")
    lines.append("UPDATE workflows SET domain = ? WHERE name = ? AND domain = 'general';")
    lines.append("```")
    lines.append("")
    lines.append("Then re-run `python -m galaxy.ai.chain_composer.catalog_audit` to confirm the `general` bucket shrank as expected.")
    return "\n".join(lines)


def _cli(argv=None) -> int:
    p = argparse.ArgumentParser(prog="chain_composer.domain_reclassifier", description=__doc__)
    p.add_argument("--limit", type=int, default=None, help="cap number of workflows (for dry-run)")
    p.add_argument("--offline", action="store_true", help="force offline keyword path (no LLM)")
    p.add_argument("--output", default=None, help="JSONL output path (one row per workflow)")
    p.add_argument("--summary", default=None, help="markdown summary path")
    args = p.parse_args(argv)

    t0 = time.time()
    proposals = reclassify(limit=args.limit, offline=args.offline)
    dt = time.time() - t0

    sys.stderr.write(f"\nClassified {len(proposals)} workflows in {dt:.1f}s.\n")
    sys.stderr.write(f"Methods: {dict(Counter(p['method'] for p in proposals))}\n")
    sys.stderr.write(f"Target distribution top 5: "
                     f"{Counter(p['proposed_domain'] for p in proposals).most_common(5)}\n")

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            for p in proposals:
                f.write(json.dumps(p) + "\n")
        sys.stderr.write(f"wrote {args.output}\n")
    if args.summary:
        Path(args.summary).write_text(render_summary(proposals), encoding="utf-8")
        sys.stderr.write(f"wrote {args.summary}\n")
    if not args.output and not args.summary:
        # Default: emit JSONL to stdout
        for p in proposals:
            sys.stdout.write(json.dumps(p) + "\n")
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(_cli(sys.argv[1:]))
