#!/usr/bin/env python3
"""Populate rationale_registry from rationale_mapping.yaml + qc_evidence.yaml.

Implements Phase 1 of docs/20260614_EVIDENCE_RATIONALE_DATA_PLAN.md.

Reads:
  - backend/config/rationale_mapping.yaml — scientific-lead worksheet
    (one phase per chain, with qc_gate_name + confirmed flag)
  - backend/config/qc_evidence.yaml — supplies paper_doi, paper_ref,
    paper_supports text for each gate
  - workflow_phase_rationale (existing table) — bioc chain rows seeded
    in week-1 from BiocTours.jsx

Writes:
  - rationale_registry table — keyed by `rationale_id` (e.g.
    `bulk_rnaseq:B`), shape matches the design's
    window.RESEARCH_PHASE_TRACE pattern.

Schema (matching design's 4-block shape; events/params/cost are joined
at endpoint time when invocation_id is supplied):

    CREATE TABLE rationale_registry (
      rationale_id     TEXT PRIMARY KEY,    -- '<chain>:<phase>' e.g. 'bulk_rnaseq_consensus_de_bioc:B'
      rationale_text   TEXT NOT NULL,       -- the "Why this method" prose
      citation_doi     TEXT,                -- nullable
      citation_title   TEXT,                -- nullable
      qc_gate_name     TEXT,                -- traceback to qc_evidence.yaml
      curated_by       TEXT,                -- scientific-lead identifier
      last_curated_at  INTEGER NOT NULL
    );

Rules:
  - Bioc chains: pulled verbatim from workflow_phase_rationale (week-1
    table). Bioc rows are always "confirmed" — they were authored
    from BiocTours.jsx line citations.
  - Other chains: pulled from rationale_mapping.yaml ONLY where the
    row carries `confirmed: true`. Suggested / unsuggested / gap rows
    are skipped silently (the WhyAnchor renders nothing for missing
    rationale_id).

Idempotent UPSERT on rationale_id. Re-runs are safe.

Usage:
  python3 backend/scripts/populate_rationale_registry.py            # dry-run
  python3 backend/scripts/populate_rationale_registry.py --apply
"""
from __future__ import annotations

import argparse
import logging
import os
import sqlite3
import sys
import time
from typing import Dict, List, Optional, Tuple

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB_PATH = os.path.join(ROOT, "backend", "database", "galaxy_ai_tools.db")
QC_PATH = os.path.join(ROOT, "backend", "config", "qc_evidence.yaml")
MAPPING_PATH = os.path.join(ROOT, "backend", "config", "rationale_mapping.yaml")

CREATE_SCHEMA = """
CREATE TABLE IF NOT EXISTS rationale_registry (
  rationale_id     TEXT PRIMARY KEY,
  rationale_text   TEXT NOT NULL,
  citation_doi     TEXT,
  citation_title   TEXT,
  qc_gate_name     TEXT,
  curated_by       TEXT,
  last_curated_at  INTEGER NOT NULL
);
"""

log = logging.getLogger("populate_rationale_registry")
logging.basicConfig(level=logging.INFO, format="%(message)s")


def _load_qc_evidence() -> Dict[str, Tuple[Optional[str], Optional[str], Optional[str]]]:
    """Return {gate_name: (paper_doi, paper_ref, paper_supports)} from qc_evidence."""
    with open(QC_PATH) as fh:
        ev = yaml.safe_load(fh) or {}
    out: Dict[str, Tuple[Optional[str], Optional[str], Optional[str]]] = {}
    for _domain, gates in ev.items():
        if not isinstance(gates, dict):
            continue
        for gate_name, items in gates.items():
            if not isinstance(items, list) or not items:
                continue
            first = items[0]
            if not isinstance(first, dict):
                continue
            out[gate_name] = (
                first.get("paper_doi"),
                first.get("paper_ref"),
                (first.get("paper_supports") or "").strip(),
            )
    return out


def _bioc_rows_from_existing_table(conn: sqlite3.Connection,
                                    chains_by_id: Dict[int, str]
                                    ) -> List[Tuple[str, str, Optional[str], Optional[str], Optional[str], str, int]]:
    """Pull bioc chain rows from workflow_phase_rationale, rekey to rationale_id.

    Bioc rows are authoritative (curated from BiocTours.jsx line citations
    in week-1) — preserved as-is.
    """
    rows = conn.execute(
        "SELECT workflow_id, phase_id, rationale_text, citation_doi, "
        "citation_title, qc_gate_name, last_curated_at "
        "FROM workflow_phase_rationale"
    ).fetchall()
    out = []
    for wid, phase, rtext, doi, title, gate, ts in rows:
        chain_name = chains_by_id.get(wid)
        if not chain_name:
            continue
        rid = f"{chain_name}:{phase}"
        out.append((rid, rtext, doi, title, gate, "bioc-week1-auto", int(ts) if ts else int(time.time())))
    return out


def _mapping_rows(qc_refs: Dict[str, Tuple[Optional[str], Optional[str], Optional[str]]],
                   now: int
                   ) -> List[Tuple[str, str, Optional[str], Optional[str], Optional[str], str, int]]:
    """Pull confirmed rows from rationale_mapping.yaml + join qc_evidence.

    Skips unconfirmed (suggested) + gap rows. The scientific lead flips
    `confirmed: true` per row to make it consumable here.
    """
    if not os.path.exists(MAPPING_PATH):
        log.warning("mapping file not found: %s (no rows from mapping yaml)", MAPPING_PATH)
        return []
    with open(MAPPING_PATH) as fh:
        data = yaml.safe_load(fh) or {}
    chains = data.get("chains") or {}
    out = []
    for chain_name, block in chains.items():
        for phase in block.get("phases") or []:
            if not phase.get("confirmed"):
                continue
            gate = phase.get("qc_gate_name")
            if not gate or gate not in qc_refs:
                log.warning("  skip %s phase %s — confirmed but no qc gate ref",
                            chain_name, phase.get("phase_id"))
                continue
            doi, title, supports = qc_refs[gate]
            if not supports:
                continue
            rid = phase.get("rationale_id") or f"{chain_name}:{phase.get('phase_id')}"
            out.append((
                rid, supports, doi, title, gate,
                phase.get("curated_by") or "mapping-yaml",
                now,
            ))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--apply", action="store_true", help="Persist (default: dry-run).")
    args = ap.parse_args()

    if not os.path.exists(DB_PATH):
        log.error("DB not found: %s", DB_PATH)
        return 1
    qc_refs = _load_qc_evidence()
    log.info("Loaded qc_evidence: %d gates", len(qc_refs))

    now = int(time.time())
    with sqlite3.connect(DB_PATH) as conn:
        chains_by_id: Dict[int, str] = {
            int(r[0]): r[1] for r in conn.execute(
                "SELECT id, name FROM workflow_chains").fetchall()
        }

        bioc_rows = _bioc_rows_from_existing_table(conn, chains_by_id)
        mapping_rows = _mapping_rows(qc_refs, now)
        all_rows = bioc_rows + mapping_rows
        log.info("rows to write: %d (bioc=%d, mapping=%d)",
                 len(all_rows), len(bioc_rows), len(mapping_rows))

        if not args.apply:
            for r in all_rows[:3]:
                log.info("  sample → %s | text=%r... | cite=%s",
                         r[0], r[1][:60], r[2] or "—")
            log.info("(dry-run; re-run with --apply to persist)")
            return 0

        conn.executescript(CREATE_SCHEMA)
        conn.executemany(
            """
            INSERT INTO rationale_registry (rationale_id, rationale_text,
                                            citation_doi, citation_title,
                                            qc_gate_name, curated_by,
                                            last_curated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(rationale_id) DO UPDATE SET
              rationale_text  = excluded.rationale_text,
              citation_doi    = excluded.citation_doi,
              citation_title  = excluded.citation_title,
              qc_gate_name    = excluded.qc_gate_name,
              curated_by      = excluded.curated_by,
              last_curated_at = excluded.last_curated_at
            """,
            all_rows,
        )
        conn.commit()
        log.info("wrote %d rows", len(all_rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
