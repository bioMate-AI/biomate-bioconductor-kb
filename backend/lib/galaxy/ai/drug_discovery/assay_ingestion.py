"""
Core ingestion logic for BioMate assay data.

Handles CSV parsing, validation, SQLite persistence, and compound ranking.
"""
import sqlite3
from datetime import datetime, timezone
from statistics import mean
from typing import Optional

from .assay_schema import AssayCSVValidator, SUPPORTED_ASSAY_TYPES

# Assay types where a lower measured value = better therapeutic potency.
_LOWER_IS_BETTER = {"IC50", "Ki", "Kd", "EC50"}

# Assay types where a HIGHER measured value = better safety profile.
# hERG IC50: higher IC50 means the drug is less cardiotoxic.
# solubility: higher is better for bioavailability.
# permeability: higher Caco-2/PAMPA is better for absorption.
_HIGHER_IS_BETTER = {"hERG", "solubility", "permeability"}

# hERG safety gate: IC50 below this threshold (µM) triggers a safety penalty.
# ICH S7B guideline: safety concern if hERG IC50 < 30× therapeutic Cmax;
# empirical threshold used here is 10 µM (conservative, widely cited).
_HERG_SAFETY_THRESHOLD_uM = 10.0
_HERG_SAFETY_PENALTY = 0.3

# Flag assay types whose value encodes a binary safety flag (1 = fail).
_SAFETY_FLAG_TYPES = {"DILI", "Ames", "ClinTox"}

# Penalty applied to combined_score when a safety flag is positive.
_SAFETY_PENALTY = 0.3


class AssayIngestionService:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self._validator = AssayCSVValidator()
        self.ensure_schema()

    # ------------------------------------------------------------------
    # Schema management
    # ------------------------------------------------------------------

    def ensure_schema(self):
        """Create SQLite tables if they do not already exist."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS campaign_assay_results (
                    id               INTEGER PRIMARY KEY AUTOINCREMENT,
                    campaign_id      TEXT NOT NULL,
                    compound_id      TEXT NOT NULL,
                    smiles           TEXT,
                    assay_type       TEXT NOT NULL,
                    value_uM         REAL NOT NULL,
                    unit_normalized  TEXT NOT NULL DEFAULT 'uM',
                    operator         TEXT,
                    assay_date       TEXT NOT NULL,
                    operator_note    TEXT,
                    ingested_at      TEXT NOT NULL
                )
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS campaign_compound_ranks (
                    campaign_id     TEXT NOT NULL,
                    compound_id     TEXT NOT NULL,
                    combined_score  REAL NOT NULL,
                    rank            INTEGER NOT NULL,
                    last_updated    TEXT NOT NULL,
                    PRIMARY KEY (campaign_id, compound_id)
                )
            """)
            conn.commit()

    # ------------------------------------------------------------------
    # Ingestion
    # ------------------------------------------------------------------

    def ingest(self, campaign_id: str, csv_path: str) -> dict:
        """Parse, validate, and persist assay rows; recompute ranks.

        Returns a summary dict with keys:
            ingested, errors, updated_ranks, newly_failed, newly_passed
        """
        rows, errors = self._validator.validate(csv_path)
        ingested = 0
        now = datetime.now(timezone.utc).isoformat()

        with sqlite3.connect(self.db_path) as conn:
            for row in rows:
                conn.execute("""
                    INSERT INTO campaign_assay_results
                    (campaign_id, compound_id, smiles, assay_type,
                     value_uM, unit_normalized, operator, assay_date,
                     operator_note, ingested_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    campaign_id,
                    row["compound_id"],
                    row.get("smiles", ""),
                    row["assay_type"],
                    row["value_uM"],
                    row["unit_normalized"],
                    row.get("operator", ""),
                    row["assay_date"],
                    row.get("operator_note", ""),
                    now,
                ))
                ingested += 1
            conn.commit()

        old_ranks = {r["compound_id"]: r["rank"] for r in self.get_ranked_compounds(campaign_id)}
        updated_ranks = self._recompute_ranks(campaign_id)
        new_rank_map = {r["compound_id"]: r for r in updated_ranks}

        newly_failed: list[str] = []
        newly_passed: list[str] = []
        for cid, new_info in new_rank_map.items():
            old_rank = old_ranks.get(cid)
            new_rank = new_info["rank"]
            if old_rank is None:
                continue
            # "newly_failed": previously ranked in top-half, now dropped to bottom-half
            n = len(updated_ranks)
            mid = n // 2
            if old_rank <= mid and new_rank > mid:
                newly_failed.append(cid)
            elif old_rank > mid and new_rank <= mid:
                newly_passed.append(cid)

        return {
            "ingested": ingested,
            "errors": errors,
            "updated_ranks": updated_ranks,
            "newly_failed": newly_failed,
            "newly_passed": newly_passed,
        }

    # ------------------------------------------------------------------
    # Rank computation
    # ------------------------------------------------------------------

    def _recompute_ranks(self, campaign_id: str) -> list[dict]:
        results = self.get_campaign_results(campaign_id)
        if not results:
            return []

        # Group by compound
        by_compound: dict[str, list[dict]] = {}
        for r in results:
            by_compound.setdefault(r["compound_id"], []).append(r)

        # Per-assay-type value ranges for normalisation across all compounds
        assay_values: dict[str, list[float]] = {}
        for rows in by_compound.values():
            for r in rows:
                assay_values.setdefault(r["assay_type"], []).append(r["value_uM"])

        assay_min = {at: min(vs) for at, vs in assay_values.items()}
        assay_max = {at: max(vs) for at, vs in assay_values.items()}

        scores: dict[str, float] = {}
        for cid, rows in by_compound.items():
            component_scores: list[float] = []
            safety_penalty = 0.0

            for r in rows:
                at = r["assay_type"]
                val = r["value_uM"]
                lo = assay_min[at]
                hi = assay_max[at]

                if at in _SAFETY_FLAG_TYPES:
                    # Treat as binary flag: value >= 1 means fail
                    if val >= 1.0:
                        safety_penalty += _SAFETY_PENALTY
                    continue

                if at == "hERG":
                    # hERG IC50: apply a safety penalty if below the cardiac
                    # liability threshold (ICH S7B-informed, 10 µM empirical gate).
                    # Also add a normalised positive score for compounds with
                    # high hERG IC50 (i.e., safe compounds are rewarded).
                    if val < _HERG_SAFETY_THRESHOLD_uM:
                        safety_penalty += _HERG_SAFETY_PENALTY
                    span = hi - lo
                    norm = (val - lo) / span if span > 0 else 0.5  # higher IC50 = higher norm
                    component_scores.append(norm)
                    continue

                span = hi - lo
                if span == 0:
                    norm = 0.5
                else:
                    norm = (val - lo) / span  # 0→min, 1→max

                if at in _LOWER_IS_BETTER:
                    norm = 1.0 - norm  # invert so low value = high score
                # _HIGHER_IS_BETTER types (solubility, permeability) keep norm as-is

                component_scores.append(norm)

            base = mean(component_scores) if component_scores else 0.0
            scores[cid] = max(0.0, base - safety_penalty)

        ranked = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        now = datetime.now(timezone.utc).isoformat()

        with sqlite3.connect(self.db_path) as conn:
            for rank, (cid, score) in enumerate(ranked, start=1):
                conn.execute("""
                    INSERT OR REPLACE INTO campaign_compound_ranks
                    (campaign_id, compound_id, combined_score, rank, last_updated)
                    VALUES (?, ?, ?, ?, ?)
                """, (campaign_id, cid, score, rank, now))
            conn.commit()

        return [
            {"compound_id": cid, "combined_score": score, "rank": rank}
            for rank, (cid, score) in enumerate(ranked, start=1)
        ]

    # ------------------------------------------------------------------
    # Queries
    # ------------------------------------------------------------------

    def get_campaign_results(self, campaign_id: str) -> list[dict]:
        """All assay results for a campaign, ordered by compound_id then assay_date."""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cur = conn.execute("""
                SELECT * FROM campaign_assay_results
                WHERE campaign_id = ?
                ORDER BY compound_id, assay_date
            """, (campaign_id,))
            return [dict(row) for row in cur.fetchall()]

    def get_ranked_compounds(self, campaign_id: str) -> list[dict]:
        """Compounds ranked by combined_score descending, with SMILES if available."""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cur = conn.execute("""
                SELECT r.compound_id, r.combined_score, r.rank,
                       MAX(a.smiles) AS smiles
                FROM campaign_compound_ranks r
                LEFT JOIN campaign_assay_results a
                    ON a.campaign_id = r.campaign_id
                    AND a.compound_id = r.compound_id
                    AND a.smiles != ''
                WHERE r.campaign_id = ?
                GROUP BY r.compound_id, r.combined_score, r.rank
                ORDER BY r.rank
            """, (campaign_id,))
            return [dict(row) for row in cur.fetchall()]
