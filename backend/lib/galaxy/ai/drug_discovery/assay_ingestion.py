"""
Core ingestion logic for BioMate assay data.

Handles CSV parsing, validation, SQLite persistence, and compound ranking.

Ranking contract (get_ranked_compounds / ingest()["updated_ranks"]):
  - Each assay type belongs to an objective (potency, safety, developability;
    other types are their own objective). A campaign's objectives are those
    measured for any of its compounds.
  - Every ranked compound carries ``coverage_status`` ("complete" when it has
    a measurement for every campaign objective, else "incomplete"),
    ``measured_objectives`` and ``missing_objectives``.
  - Complete compounds always rank ahead of incomplete ones; only a complete
    compound can be presented as an overall lead.
  - ``combined_score`` is computed from the compound's measured objectives
    only. For an incomplete compound it is a partial score and is not
    comparable with the scores of complete compounds.
  - ingest() returns ``warnings`` naming every incomplete compound.

Censored values (operator '<' or '>') are bounds, not measurements:
  - Each ranked compound carries ``objectives`` ({objective: {"censored":
    bool, "censored_measurements": [...]}}) and ``censored_objectives``.
  - ``combined_score`` is conservative: a bound on the unfavourable side
    (e.g. IC50 '>10 uM') scores as the worst normalised value (0), since the
    true value may be arbitrarily worse; a bound on the favourable side
    (IC50 '<1 nM') scores at the bound. ``combined_score_upper`` is the
    at-best score, taking every bound at its value. Exact compounds rank
    ahead of censored ones with the same combined_score.
  - Normalisation ranges come from exact measurements only, so a bound never
    stretches the scale of measured compounds.

CSV uploads and LIMS connectors share ingest_rows(); rows with a
``source_record_id`` (e.g. a Benchling result ID) are upserted on
(source_system, source_record_id), so re-polling is idempotent.
"""
import json
import sqlite3
from datetime import datetime, timezone
from statistics import mean
from typing import Iterable, Optional

from .assay_schema import (
    CENSORING_OPERATORS, AssayCSVValidator, SUPPORTED_ASSAY_TYPES, read_assay_csv,
    structure_identity,
    _entity_identity,
)

# Exported ranking contract: the key of each ranked compound's observed score
# (also the campaign_compound_ranks column name) and its coverage fields.
RANKED_SCORE_KEY = "combined_score"
COVERAGE_STATUS_KEY = "coverage_status"
COVERAGE_COMPLETE = "complete"
COVERAGE_INCOMPLETE = "incomplete"

# Assay types where a lower measured value = better therapeutic potency.
_LOWER_IS_BETTER = {"IC50", "Ki", "Kd", "EC50"}

# Assay types where a HIGHER measured value = better.
# hERG IC50: higher IC50 means the drug is less cardiotoxic.
# solubility: higher is better for bioavailability.
# permeability: higher Caco-2/PAMPA is better for absorption.
# pIC50 / percent_inhibition: higher means more potent.
_HIGHER_IS_BETTER = {"hERG", "solubility", "permeability", "pIC50", "percent_inhibition"}

# Objective each assay type provides evidence for; unlisted types are their own objective.
_OBJECTIVE_OF_ASSAY = {
    **{at: "potency" for at in ("IC50", "Ki", "Kd", "EC50", "pIC50", "percent_inhibition")},
    **{at: "safety" for at in ("hERG", "DILI", "Ames", "ClinTox")},
    **{at: "developability" for at in ("solubility", "permeability")},
}


def _objective(assay_type: str) -> str:
    return _OBJECTIVE_OF_ASSAY.get(assay_type, assay_type)


def _lower_is_better(assay_type: str) -> bool:
    return assay_type in _LOWER_IS_BETTER


def _censored_side(assay_type: str, operator: Optional[str]) -> Optional[str]:
    """'favourable' / 'unfavourable' for a censored value, None if exact.

    IC50 '>10' (true value worse than the bound) is unfavourable; IC50 '<0.001'
    (true value at least as good as the bound) is favourable.
    """
    if operator not in CENSORING_OPERATORS:
        return None
    better_below = _lower_is_better(assay_type)
    return "favourable" if (operator == "<") == better_below else "unfavourable"


def _is_censored(row: dict) -> bool:
    return (row.get("operator") or "") in CENSORING_OPERATORS

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
    def __init__(self, db_path: str, modality: str = "small_molecule"):
        self.db_path = db_path
        self.modality = modality
        self._validator = AssayCSVValidator()
        self.ensure_schema()

    # ------------------------------------------------------------------
    # Schema management
    # ------------------------------------------------------------------

    _RESULT_COLUMNS_ADDED = {
        "parent_smiles": "TEXT",
        "structure_flags": "TEXT",
        "source_system": "TEXT",
        "source_record_id": "TEXT",
        "provenance_json": "TEXT",
    }

    def ensure_schema(self):
        """Create SQLite tables if they do not already exist; add new columns."""
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
            cols = {r[1] for r in conn.execute("PRAGMA table_info(campaign_assay_results)")}
            for name, sql_type in self._RESULT_COLUMNS_ADDED.items():
                if name not in cols:
                    conn.execute(f"ALTER TABLE campaign_assay_results ADD COLUMN {name} {sql_type}")
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_assay_results_source_record
                ON campaign_assay_results (campaign_id, source_system, source_record_id)
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
            rank_cols = {r[1] for r in conn.execute("PRAGMA table_info(campaign_compound_ranks)")}
            if "combined_score_upper" not in rank_cols:
                conn.execute("ALTER TABLE campaign_compound_ranks ADD COLUMN combined_score_upper REAL")
            conn.commit()

    # ------------------------------------------------------------------
    # Ingestion
    # ------------------------------------------------------------------

    def ingest(self, campaign_id: str, csv_path: str) -> dict:
        """Parse a CSV file and ingest it through ingest_rows()."""
        raw_rows, read_errors, fatal = read_assay_csv(csv_path)
        if fatal:
            raw_rows = []
        return self.ingest_rows(campaign_id, raw_rows, extra_errors=read_errors)

    def ingest_rows(
        self,
        campaign_id: str,
        raw_rows: "Iterable[dict]",
        extra_errors: "Optional[list[str]]" = None,
    ) -> dict:
        """Validate, persist and rank assay rows (the CSV and LIMS shared path).

        Rows use the CSV column names; values may be strings or numbers.
        Optional ``source_system`` / ``source_record_id`` / ``provenance``
        are stored with the row; a row whose (source_system,
        source_record_id) is already stored replaces it (``updated``), or is
        left alone if unchanged (``unchanged``).

        Returns a summary dict with keys:
            ingested, updated, unchanged, errors, warnings, notes,
            updated_ranks, newly_failed, newly_passed

        Rows whose compound_id conflicts with a parent structure already
        stored for the campaign (or with another row of the batch) are
        rejected in ``errors``.
        """
        raw_rows = list(raw_rows)
        replacing = {(r.get("source_system"), str(r["source_record_id"]))
                     for r in raw_rows if r.get("source_record_id") not in (None, "")}
        known, forms = self._known_structures(campaign_id, exclude_records=replacing)
        validation = self._validator.validate_rows(raw_rows, known_structures=known, known_forms=forms,
                                                   modality=self.modality)
        errors = list(extra_errors or []) + validation.errors
        ingested = updated = unchanged = 0
        now = datetime.now(timezone.utc).isoformat()

        with sqlite3.connect(self.db_path) as conn:
            for row in validation.rows:
                values = (
                    row["compound_id"], row.get("smiles", ""), row["assay_type"],
                    row["value_uM"], row["unit_normalized"], row.get("operator", ""),
                    row["assay_date"], row.get("operator_note", ""),
                    row.get("parent_smiles") or "",
                    json.dumps(row.get("structure_flags") or []),
                    row.get("source_system"),
                    str(row["source_record_id"]) if row.get("source_record_id") not in (None, "") else None,
                    json.dumps(row["provenance"], sort_keys=True) if row.get("provenance") else None,
                )
                existing = None
                if values[11] is not None:
                    existing = conn.execute("""
                        SELECT id, compound_id, smiles, assay_type, value_uM, unit_normalized,
                               operator, assay_date, operator_note, parent_smiles,
                               structure_flags, source_system, source_record_id, provenance_json
                        FROM campaign_assay_results
                        WHERE campaign_id = ? AND source_system IS ? AND source_record_id = ?
                    """, (campaign_id, values[10], values[11])).fetchone()
                if existing is not None:
                    if tuple(existing[1:]) == values:
                        unchanged += 1
                        continue
                    conn.execute("""
                        UPDATE campaign_assay_results SET
                            compound_id = ?, smiles = ?, assay_type = ?, value_uM = ?,
                            unit_normalized = ?, operator = ?, assay_date = ?, operator_note = ?,
                            parent_smiles = ?, structure_flags = ?, source_system = ?,
                            source_record_id = ?, provenance_json = ?, ingested_at = ?
                        WHERE id = ?
                    """, values + (now, existing[0]))
                    updated += 1
                    continue
                conn.execute("""
                    INSERT INTO campaign_assay_results
                    (campaign_id, compound_id, smiles, assay_type,
                     value_uM, unit_normalized, operator, assay_date,
                     operator_note, parent_smiles, structure_flags, source_system,
                     source_record_id, provenance_json, ingested_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (campaign_id,) + values + (now,))
                ingested += 1
            conn.commit()

        summary = self._rerank(campaign_id)
        return {
            "ingested": ingested,
            "updated": updated,
            "unchanged": unchanged,
            "errors": errors,
            "notes": validation.notes,
            **summary,
        }

    def retract_records(self, campaign_id: str, source_system: str, record_ids: "Iterable[str]") -> dict:
        """Delete rows that the source system withdrew (e.g. archived results) and re-rank."""
        ids = [str(i) for i in record_ids]
        removed = 0
        with sqlite3.connect(self.db_path) as conn:
            for rid in ids:
                cur = conn.execute("""
                    DELETE FROM campaign_assay_results
                    WHERE campaign_id = ? AND source_system = ? AND source_record_id = ?
                """, (campaign_id, source_system, rid))
                removed += cur.rowcount
            conn.commit()
        return {"retracted": removed, **self._rerank(campaign_id)}

    def _rerank(self, campaign_id: str) -> dict:
        old_ranks = {r["compound_id"]: r["rank"] for r in self.get_ranked_compounds(campaign_id)}
        updated_ranks = self._recompute_ranks(campaign_id)
        new_rank_map = {r["compound_id"]: r for r in updated_ranks}

        newly_failed: "list[str]" = []
        newly_passed: "list[str]" = []
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

        warnings = [
            f"Compound {r['compound_id']} is incompletely evaluated: missing "
            f"{', '.join(r['missing_objectives'])} (measured: {', '.join(r['measured_objectives'])}). "
            "It is ranked after fully evaluated compounds and its combined_score covers "
            "measured objectives only, so it is not an overall lead candidate."
            for r in updated_ranks if r[COVERAGE_STATUS_KEY] != COVERAGE_COMPLETE
        ]
        warnings += [
            f"Compound {r['compound_id']} has censored values for {', '.join(r['censored_objectives'])} "
            "(reported as a bound with '<' or '>'); its combined_score is a conservative lower bound "
            f"(at-best {r['combined_score_upper']:.3f}) and it is not used as a regression training label."
            for r in updated_ranks if r["censored_objectives"]
        ]
        return {
            "warnings": warnings,
            "updated_ranks": updated_ranks,
            "newly_failed": newly_failed,
            "newly_passed": newly_passed,
        }

    def _known_structures(
        self, campaign_id: str, exclude_records: "Optional[set]" = None,
    ) -> "tuple[dict[str, set[str]], dict[str, set[str]]]":
        """(compound_id → stored parent keys, compound_id → stored as-submitted forms).

        Rows about to be replaced (``exclude_records`` of (source_system,
        source_record_id)) are left out so a corrected LIMS record is checked
        against the rest of the campaign, not against its own old version.
        """
        exclude = exclude_records or set()
        with sqlite3.connect(self.db_path) as conn:
            stored = conn.execute("""
                SELECT compound_id, smiles, source_system, source_record_id
                FROM campaign_assay_results
                WHERE campaign_id = ? AND smiles IS NOT NULL AND smiles != ''
            """, (campaign_id,)).fetchall()
        known: "dict[str, set[str]]" = {}
        forms: "dict[str, set[str]]" = {}
        for cid, smiles, system, record_id in stored:
            if record_id is not None and (system, record_id) in exclude:
                continue
            ident, _ = _entity_identity(smiles, self.modality)
            # An unparseable stored SMILES still identifies the compound by its text.
            known.setdefault(cid, set()).add(ident.parent if ident else smiles.strip())
            forms.setdefault(cid, set()).add(ident.submitted if ident else smiles.strip())
        return known, forms

    @staticmethod
    def _coverage(by_compound: "dict[str, list[dict]]") -> "dict[str, dict]":
        """Per compound: coverage fields plus per-objective censoring."""
        objectives = {_objective(r["assay_type"]) for rows in by_compound.values() for r in rows}
        coverage = {}
        for cid, rows in by_compound.items():
            measured = {_objective(r["assay_type"]) for r in rows}
            missing = sorted(objectives - measured)
            per_objective: "dict[str, dict]" = {}
            for obj in sorted(measured):
                censored = [
                    {"assay_type": r["assay_type"], "operator": r["operator"],
                     "bound": r["value_uM"], "unit": r["unit_normalized"],
                     "side": _censored_side(r["assay_type"], r["operator"])}
                    for r in rows if _objective(r["assay_type"]) == obj and _is_censored(r)
                ]
                per_objective[obj] = {"censored": bool(censored), "censored_measurements": censored}
            coverage[cid] = {
                COVERAGE_STATUS_KEY: COVERAGE_INCOMPLETE if missing else COVERAGE_COMPLETE,
                "measured_objectives": sorted(measured),
                "missing_objectives": missing,
                "objectives": per_objective,
                "censored_objectives": sorted(o for o, v in per_objective.items() if v["censored"]),
            }
        return coverage

    # ------------------------------------------------------------------
    # Rank computation
    # ------------------------------------------------------------------

    @staticmethod
    def _component_bounds(row: dict, lo: Optional[float], hi: Optional[float]) -> "tuple[float, float]":
        """(conservative, at-best) normalised score in [0, 1] for one value; higher = better."""
        at = row["assay_type"]

        def score(v: float) -> float:
            if lo is None or hi is None or hi - lo <= 0:
                return 0.5
            norm = min(1.0, max(0.0, (v - lo) / (hi - lo)))
            return 1.0 - norm if _lower_is_better(at) else norm

        at_bound = score(row["value_uM"])
        side = _censored_side(at, row.get("operator"))
        if side == "unfavourable":
            return 0.0, at_bound
        if side == "favourable":
            return at_bound, 1.0
        return at_bound, at_bound

    @staticmethod
    def _herg_penalties(row: dict) -> "tuple[float, float]":
        """(conservative, at-best) hERG liability penalty for one value."""
        val, op = row["value_uM"], row.get("operator") or ""
        if op == "<":        # true IC50 below the bound: may be anywhere under it
            return _HERG_SAFETY_PENALTY, (_HERG_SAFETY_PENALTY if val <= _HERG_SAFETY_THRESHOLD_uM else 0.0)
        if op == ">":        # true IC50 above the bound
            return (_HERG_SAFETY_PENALTY if val < _HERG_SAFETY_THRESHOLD_uM else 0.0), 0.0
        penalty = _HERG_SAFETY_PENALTY if val < _HERG_SAFETY_THRESHOLD_uM else 0.0
        return penalty, penalty

    def _recompute_ranks(self, campaign_id: str) -> "list[dict]":
        results = self.get_campaign_results(campaign_id)
        if not results:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("DELETE FROM campaign_compound_ranks WHERE campaign_id = ?", (campaign_id,))
                conn.commit()
            return []

        # Group by compound
        by_compound: "dict[str, list[dict]]" = {}
        for r in results:
            by_compound.setdefault(r["compound_id"], []).append(r)

        # Normalisation range per assay type from exact measurements; bounds
        # are only used when an assay type has no exact value at all.
        exact_values: "dict[str, list[float]]" = {}
        all_values: "dict[str, list[float]]" = {}
        for r in results:
            all_values.setdefault(r["assay_type"], []).append(r["value_uM"])
            if not _is_censored(r):
                exact_values.setdefault(r["assay_type"], []).append(r["value_uM"])
        ranges = {at: (min(exact_values.get(at) or vs), max(exact_values.get(at) or vs))
                  for at, vs in all_values.items()}

        scores: "dict[str, tuple[float, float]]" = {}
        for cid, rows in by_compound.items():
            lower_parts: "list[float]" = []
            upper_parts: "list[float]" = []
            penalty_lower = penalty_upper = 0.0

            for r in rows:
                at = r["assay_type"]
                if at in _SAFETY_FLAG_TYPES:
                    # Binary flag (validator rejects '<'/'>' here): value >= 1 means fail
                    if r["value_uM"] >= 1.0:
                        penalty_lower += _SAFETY_PENALTY
                        penalty_upper += _SAFETY_PENALTY
                    continue
                if at == "hERG":
                    # hERG IC50: safety penalty below the cardiac liability threshold
                    # (ICH S7B-informed, 10 µM empirical gate), plus a normalised
                    # positive score for high hERG IC50 (safe compounds are rewarded).
                    p_lo, p_up = self._herg_penalties(r)
                    penalty_lower += p_lo
                    penalty_upper += p_up
                lo, hi = ranges[at]
                c_lo, c_up = self._component_bounds(r, lo, hi)
                lower_parts.append(c_lo)
                upper_parts.append(c_up)

            lower = max(0.0, (mean(lower_parts) if lower_parts else 0.0) - penalty_lower)
            upper = max(0.0, (mean(upper_parts) if upper_parts else 0.0) - penalty_upper)
            scores[cid] = (lower, upper)

        coverage = self._coverage(by_compound)
        n_censored = {cid: sum(1 for r in rows if _is_censored(r)) for cid, rows in by_compound.items()}
        ranked = sorted(
            scores.items(),
            key=lambda x: (coverage[x[0]][COVERAGE_STATUS_KEY] != COVERAGE_COMPLETE,
                           -x[1][0], n_censored[x[0]], x[0]),
        )
        now = datetime.now(timezone.utc).isoformat()

        with sqlite3.connect(self.db_path) as conn:
            # Replace the whole ranking so compounds whose rows were retracted drop out.
            conn.execute("DELETE FROM campaign_compound_ranks WHERE campaign_id = ?", (campaign_id,))
            for rank, (cid, (score, upper)) in enumerate(ranked, start=1):
                conn.execute("""
                    INSERT OR REPLACE INTO campaign_compound_ranks
                    (campaign_id, compound_id, combined_score, combined_score_upper, rank, last_updated)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (campaign_id, cid, score, upper, rank, now))
            conn.commit()

        return [
            {"compound_id": cid, RANKED_SCORE_KEY: score, "combined_score_upper": upper,
             "rank": rank, **coverage[cid]}
            for rank, (cid, (score, upper)) in enumerate(ranked, start=1)
        ]

    # ------------------------------------------------------------------
    # Queries
    # ------------------------------------------------------------------

    def get_campaign_results(self, campaign_id: str) -> "list[dict]":
        """All assay results for a campaign, ordered by compound_id then assay_date."""
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cur = conn.execute("""
                SELECT * FROM campaign_assay_results
                WHERE campaign_id = ?
                ORDER BY compound_id, assay_date, id
            """, (campaign_id,))
            rows = [dict(row) for row in cur.fetchall()]
        for r in rows:
            r["censored"] = _is_censored(r)
        return rows

    def get_ranked_compounds(self, campaign_id: str) -> "list[dict]":
        """Ranked compounds with SMILES, parent SMILES, coverage and censoring
        (see the module ranking contract)."""
        by_compound: "dict[str, list[dict]]" = {}
        for r in self.get_campaign_results(campaign_id):
            by_compound.setdefault(r["compound_id"], []).append(r)
        coverage = self._coverage(by_compound)
        unmeasured = {COVERAGE_STATUS_KEY: COVERAGE_INCOMPLETE, "measured_objectives": [],
                      "missing_objectives": sorted({o for c in coverage.values()
                                                    for o in c["measured_objectives"]}),
                      "objectives": {}, "censored_objectives": []}
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            cur = conn.execute("""
                SELECT r.compound_id, r.combined_score, r.combined_score_upper, r.rank,
                       MAX(a.smiles) AS smiles, MAX(a.parent_smiles) AS parent_smiles,
                       MAX(a.structure_flags) AS structure_flags
                FROM campaign_compound_ranks r
                LEFT JOIN campaign_assay_results a
                    ON a.campaign_id = r.campaign_id
                    AND a.compound_id = r.compound_id
                    AND a.smiles != ''
                WHERE r.campaign_id = ?
                GROUP BY r.compound_id, r.combined_score, r.combined_score_upper, r.rank
                ORDER BY r.rank
            """, (campaign_id,))
            ranked = []
            for row in cur.fetchall():
                entry = {**dict(row), **coverage.get(row["compound_id"], unmeasured)}
                if not entry.get("parent_smiles") and entry.get("smiles"):
                    # Rows stored before parent_smiles existed.
                    ident, _ = _entity_identity(entry["smiles"], self.modality)
                    entry["parent_smiles"] = ident.parent if ident else None
                    entry["structure_flags"] = list(ident.flags) if ident else []
                else:
                    entry["structure_flags"] = json.loads(entry["structure_flags"] or "[]")
                if entry.get("combined_score_upper") is None:
                    entry["combined_score_upper"] = entry["combined_score"]
                ranked.append(entry)
            return ranked
