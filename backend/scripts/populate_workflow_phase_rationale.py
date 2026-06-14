#!/usr/bin/env python3
"""Populate workflow_phase_rationale from the bioconductor handoff design.

Implements section 5 of docs/20260614_RATIONALE_ANCHOR_PLAN.md.

Creates the table if needed (schema from §1 of the plan), then walks the
24-row curation source mapping (§2 of the plan) — every `rationale_text`
is a verbatim quote from a specific `BiocTours.jsx:line` body, and every
`citation_doi` / `citation_title` is resolved from a specific
`qc_evidence.yaml` gate.

No new prose is authored — strings are loaded from the cited files and
stripped of JSX tags by a small regex pass. Re-runs are idempotent
(INSERT … ON CONFLICT REPLACE on the (workflow_id, phase_id) primary key).

Usage:
  python3 backend/scripts/populate_workflow_phase_rationale.py            # dry-run
  python3 backend/scripts/populate_workflow_phase_rationale.py --apply
  python3 backend/scripts/populate_workflow_phase_rationale.py --apply --verbose
"""
from __future__ import annotations

import argparse
import logging
import os
import re
import sqlite3
import sys
import time
from typing import Dict, Optional, Tuple

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB_PATH = os.path.join(ROOT, "backend", "database", "galaxy_ai_tools.db")
BIOC_TOURS_JSX = os.path.join(
    ROOT, "reference", "claude_design", "bioconductor-handoff", "src", "BiocTours.jsx"
)
QC_EVIDENCE_YAML = os.path.join(ROOT, "backend", "config", "qc_evidence.yaml")

# Mapping from §2 of the plan. Each tuple: (chain_name, phase_id, source_line,
# qc_evidence_gate_or_None). source_line is the 1-based line of the `body: (<>…</>)`
# (or `previewBody:` / `completeBody:`) we extract the rationale_text from.
ROWS = [
    # ── Chain 1 — bulk_rnaseq_consensus_de_bioc (transcriptomics, 6 phases) ──
    ("bulk_rnaseq_consensus_de_bioc", "A_qc",      135, None),
    ("bulk_rnaseq_consensus_de_bioc", "B_norm",    141, "deseq2_negative_binomial_fit"),
    ("bulk_rnaseq_consensus_de_bioc", "C_de",      147, "deseq2_negative_binomial_fit"),
    ("bulk_rnaseq_consensus_de_bioc", "D_shrink",  153, "apeglm_lfc_shrinkage"),
    ("bulk_rnaseq_consensus_de_bioc", "E_enrich",  159, "clusterprofiler_enrichment"),
    ("bulk_rnaseq_consensus_de_bioc", "F_viz",     166, None),
    # ── Chain 2 — scrna_consensus_de_bioc (single_cell, 7 phases) ──
    ("scrna_consensus_de_bioc",       "A_qc",            215, "scater_qc_normalization"),
    ("scrna_consensus_de_bioc",       "B_norm",          221, "scran_normalization_hvg"),
    ("scrna_consensus_de_bioc",       "C_cluster",       227, "scran_normalization_hvg"),
    ("scrna_consensus_de_bioc",       "D_markers",       233, "score_markers_per_cluster"),
    ("scrna_consensus_de_bioc",       "E_annotate",      233, "singler_celltype_annotation"),
    ("scrna_consensus_de_bioc",       "F_pseudobulk_de", 239, "pseudobulk_aggregation_deseq2"),
    ("scrna_consensus_de_bioc",       "G_report",        248, None),
    # ── Chain 3 — methylation_450k_array_analysis (epigenomics, 5 phases) ──
    ("methylation_450k_array_analysis", "A_read",     295, "minfi_array_processing"),
    ("methylation_450k_array_analysis", "B_qc_norm",  301, "minfi_array_processing"),
    ("methylation_450k_array_analysis", "C_dmp",      307, "limma_dmp_test"),
    ("methylation_450k_array_analysis", "D_dmr",      313, "dmrcate_region_call"),
    ("methylation_450k_array_analysis", "E_enrich",   319, "missmethyl_cpg_corrected_go"),
    # ── Chain 4 — scrna_pseudobulk_de_bioc (single_cell, 6 phases) ──
    ("scrna_pseudobulk_de_bioc",       "A_qc",          215, "scater_qc_normalization"),
    ("scrna_pseudobulk_de_bioc",       "B_norm_hvg",    221, "scran_normalization_hvg"),
    ("scrna_pseudobulk_de_bioc",       "C_cluster",     227, "scran_normalization_hvg"),
    ("scrna_pseudobulk_de_bioc",       "D_annotate",    233, "singler_celltype_annotation"),
    ("scrna_pseudobulk_de_bioc",       "E_pseudobulk",  239, "pseudobulk_aggregation_deseq2"),
    ("scrna_pseudobulk_de_bioc",       "F_report",      248, None),
]

CREATE_SCHEMA = """
CREATE TABLE IF NOT EXISTS workflow_phase_rationale (
  workflow_id      INTEGER NOT NULL,
  phase_id         TEXT    NOT NULL,
  rationale_text   TEXT    NOT NULL,
  citation_doi     TEXT,
  citation_title   TEXT,
  qc_gate_name     TEXT,
  last_curated_at  INTEGER NOT NULL,
  PRIMARY KEY (workflow_id, phase_id)
);
CREATE INDEX IF NOT EXISTS idx_wpr_workflow ON workflow_phase_rationale(workflow_id);
"""

# JSX → plain text conversion. Strip:
#   <tag>, </tag>, self-closing <tag/>, <tag attr="…">, code blocks etc.
# Keep the textual content. Convert common entities and JSX braces.
_JSX_TAG_RE = re.compile(r"<[^>]+>")
_JSX_BRACE_RE = re.compile(r"\{[^{}]*\}")  # strip {expression} content


def _strip_jsx(s: str) -> str:
    """Render a JSX body literal as plain UTF-8 text."""
    # Remove the wrapping (<>…</>) Fragment if present.
    s = s.strip()
    # Drop trailing hint <div className="hint">…</div> blocks — they're
    # secondary text not appropriate for the rationale_text payload.
    s = re.sub(r'<div className="hint">.*?</div>', "", s, flags=re.S)
    # Strip JSX braces with expressions
    s = _JSX_BRACE_RE.sub("", s)
    # Strip all tags
    s = _JSX_TAG_RE.sub("", s)
    # Common HTML entities used in the source
    s = s.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")
    # Collapse whitespace
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _extract_body_at_line(source_lines: list[str], one_based_line: int) -> str:
    """Read the JSX body starting at the given line ("body: (<>…</>),").

    The body field can span multiple lines until the matching </>).
    We greedy-match from `(<>` to the closing `)`.
    """
    # Walk from the cited line until we find the body literal.
    idx = max(0, one_based_line - 1)
    # Gather a window of lines around the cite for the regex match.
    window = "\n".join(source_lines[idx:idx + 8])
    # Match body: (<>…</>) — non-greedy stops at first </>
    m = re.search(r"(?:body|previewBody|completeBody|methodsBody|paramsBody|softwareBody|citeBody|qcBody|findingsBody|outputsBody):\s*\(<>(.*?)</>\)", window, re.S)
    if not m:
        # Fall back to single-line body
        m = re.search(r"(?:body|previewBody|completeBody):\s*'([^']+)'", window)
        if not m:
            raise ValueError(f"could not parse body literal near line {one_based_line}")
    return _strip_jsx(m.group(1))


def _load_qc_evidence() -> Dict[str, Tuple[Optional[str], Optional[str]]]:
    """Return {gate_name: (paper_doi, paper_ref)} from qc_evidence.yaml.

    Picks the first evidence item in each gate (the canonical reference).
    """
    with open(QC_EVIDENCE_YAML) as fh:
        ev = yaml.safe_load(fh) or {}
    out: Dict[str, Tuple[Optional[str], Optional[str]]] = {}
    for domain, gates in ev.items():
        if not isinstance(gates, dict):
            continue
        for gate_name, items in gates.items():
            if not isinstance(items, list) or not items:
                continue
            first = items[0]
            if not isinstance(first, dict):
                continue
            out[gate_name] = (first.get("paper_doi"), first.get("paper_ref"))
    return out


def _resolve_workflow_id(conn: sqlite3.Connection, chain_name: str) -> Optional[int]:
    row = conn.execute(
        "SELECT id FROM workflow_chains WHERE name=? LIMIT 1", (chain_name,)
    ).fetchone()
    return int(row[0]) if row else None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--apply", action="store_true", help="Persist; default is dry-run.")
    ap.add_argument("--verbose", action="store_true", help="Log each row.")
    args = ap.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(message)s",
    )
    log = logging.getLogger("populate_wpr")

    if not os.path.exists(DB_PATH):
        log.error("DB not found: %s", DB_PATH)
        return 1
    if not os.path.exists(BIOC_TOURS_JSX):
        log.error("BiocTours.jsx not found: %s", BIOC_TOURS_JSX)
        return 1

    with open(BIOC_TOURS_JSX) as fh:
        jsx_lines = fh.read().splitlines()
    qc_refs = _load_qc_evidence()
    log.info("Loaded qc_evidence: %d gates", len(qc_refs))

    now = int(time.time())
    rows_to_write: list[Tuple[int, str, str, Optional[str], Optional[str], Optional[str], int]] = []

    with sqlite3.connect(DB_PATH) as conn:
        # Cache workflow_id resolutions to keep the script log readable.
        wf_cache: Dict[str, Optional[int]] = {}
        unresolved: list[str] = []
        for chain_name, phase_id, src_line, gate in ROWS:
            if chain_name not in wf_cache:
                wf_cache[chain_name] = _resolve_workflow_id(conn, chain_name)
            wid = wf_cache[chain_name]
            if wid is None:
                unresolved.append(chain_name)
                log.warning("skip: chain %r not in workflow_chains", chain_name)
                continue
            try:
                rationale = _extract_body_at_line(jsx_lines, src_line)
            except ValueError as exc:
                log.warning("skip: %s phase %s line %d — %s", chain_name, phase_id, src_line, exc)
                continue
            cite_doi: Optional[str] = None
            cite_title: Optional[str] = None
            if gate and gate in qc_refs:
                cite_doi, cite_title = qc_refs[gate]
            row = (wid, phase_id, rationale, cite_doi, cite_title, gate, now)
            rows_to_write.append(row)
            log.debug(
                "  + wid=%d phase=%s gate=%s len(text)=%d cite=%s",
                wid, phase_id, gate, len(rationale), (cite_doi or "—"),
            )

        log.info("rows to write: %d (unresolved chains: %d)", len(rows_to_write), len(unresolved))

        if not args.apply:
            for r in rows_to_write[:3]:
                log.info("  sample → wid=%d phase=%s text[:80]=%r cite=%s",
                         r[0], r[1], r[2][:80], r[3] or "—")
            log.info("(dry-run; re-run with --apply to persist)")
            return 0

        # Create schema + upsert
        conn.executescript(CREATE_SCHEMA)
        conn.executemany(
            """
            INSERT INTO workflow_phase_rationale (workflow_id, phase_id, rationale_text,
                                                   citation_doi, citation_title,
                                                   qc_gate_name, last_curated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(workflow_id, phase_id) DO UPDATE SET
              rationale_text  = excluded.rationale_text,
              citation_doi    = excluded.citation_doi,
              citation_title  = excluded.citation_title,
              qc_gate_name    = excluded.qc_gate_name,
              last_curated_at = excluded.last_curated_at
            """,
            rows_to_write,
        )
        conn.commit()
        log.info("wrote %d rows", len(rows_to_write))
    return 0


if __name__ == "__main__":
    sys.exit(main())
