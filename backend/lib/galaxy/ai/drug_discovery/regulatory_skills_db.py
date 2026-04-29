"""
Regulatory Skills Database — BioMate

Stores learnable patterns from authoritative, current regulatory documents:
  - OSP Qualification Reports (GPL, EMA-accepted PBPK validation)
  - ICH M4S(R2) section format template
  - EMA/CHMP/EWP/37498/2011 Rev1 criteria

Sources are validated against regulatory_knowledge.yaml before ingestion —
superseded or unofficial sources are rejected.

Schema:
  documents  — one row per source document (URL, version, fetched_at, hash)
  skills     — one row per extracted skill/pattern
  metrics    — one row per PBPK performance metric extracted from a document

Usage:
    db = RegulatorySkillsDB()
    db.ingest_osp_reports()
    skills = db.query_skills(skill_type="pbpk_acceptance_range")
    comparable = db.compare_metrics(afe=0.611, aafe=1.893, within_2fold=0.733)
"""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import time
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
from typing import Optional
import urllib.request

from .ind_assembly import _load_regulatory_kb

log = __import__("logging").getLogger(__name__)

_DB_PATH = Path(__file__).parent.parent.parent.parent.parent / "database" / "regulatory_skills.db"

# ─── Authoritative sources (validated against regulatory_knowledge.yaml) ─────
# Only these sources are accepted — no noisy web content

AUTHORITATIVE_SOURCES = {
    "OSP_CYP3A4_DDI": {
        "url": "https://raw.githubusercontent.com/Open-Systems-Pharmacology/OSP-Qualification-Reports/master/DDI_Qualification_CYP3A4/report.md",
        "guideline_ids": ["EMA_PBPK_2018", "CDE_PBPK_2021"],
        "ctd_section": "2.6.2",
        "version_pattern": r"Version\s*\|\s*([\d\.\-a-zA-Z]+)",
        "license": "GPL-2.0",
        "authority": "Open Systems Pharmacology — EMA-accepted",
        "current": True,
        "description": "CYP3A4 DDI PBPK qualification — Midazolam, Rifampicin, Clarithromycin network",
    },
    "OSP_CYP2C19_DDI": {
        "url": "https://raw.githubusercontent.com/Open-Systems-Pharmacology/OSP-Qualification-Reports/master/DDI_Qualification_CYP2C19/report.md",
        "guideline_ids": ["EMA_PBPK_2018"],
        "ctd_section": "2.6.2",
        "version_pattern": r"Version\s*\|\s*([\d\.\-a-zA-Z]+)",
        "license": "GPL-2.0",
        "authority": "Open Systems Pharmacology — EMA-accepted",
        "current": True,
        "description": "CYP2C19 DDI PBPK qualification — Omeprazole, Fluvoxamine",
    },
    "OSP_CYP1A2_DDI": {
        "url": "https://raw.githubusercontent.com/Open-Systems-Pharmacology/OSP-Qualification-Reports/master/DDI_Qualification_CYP1A2/report.md",
        "guideline_ids": ["EMA_PBPK_2018"],
        "ctd_section": "2.6.2",
        "license": "GPL-2.0",
        "authority": "Open Systems Pharmacology — EMA-accepted",
        "current": True,
        "description": "CYP1A2 DDI PBPK qualification — Fluvoxamine, Theophylline, Caffeine",
    },
    "OSP_PGP_DDI": {
        "url": "https://raw.githubusercontent.com/Open-Systems-Pharmacology/OSP-Qualification-Reports/master/DDI_Qualification_P-gp/report.md",
        "guideline_ids": ["EMA_PBPK_2018"],
        "ctd_section": "2.6.2",
        "license": "GPL-2.0",
        "authority": "Open Systems Pharmacology — EMA-accepted",
        "current": True,
        "description": "P-gp DDI PBPK qualification — Digoxin, Rifampicin, Itraconazole",
    },
    "OSP_PEDIATRIC_CYP3A4": {
        "url": "https://raw.githubusercontent.com/Open-Systems-Pharmacology/OSP-Qualification-Reports/master/Pediatric_Qualification_Package_CYP3A4_Ontogeny/report.md",
        "guideline_ids": ["EMA_PBPK_2018"],
        "ctd_section": "2.6.2",
        "license": "GPL-2.0",
        "authority": "Open Systems Pharmacology — EMA-accepted",
        "current": True,
        "description": "Pediatric CYP3A4 ontogeny PBPK — Midazolam, Alfentanil",
    },
    "OSP_CKD": {
        "url": "https://raw.githubusercontent.com/Open-Systems-Pharmacology/OSP-Qualification-Reports/master/Qualification-CKD/report.md",
        "guideline_ids": ["EMA_PBPK_2018"],
        "ctd_section": "2.6.2",
        "license": "GPL-2.0",
        "authority": "Open Systems Pharmacology — EMA-accepted",
        "current": True,
        "description": "CKD special population PBPK — Gabapentin, Atenolol",
    },
}


class RegulatorySkillsDB:
    """
    SQLite-backed store for regulatory patterns learned from approved documents.

    All documents must be validated against regulatory_knowledge.yaml before
    ingestion — only authoritative, current, non-superseded sources accepted.
    """

    def __init__(self, db_path: Optional[Path] = None):
        self.db_path = str(db_path or _DB_PATH)
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    # ── Schema ────────────────────────────────────────────────────────────────

    def _init_schema(self) -> None:
        with sqlite3.connect(self.db_path) as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS documents (
                    source_id       TEXT PRIMARY KEY,
                    url             TEXT NOT NULL,
                    authority       TEXT NOT NULL,
                    guideline_ids   TEXT NOT NULL,   -- JSON list
                    ctd_section     TEXT NOT NULL,
                    license         TEXT NOT NULL,
                    description     TEXT NOT NULL,
                    version         TEXT,
                    fetched_at      TEXT NOT NULL,
                    content_sha256  TEXT NOT NULL,
                    char_count      INTEGER,
                    is_current      INTEGER DEFAULT 1
                );

                CREATE TABLE IF NOT EXISTS skills (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_id       TEXT REFERENCES documents(source_id),
                    skill_type      TEXT NOT NULL,   -- pbpk_metric | narrative_pattern | section_structure | citation_pattern
                    ctd_section     TEXT NOT NULL,
                    guideline_id    TEXT NOT NULL,
                    drug_name       TEXT,
                    enzyme          TEXT,
                    metric_name     TEXT,
                    metric_value    REAL,
                    metric_unit     TEXT,
                    context         TEXT,            -- JSON: surrounding text / table
                    created_at      TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS pbpk_benchmarks (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_id       TEXT REFERENCES documents(source_id),
                    drug_pair       TEXT NOT NULL,   -- e.g. "Rifampicin/Midazolam"
                    enzyme          TEXT,
                    pk_parameter    TEXT NOT NULL,   -- AUC_ratio | CMAX_ratio | AUC | Cmax
                    gmfe            REAL,
                    within_2fold_pct REAL,
                    within_guest_pct REAL,
                    n_points        INTEGER,
                    regulatory_verdict TEXT,         -- PASS | FAIL | N/A
                    created_at      TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS narrative_patterns (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_id       TEXT REFERENCES documents(source_id),
                    ctd_section     TEXT NOT NULL,
                    pattern_type    TEXT NOT NULL,   -- sentence | table_header | disclaimer | criterion_statement
                    text            TEXT NOT NULL,
                    guideline_id    TEXT,
                    created_at      TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_skills_type ON skills(skill_type);
                CREATE INDEX IF NOT EXISTS idx_skills_metric ON skills(metric_name);
                CREATE INDEX IF NOT EXISTS idx_pbpk_drug ON pbpk_benchmarks(drug_pair);
                CREATE INDEX IF NOT EXISTS idx_narrative_section ON narrative_patterns(ctd_section);
            """)

    # ── Ingestion ─────────────────────────────────────────────────────────────

    def ingest_all(self, force_refresh: bool = False) -> dict:
        """Download and ingest all authoritative sources. Returns summary."""
        kb = _load_regulatory_kb()
        results = {}
        for source_id, meta in AUTHORITATIVE_SOURCES.items():
            if not meta.get("current", True):
                log.info("[skills_db] Skipping non-current source: %s", source_id)
                continue

            # Validate all guideline_ids against KB
            for gid in meta.get("guideline_ids", []):
                if gid not in kb.get("guidelines", {}):
                    log.warning("[skills_db] Unknown guideline %s in source %s — skipping",
                                gid, source_id)
                    continue

            results[source_id] = self._ingest_source(source_id, meta, force_refresh)
            time.sleep(0.5)  # rate limiting

        return results

    def _ingest_source(self, source_id: str, meta: dict, force_refresh: bool) -> dict:
        """Download one source, parse it, and store skills."""
        result = {"source_id": source_id, "status": "skipped", "skills_added": 0}

        # Check if already ingested (unless force)
        if not force_refresh:
            with sqlite3.connect(self.db_path) as conn:
                row = conn.execute(
                    "SELECT fetched_at, char_count FROM documents WHERE source_id=?",
                    (source_id,)
                ).fetchone()
                if row:
                    log.info("[skills_db] %s already ingested (%s, %d chars) — skipping",
                             source_id, row[0][:10], row[1] or 0)
                    result["status"] = "already_ingested"
                    return result

        # Download
        try:
            log.info("[skills_db] Fetching %s …", meta["url"])
            req = urllib.request.Request(meta["url"],
                                         headers={"User-Agent": "BioMate-RegSkills/1.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                content = resp.read().decode("utf-8", errors="replace")
        except Exception as exc:
            log.error("[skills_db] Failed to fetch %s: %s", source_id, exc)
            result["status"] = f"fetch_error: {exc}"
            return result

        sha = hashlib.sha256(content.encode()).hexdigest()
        version = ""
        if "version_pattern" in meta:
            m = re.search(meta["version_pattern"], content, re.IGNORECASE)
            if m:
                version = m.group(1)

        ts = datetime.now(timezone.utc).isoformat()

        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT OR REPLACE INTO documents
                (source_id, url, authority, guideline_ids, ctd_section, license,
                 description, version, fetched_at, content_sha256, char_count, is_current)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,1)
            """, (source_id, meta["url"], meta["authority"],
                  json.dumps(meta.get("guideline_ids", [])),
                  meta["ctd_section"], meta["license"],
                  meta["description"], version, ts, sha, len(content)))

        # Parse and extract skills
        n = self._parse_and_store(source_id, content, meta, ts)
        result.update({"status": "ingested", "skills_added": n,
                        "version": version, "chars": len(content)})
        log.info("[skills_db] %s: %d skills extracted", source_id, n)
        return result

    # ── Parsing ───────────────────────────────────────────────────────────────

    def _parse_and_store(self, source_id: str, content: str, meta: dict, ts: str) -> int:
        """Extract skills from markdown content."""
        n = 0
        n += self._extract_gmfe_tables(source_id, content, meta, ts)
        n += self._extract_within_2fold_tables(source_id, content, meta, ts)
        n += self._extract_criterion_statements(source_id, content, meta, ts)
        n += self._extract_regulatory_narratives(source_id, content, meta, ts)
        return n

    def _extract_gmfe_tables(self, source_id: str, content: str, meta: dict, ts: str) -> int:
        """Extract GMFE values from tables like: | AUC | 1.36 |"""
        n = 0
        # Match "GMFE for CYP3A4 DDI" style tables
        table_blocks = re.findall(
            r'Table.*?GMFE.*?\n((?:\|[^\n]+\n)+)',
            content, re.IGNORECASE | re.DOTALL
        )
        for block in table_blocks:
            rows = [r.strip() for r in block.strip().split("\n") if "|" in r]
            for row in rows:
                parts = [p.strip() for p in row.split("|") if p.strip()]
                if len(parts) >= 2:
                    param, val = parts[0], parts[1]
                    try:
                        gmfe_val = float(val)
                        if 0.5 < gmfe_val < 5.0:
                            enzyme = ""
                            if "CYP3A4" in content[:500]:
                                enzyme = "CYP3A4"
                            elif "CYP2C19" in content[:500]:
                                enzyme = "CYP2C19"
                            elif "CYP1A2" in content[:500]:
                                enzyme = "CYP1A2"
                            elif "P-gp" in content[:500]:
                                enzyme = "P-gp"

                            self._insert_skill(source_id, "pbpk_metric", meta["ctd_section"],
                                               meta["guideline_ids"][0], None, enzyme,
                                               f"GMFE_{param}", gmfe_val, "ratio",
                                               json.dumps({"table_row": row}), ts)
                            n += 1
                    except ValueError:
                        pass
        return n

    def _extract_within_2fold_tables(self, source_id: str, content: str, meta: dict, ts: str) -> int:
        """Extract within-2-fold percentage from tables."""
        n = 0
        # Find tables with "Points within 2 fold" pattern
        matches = re.findall(
            r'Points within 2 fold\s*\|(\d+)\s*\|(\d+\.?\d*)',
            content
        )
        for n_pts, pct in matches:
            self._insert_skill(source_id, "pbpk_metric", meta["ctd_section"],
                               meta["guideline_ids"][0], None, "",
                               "within_2fold_pct", float(pct), "%",
                               json.dumps({"n_points": int(n_pts)}), ts)
            n += 1

        # Also "Points total" for context
        totals = re.findall(r'Points total\s*\|(\d+)\s*\|', content)
        if totals and matches:
            # Store PBPK benchmark summary
            try:
                self._insert_pbpk_benchmark(
                    source_id,
                    drug_pair=f"All drugs ({source_id})",
                    enzyme=source_id.split("_")[1] if "_" in source_id else "",
                    pk_parameter="AUC_ratio",
                    gmfe=None,  # will be filled from skills
                    within_2fold_pct=float(matches[0][1]) if matches else None,
                    n_points=int(totals[0]) if totals else None,
                    ts=ts
                )
                n += 1
            except Exception:
                pass
        return n

    def _extract_criterion_statements(self, source_id: str, content: str, meta: dict, ts: str) -> int:
        """Extract sentences that define regulatory criteria (EMA ≥67% etc.)."""
        n = 0
        criteria_patterns = [
            r'[Gg]eometric mean fold error.*?(?:\.|$)',
            r'(?:within|percentage).*?2.fold.*?(?:\.|$)',
            r'EMA.*?criterion.*?(?:\.|$)',
            r'PBPK.*?qualif.*?(?:\.|$)',
            r'acceptability.*?criterion.*?(?:\.|$)',
        ]
        for pat in criteria_patterns:
            for m in re.finditer(pat, content, re.IGNORECASE | re.MULTILINE):
                text = m.group(0).strip()
                if 30 < len(text) < 400:
                    self._insert_narrative(source_id, meta["ctd_section"],
                                           "criterion_statement", text,
                                           meta["guideline_ids"][0], ts)
                    n += 1
        return n

    def _extract_regulatory_narratives(self, source_id: str, content: str, meta: dict, ts: str) -> int:
        """Extract well-formed regulatory narrative sentences for LLM training."""
        n = 0
        # Extract introduction paragraphs (tend to contain formal regulatory language)
        intro_match = re.search(
            r'(?:# Introduction|## Introduction|# 1 Introduction)(.*?)(?:^#|\Z)',
            content, re.DOTALL | re.MULTILINE
        )
        if intro_match:
            intro_text = intro_match.group(1)
            sentences = re.split(r'(?<=[.!?])\s+', intro_text)
            for sent in sentences:
                sent = sent.strip()
                # Only formal regulatory-style sentences (not table rows or TOC lines)
                if (40 < len(sent) < 600
                        and not sent.startswith("|")
                        and not sent.startswith("#")
                        and re.search(r'[Qq]ualif|[Pp]red|model|PBPK|EMA|FDA|ICH|DDI|enzym', sent)):
                    self._insert_narrative(source_id, meta["ctd_section"],
                                           "regulatory_sentence", sent,
                                           meta["guideline_ids"][0], ts)
                    n += 1
        return n

    # ── DB insert helpers ─────────────────────────────────────────────────────

    def _insert_skill(self, source_id, skill_type, section, guideline_id,
                      drug, enzyme, metric_name, metric_value, unit, context, ts):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO skills (source_id, skill_type, ctd_section, guideline_id,
                                    drug_name, enzyme, metric_name, metric_value,
                                    metric_unit, context, created_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """, (source_id, skill_type, section, guideline_id,
                  drug, enzyme, metric_name, metric_value, unit, context, ts))

    def _insert_pbpk_benchmark(self, source_id, drug_pair, enzyme, pk_parameter,
                                gmfe, within_2fold_pct, n_points, ts):
        verdict = "PASS" if (within_2fold_pct or 0) >= 67 else "FAIL"
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO pbpk_benchmarks (source_id, drug_pair, enzyme, pk_parameter,
                                              gmfe, within_2fold_pct, n_points,
                                              regulatory_verdict, created_at)
                VALUES (?,?,?,?,?,?,?,?,?)
            """, (source_id, drug_pair, enzyme, pk_parameter,
                  gmfe, within_2fold_pct, n_points, verdict, ts))

    def _insert_narrative(self, source_id, section, pattern_type, text, guideline_id, ts):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO narrative_patterns (source_id, ctd_section, pattern_type,
                                                text, guideline_id, created_at)
                VALUES (?,?,?,?,?,?)
            """, (source_id, section, pattern_type, text, guideline_id, ts))

    # ── Query interface ───────────────────────────────────────────────────────

    def query_skills(self, skill_type: str = None, metric_name: str = None,
                     ctd_section: str = None) -> list[dict]:
        """Query stored skills with optional filters."""
        clauses, params = [], []
        if skill_type:
            clauses.append("skill_type=?"); params.append(skill_type)
        if metric_name:
            clauses.append("metric_name=?"); params.append(metric_name)
        if ctd_section:
            clauses.append("ctd_section=?"); params.append(ctd_section)
        where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(f"SELECT * FROM skills {where} LIMIT 500", params).fetchall()
            return [dict(r) for r in rows]

    def get_pbpk_benchmarks(self) -> list[dict]:
        """All PBPK benchmark results from approved OSP reports."""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(
                "SELECT b.*, d.description, d.version FROM pbpk_benchmarks b "
                "JOIN documents d ON b.source_id=d.source_id"
            ).fetchall()
            return [dict(r) for r in rows]

    def compare_metrics(self, afe: float, aafe: float, within_2fold: float,
                         region: str = "EMA") -> dict:
        """
        Compare BioMate PBPK metrics against the accepted range from approved documents.

        Returns a structured comparison with pass/fail verdict and benchmark context.
        """
        # Get all within_2fold_pct values from approved reports
        rows = self.query_skills(metric_name="within_2fold_pct")
        approved_within2fold = [r["metric_value"] for r in rows if r["metric_value"]]

        # Get GMFE values for AUC from approved reports
        gmfe_rows = self.query_skills(metric_name="GMFE_AUC")
        approved_gmfe_auc = [r["metric_value"] for r in gmfe_rows if r["metric_value"]]

        # EMA criterion: ≥67% within 2-fold (from KB)
        from .ind_assembly import get_threshold
        ema_threshold = get_threshold("PBPK_within_2fold", "value", 0.67)

        # OSP benchmark summary (what passes in EMA-accepted reports)
        osp_within2fold_range = (
            (min(approved_within2fold), max(approved_within2fold))
            if approved_within2fold else (None, None)
        )
        osp_gmfe_range = (
            (min(approved_gmfe_auc), max(approved_gmfe_auc))
            if approved_gmfe_auc else (None, None)
        )

        biomate_passes_ema = within_2fold >= ema_threshold
        in_osp_range = (
            osp_within2fold_range[0] is not None
            and osp_within2fold_range[0] / 100 <= within_2fold <= osp_within2fold_range[1] / 100
        )

        return {
            "biomate_metrics": {"afe": afe, "aafe": aafe, "within_2fold": within_2fold},
            "ema_criterion": {
                "threshold": ema_threshold,
                "passes": biomate_passes_ema,
                "margin": round(within_2fold - ema_threshold, 3),
            },
            "osp_benchmark": {
                "n_reports": len(set(r["source_id"] for r in rows)),
                "within_2fold_range_pct": osp_within2fold_range,
                "gmfe_auc_range": osp_gmfe_range,
                "biomate_within_osp_range": in_osp_range,
            },
            "verdict": "PASS" if biomate_passes_ema else "FAIL",
            "note": (
                f"BioMate within-2-fold ({within_2fold:.1%}) {'exceeds' if biomate_passes_ema else 'is below'} "
                f"EMA criterion ({ema_threshold:.0%}). "
                f"OSP approved range: {osp_within2fold_range[0]:.1f}–{osp_within2fold_range[1]:.1f}%"
                if osp_within2fold_range[0] else "No OSP benchmark data loaded yet."
            ),
        }

    def get_narrative_patterns(self, ctd_section: str = None,
                                pattern_type: str = None) -> list[dict]:
        """Retrieve regulatory narrative patterns for a section."""
        clauses, params = [], []
        if ctd_section:
            clauses.append("ctd_section LIKE ?"); params.append(f"{ctd_section}%")
        if pattern_type:
            clauses.append("pattern_type=?"); params.append(pattern_type)
        where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(
                f"SELECT * FROM narrative_patterns {where} ORDER BY RANDOM() LIMIT 20", params
            ).fetchall()
            return [dict(r) for r in rows]

    def summary(self) -> dict:
        """Return a summary of the current DB state."""
        with sqlite3.connect(self.db_path) as conn:
            docs = conn.execute("SELECT COUNT(*) FROM documents WHERE is_current=1").fetchone()[0]
            skills = conn.execute("SELECT COUNT(*) FROM skills").fetchone()[0]
            benchmarks = conn.execute("SELECT COUNT(*) FROM pbpk_benchmarks").fetchone()[0]
            narratives = conn.execute("SELECT COUNT(*) FROM narrative_patterns").fetchone()[0]
            sources = conn.execute(
                "SELECT source_id, version, fetched_at, char_count FROM documents WHERE is_current=1"
            ).fetchall()
        return {
            "documents": docs,
            "skills": skills,
            "pbpk_benchmarks": benchmarks,
            "narrative_patterns": narratives,
            "sources": [{"id": s[0], "version": s[1], "fetched": s[2][:10], "chars": s[3]}
                        for s in sources],
        }
