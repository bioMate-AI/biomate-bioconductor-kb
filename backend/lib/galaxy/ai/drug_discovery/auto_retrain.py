"""
BioMate Auto-Retrain Loop — Phase 3a CRO Automation

Monitors the audit log for new INGEST_ASSAY events and automatically
refits the Bayesian surrogate model + generates a fresh proposal round
without any manual operator action.

Architecture:
  - One daemon thread per active campaign
  - Polls audit log every `check_interval_s` seconds for new INGEST_ASSAY records
  - On new data: reloads campaign compound ranks, refits GP, re-scores cached
    virtual library, saves proposal to auto_proposals table
  - Records the retrain event as a SYSTEM audit record

Virtual library caching:
  - `save_virtual_library()` stores the client's last-used virtual library in the
    campaign DB (virtual_library_cache table, max 1 row per campaign)
  - `_refit_and_propose()` loads this cache automatically

Campaign DB tables added:
  virtual_library_cache  (campaign_id, smiles_json, n_propose, diversity_weight, saved_at)
  auto_proposals         (id, campaign_id, round_number, proposed_smiles_json,
                          scores_json, ci_json, ad_statuses_json, triggered_by,
                          created_at, training_report_json, gp_stds_json,
                          surrogate_report_json)

Round numbers are allocated by BayesianOptimizer.save_proposal from the
bo_proposals ledger; each auto proposal is written in the same transaction as
its bo_proposals row, so both tables always agree on the round.
"""

import json
import logging
import math
import os
import sqlite3
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)

from .assay_ingestion import COVERAGE_COMPLETE, COVERAGE_STATUS_KEY, RANKED_SCORE_KEY

# Surrogate objective name under which that observed score is modelled; this is
# the key of RoundProposal.scores / AutoProposal.scores.
CAMPAIGN_OBJECTIVE = "composite_score"


class CampaignDataError(ValueError):
    """Campaign assay data cannot be turned into a valid training set."""

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

from dataclasses import dataclass, field


@dataclass
class AutoProposal:
    id: int
    campaign_id: str
    round_number: int
    proposed_smiles: list[str]
    scores: dict
    confidence_intervals: dict
    ad_statuses: list[str]
    triggered_by: str          # "auto_retrain" | "manual"
    created_at: str
    # {score_field, objective, n_ranked, n_used, skipped: [{compound_id, reason}], warnings}
    training_report: dict = field(default_factory=dict)
    # {objective: [posterior std per proposed compound]}
    gp_stds: dict = field(default_factory=dict)
    # RoundProposal.surrogate_report; can_discriminate mirrors its flag and is
    # None for rounds persisted before it was recorded.
    surrogate_report: dict = field(default_factory=dict)
    can_discriminate: Optional[bool] = None


@dataclass
class CampaignTrainingRows:
    compound_ids: list[str]
    smiles: list[str]
    labels: list[float]
    skipped: list[dict]
    warnings: list[str]

    def report(self, n_ranked: int) -> dict:
        return {
            "score_field": RANKED_SCORE_KEY,
            "objective": CAMPAIGN_OBJECTIVE,
            "n_ranked": n_ranked,
            "n_used": len(self.labels),
            "skipped": self.skipped,
            "warnings": self.warnings,
        }


def build_training_rows(ranked: list[dict]) -> CampaignTrainingRows:
    """Map ranked campaign compounds to aligned (id, smiles, observed label) rows.

    Rows that are not fully evaluated (their score covers only some campaign
    objectives), or lack a SMILES or a finite observed score, are skipped and
    reported — never given a default or partial label. Rows whose score rests
    on a censored value ('<'/'>' bound; ``censored_objectives``) are skipped
    with reason ``censored_value``: their score is a bound, not a regression
    label. The structure used is the parent (counterions removed) when the
    ranking provides ``parent_smiles``; a multi-component parent (co-drug or
    mixture) has no single structure to featurise and is skipped with reason
    ``multi_component_structure``. Raises CampaignDataError when fewer than
    two usable rows remain (a surrogate cannot be fitted).
    """
    ids: list[str] = []
    smiles: list[str] = []
    labels: list[float] = []
    skipped: list[dict] = []
    for i, r in enumerate(ranked):
        cid = r.get("compound_id") or f"c{i}"
        smi = r.get("smiles")
        coverage = r.get(COVERAGE_STATUS_KEY)
        if coverage != COVERAGE_COMPLETE:
            entry = {"compound_id": cid,
                     "reason": f"{COVERAGE_STATUS_KEY}_{coverage or 'missing'}"}
            if r.get("missing_objectives"):
                entry["missing_objectives"] = list(r["missing_objectives"])
            skipped.append(entry)
            continue
        if r.get("censored_objectives"):
            skipped.append({"compound_id": cid, "reason": "censored_value",
                            "censored_objectives": list(r["censored_objectives"])})
            continue
        smi = r.get("parent_smiles") or smi
        if smi and "." in smi:
            skipped.append({"compound_id": cid, "reason": "multi_component_structure",
                            "parent_smiles": smi})
            continue
        if not smi:
            skipped.append({"compound_id": cid, "reason": "missing_smiles"})
            continue
        if r.get(RANKED_SCORE_KEY) is None:
            skipped.append({"compound_id": cid, "reason": f"missing_{RANKED_SCORE_KEY}"})
            continue
        try:
            value = float(r[RANKED_SCORE_KEY])
        except (TypeError, ValueError):
            skipped.append({"compound_id": cid, "reason": f"non_numeric_{RANKED_SCORE_KEY}"})
            continue
        if not math.isfinite(value):
            skipped.append({"compound_id": cid, "reason": f"non_finite_{RANKED_SCORE_KEY}"})
            continue
        ids.append(cid)
        smiles.append(smi)
        labels.append(value)

    if len(labels) < 2:
        raise CampaignDataError(
            f"need at least 2 fully evaluated compounds with SMILES and a finite {RANKED_SCORE_KEY} "
            f"to fit the surrogate; {len(labels)} usable of {len(ranked)} "
            f"(skipped: {skipped})"
        )
    warnings: list[str] = []
    if skipped:
        warnings.append(f"{len(skipped)} of {len(ranked)} ranked compounds excluded from training")
    if len(set(labels)) == 1:
        warnings.append("constant_labels: all observed scores are identical; "
                        "surrogate predictions carry no ranking information")
    return CampaignTrainingRows(ids, smiles, labels, skipped, warnings)


# ---------------------------------------------------------------------------
# Campaign DB helpers
# ---------------------------------------------------------------------------

def _schema_sql() -> str:
    return """
        CREATE TABLE IF NOT EXISTS virtual_library_cache (
            campaign_id     TEXT PRIMARY KEY,
            smiles_json     TEXT NOT NULL,
            n_propose       INTEGER NOT NULL DEFAULT 10,
            diversity_weight REAL NOT NULL DEFAULT 0.2,
            saved_at        TEXT NOT NULL,
            modality        TEXT NOT NULL DEFAULT 'small_molecule'
        );

        CREATE TABLE IF NOT EXISTS auto_proposals (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            campaign_id      TEXT NOT NULL,
            round_number     INTEGER NOT NULL,
            proposed_smiles_json TEXT NOT NULL,
            scores_json      TEXT NOT NULL,
            ci_json          TEXT NOT NULL DEFAULT '{}',
            ad_statuses_json TEXT NOT NULL DEFAULT '[]',
            triggered_by     TEXT NOT NULL DEFAULT 'auto_retrain',
            created_at       TEXT NOT NULL,
            training_report_json TEXT NOT NULL DEFAULT '{}',
            gp_stds_json     TEXT NOT NULL DEFAULT '{}',
            surrogate_report_json TEXT NOT NULL DEFAULT '{}'
        );

        CREATE INDEX IF NOT EXISTS idx_auto_proposals_campaign
            ON auto_proposals(campaign_id, created_at DESC);
    """


def _init_tables(db_path: str) -> None:
    with sqlite3.connect(db_path) as conn:
        conn.executescript(_schema_sql())
        cols = {r[1] for r in conn.execute("PRAGMA table_info(auto_proposals)")}
        for col in ("training_report_json", "gp_stds_json", "surrogate_report_json"):
            if col not in cols:
                conn.execute(f"ALTER TABLE auto_proposals "
                             f"ADD COLUMN {col} TEXT NOT NULL DEFAULT '{{}}'")
        # Migrate pre-existing virtual_library_cache rows (added modality 2026-11-17).
        vl_cols = {r[1] for r in conn.execute("PRAGMA table_info(virtual_library_cache)")}
        if "modality" not in vl_cols:
            conn.execute("ALTER TABLE virtual_library_cache "
                         "ADD COLUMN modality TEXT NOT NULL DEFAULT 'small_molecule'")


def _connect(db_path: str):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


# ---------------------------------------------------------------------------
# Virtual library cache
# ---------------------------------------------------------------------------

def save_virtual_library(
    db_path: str,
    campaign_id: str,
    smiles_list: list[str],
    n_propose: int = 10,
    diversity_weight: float = 0.2,
    modality: str = "small_molecule",
) -> None:
    """Persist the last-used virtual library for auto-retrain use.

    The modality is stored so the auto-retrain trigger and the background loop
    can rebuild the correct surrogate (Morgan/Tanimoto vs sequence Matern) from
    the campaign DB alone, without the registry.
    """
    _init_tables(db_path)
    ts = datetime.now(timezone.utc).isoformat()
    with _connect(db_path) as conn:
        conn.execute(
            """
            INSERT INTO virtual_library_cache
              (campaign_id, smiles_json, n_propose, diversity_weight, saved_at, modality)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(campaign_id) DO UPDATE SET
              smiles_json = excluded.smiles_json,
              n_propose   = excluded.n_propose,
              diversity_weight = excluded.diversity_weight,
              saved_at    = excluded.saved_at,
              modality    = excluded.modality
            """,
            (campaign_id, json.dumps(smiles_list), n_propose, diversity_weight, ts, modality),
        )


def load_virtual_library(db_path: str, campaign_id: str) -> Optional[dict]:
    """
    Return the cached virtual library dict or None if none saved.

    Returns:
        {smiles_list: [...], n_propose: int, diversity_weight: float, saved_at: str}
    """
    _init_tables(db_path)
    with _connect(db_path) as conn:
        row = conn.execute(
            "SELECT * FROM virtual_library_cache WHERE campaign_id = ?",
            (campaign_id,),
        ).fetchone()
    if row is None:
        return None
    keys = row.keys()
    return {
        "smiles_list": json.loads(row["smiles_json"]),
        "n_propose": row["n_propose"],
        "diversity_weight": row["diversity_weight"],
        "saved_at": row["saved_at"],
        "modality": (row["modality"] if "modality" in keys else "small_molecule"),
    }


# ---------------------------------------------------------------------------
# Auto-proposal persistence
# ---------------------------------------------------------------------------

def _insert_auto_proposal(conn, campaign_id: str, proposal, triggered_by: str,
                          training_report: Optional[dict]) -> AutoProposal:
    ts = datetime.now(timezone.utc).isoformat()
    report = training_report or {}
    gp_stds = getattr(proposal, "gp_stds", None) or {}
    surrogate = getattr(proposal, "surrogate_report", None) or {}
    cur = conn.execute(
        """
        INSERT INTO auto_proposals
          (campaign_id, round_number, proposed_smiles_json, scores_json,
           ci_json, ad_statuses_json, triggered_by, created_at, training_report_json,
           gp_stds_json, surrogate_report_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            campaign_id,
            proposal.round_number,
            json.dumps(proposal.proposed_compounds),
            json.dumps(proposal.scores),
            json.dumps(proposal.confidence_intervals),
            json.dumps(proposal.ad_statuses),
            triggered_by,
            ts,
            json.dumps(report),
            json.dumps(gp_stds),
            json.dumps(surrogate),
        ),
    )
    return AutoProposal(
        id=cur.lastrowid,
        campaign_id=campaign_id,
        round_number=proposal.round_number,
        proposed_smiles=proposal.proposed_compounds,
        scores=proposal.scores,
        confidence_intervals=proposal.confidence_intervals,
        ad_statuses=proposal.ad_statuses,
        triggered_by=triggered_by,
        created_at=ts,
        training_report=report,
        gp_stds=gp_stds,
        surrogate_report=surrogate,
        can_discriminate=surrogate.get("can_discriminate"),
    )


def save_auto_proposal(
    db_path: str,
    campaign_id: str,
    proposal,               # RoundProposal from BayesianOptimizer
    triggered_by: str = "auto_retrain",
    training_report: Optional[dict] = None,
) -> AutoProposal:
    """Write one auto_proposals row with the proposal's existing round number.

    Low-level: does not allocate a round. Campaign rounds must go through
    persist_round(), which allocates the round in the bo_proposals ledger.
    """
    _init_tables(db_path)
    with _connect(db_path) as conn:
        return _insert_auto_proposal(conn, campaign_id, proposal, triggered_by, training_report)


def _backfill_legacy_rounds(conn, campaign_id: str) -> None:
    """Record auto_proposals rounds written before they were mirrored into
    bo_proposals, so the ledger's MAX(round_number) never falls below a round
    already shown to users. Historic rows are not renumbered."""
    conn.execute(
        """
        INSERT INTO bo_proposals
          (campaign_id, round_number, proposed_smiles, scores_json,
           acquisition_values_json, pareto_front_smiles_json, diversity_score, timestamp)
        SELECT a.campaign_id, a.round_number, a.proposed_smiles_json, a.scores_json,
               '[]', '[]', 0.0, MIN(a.created_at)
        FROM auto_proposals a
        WHERE a.campaign_id = ?
          AND NOT EXISTS (SELECT 1 FROM bo_proposals b
                          WHERE b.campaign_id = a.campaign_id
                            AND b.round_number = a.round_number)
        GROUP BY a.campaign_id, a.round_number
        """,
        (campaign_id,),
    )


def persist_round(
    db_path: str,
    optimizer,              # BayesianOptimizer that produced `proposal`
    proposal,               # RoundProposal
    triggered_by: str,
    training_report: Optional[dict] = None,
) -> AutoProposal:
    """Persist a campaign round atomically to bo_proposals and auto_proposals.

    The round number is allocated by the optimizer's ledger inside the same
    write-locked transaction as the auto_proposals insert, so rounds are
    strictly increasing per campaign and identical in both tables.
    """
    _init_tables(db_path)
    conn = sqlite3.connect(db_path, isolation_level=None)
    try:
        conn.execute("BEGIN IMMEDIATE")
        try:
            _backfill_legacy_rounds(conn, proposal.campaign_id)
            optimizer.save_proposal(proposal, conn=conn)
            auto_p = _insert_auto_proposal(conn, proposal.campaign_id, proposal,
                                           triggered_by, training_report)
        except Exception:
            conn.execute("ROLLBACK")
            raise
        conn.execute("COMMIT")
        return auto_p
    finally:
        conn.close()


def _row_to_auto_proposal(r) -> AutoProposal:
    surrogate = json.loads(r["surrogate_report_json"] or "{}")
    return AutoProposal(
        id=r["id"],
        campaign_id=r["campaign_id"],
        round_number=r["round_number"],
        proposed_smiles=json.loads(r["proposed_smiles_json"]),
        scores=json.loads(r["scores_json"]),
        confidence_intervals=json.loads(r["ci_json"]),
        ad_statuses=json.loads(r["ad_statuses_json"]),
        triggered_by=r["triggered_by"],
        created_at=r["created_at"],
        training_report=json.loads(r["training_report_json"] or "{}"),
        gp_stds=json.loads(r["gp_stds_json"] or "{}"),
        surrogate_report=surrogate,
        can_discriminate=surrogate.get("can_discriminate"),
    )


def get_latest_auto_proposal(db_path: str, campaign_id: str) -> Optional[AutoProposal]:
    """Return the most recent auto-proposal for a campaign, or None."""
    _init_tables(db_path)
    with _connect(db_path) as conn:
        row = conn.execute(
            """
            SELECT * FROM auto_proposals
            WHERE campaign_id = ?
            ORDER BY created_at DESC LIMIT 1
            """,
            (campaign_id,),
        ).fetchone()
    if row is None:
        return None
    return _row_to_auto_proposal(row)


def list_auto_proposals(db_path: str, campaign_id: str, limit: int = 20) -> list[AutoProposal]:
    """Return the most recent auto-proposals for a campaign, newest first."""
    _init_tables(db_path)
    with _connect(db_path) as conn:
        rows = conn.execute(
            """
            SELECT * FROM auto_proposals
            WHERE campaign_id = ?
            ORDER BY created_at DESC LIMIT ?
            """,
            (campaign_id, limit),
        ).fetchall()
    return [_row_to_auto_proposal(r) for r in rows]


# ---------------------------------------------------------------------------
# Core refit logic (synchronous — called by background thread or directly)
# ---------------------------------------------------------------------------

def fit_campaign_optimizer(db_path: str, campaign_id: str, rows: CampaignTrainingRows,
                           n_initial: Optional[int] = None, modality: str = "small_molecule"):
    """Fit a BayesianOptimizer on observed campaign labels (CAMPAIGN_OBJECTIVE).

    ``modality`` selects the featuriser + GP: "small_molecule" (SMILES/Morgan/
    Tanimoto, default) or "peptide"/"biologic" (sequence descriptors/Matern)."""
    import numpy as np
    from .bayesian_optimizer import BayesianOptimizer, CampaignDataset

    kwargs = {} if n_initial is None else {"n_initial": n_initial}
    opt = BayesianOptimizer(campaign_id=campaign_id, db_path=db_path, modality=modality, **kwargs)
    dataset = CampaignDataset(
        compound_ids=rows.compound_ids,
        smiles_list=rows.smiles,
        features=opt._featurise(rows.smiles),
        objectives={CAMPAIGN_OBJECTIVE: np.array(rows.labels, dtype=float)},
        objective_directions={CAMPAIGN_OBJECTIVE: "maximize"},
    )
    opt.fit(dataset)
    return opt


def refit_and_propose(
    db_path: str,
    campaign_id: str,
    triggered_by: str = "auto_retrain",
) -> Optional[AutoProposal]:
    """
    Load current campaign data, refit the GP, run a proposal round using
    the cached virtual library, and persist the result.

    Returns the new AutoProposal, or None if prerequisites are not met
    (no assay data, no cached virtual library, or optimizer import fails).

    Raises CampaignDataError when assay data exists but fewer than two ranked
    compounds carry a SMILES and a finite observed score. Compounds skipped
    for that reason are listed in AutoProposal.training_report.
    """
    try:
        from .assay_ingestion import AssayIngestionService
        from .bayesian_optimizer import BayesianOptimizer
    except ImportError as exc:
        log.error("auto_retrain: missing dependency — %s", exc)
        return None

    # Load cached virtual library first — it carries the campaign modality so the
    # surrogate is rebuilt correctly (Morgan/Tanimoto vs sequence Matern) from the
    # campaign DB alone (the background loop has no registry access).
    vl = load_virtual_library(db_path, campaign_id)
    if vl is None:
        log.info("auto_retrain[%s]: no virtual library cached — skipping", campaign_id)
        return None
    modality = vl.get("modality", "small_molecule")

    # Load current compound ranks
    try:
        svc = AssayIngestionService(db_path, modality=modality)
        ranked = svc.get_ranked_compounds(campaign_id)
    except Exception as exc:
        log.error("auto_retrain[%s]: failed to load compounds — %s", campaign_id, exc)
        return None

    if not ranked:
        log.info("auto_retrain[%s]: no assay data yet — skipping", campaign_id)
        return None

    rows = build_training_rows(ranked)
    report = rows.report(len(ranked))
    for w in rows.warnings:
        log.warning("auto_retrain[%s]: %s", campaign_id, w)

    # Refit GP. n_initial matches the usable training-set size so the
    # optimizer can run on any non-trivial dataset (≥2 compounds).
    try:
        opt = fit_campaign_optimizer(db_path, campaign_id, rows,
                                     n_initial=max(2, len(rows.labels)),
                                     modality=modality)
        proposal = opt.propose_next_round(
            virtual_library_smiles=vl["smiles_list"],
            n_propose=vl["n_propose"],
            diversity_weight=vl["diversity_weight"],
        )
    except Exception as exc:
        log.error("auto_retrain[%s]: optimizer failed — %s", campaign_id, exc)
        return None

    # Persist and audit
    auto_p = persist_round(db_path, opt, proposal, triggered_by, report)

    try:
        from ..compliance.audit_store import AuditStore, AuditAction, AuditEvent, hash_payload
        store = AuditStore()
        store.append(AuditEvent(
            user_id="system:auto_retrain",
            action=AuditAction.SYSTEM,
            resource_type="campaign",
            resource_id=campaign_id,
            payload_hash=hash_payload(f"auto_proposal_id={auto_p.id}"),
            details=(
                f"auto_retrain: round={proposal.round_number} "
                f"n_proposed={len(proposal.proposed_compounds)} "
                f"triggered_by={triggered_by}"
            ),
        ))
    except Exception as exc:
        log.warning("auto_retrain[%s]: audit append failed — %s", campaign_id, exc)

    log.info(
        "auto_retrain[%s]: proposal id=%d round=%d n=%d",
        campaign_id, auto_p.id, proposal.round_number, len(proposal.proposed_compounds),
    )
    return auto_p


# ---------------------------------------------------------------------------
# Background loop manager
# ---------------------------------------------------------------------------

_active_loops: dict[str, threading.Thread] = {}
_loop_stop_events: dict[str, threading.Event] = {}


def start_background_loop(
    db_path: str,
    campaign_id: str,
    check_interval_s: float = 60.0,
) -> None:
    """
    Start a daemon thread that periodically checks for new assay data and
    re-runs the optimizer.  Idempotent: a second call for the same campaign
    is a no-op if the loop is already running.
    """
    if campaign_id in _active_loops and _active_loops[campaign_id].is_alive():
        log.debug("auto_retrain[%s]: loop already running", campaign_id)
        return

    stop_event = threading.Event()
    _loop_stop_events[campaign_id] = stop_event

    def _loop():
        log.info("auto_retrain[%s]: background loop started (interval=%ds)", campaign_id, check_interval_s)
        last_audit_id = _get_latest_ingest_audit_id(campaign_id)

        while not stop_event.is_set():
            stop_event.wait(check_interval_s)
            if stop_event.is_set():
                break
            try:
                latest_id = _get_latest_ingest_audit_id(campaign_id)
                if latest_id != last_audit_id:
                    log.info("auto_retrain[%s]: new assay data detected — refitting", campaign_id)
                    refit_and_propose(db_path, campaign_id, triggered_by="auto_retrain")
                    last_audit_id = latest_id
            except Exception as exc:
                log.error("auto_retrain[%s]: loop iteration failed — %s", campaign_id, exc)

        log.info("auto_retrain[%s]: background loop stopped", campaign_id)

    t = threading.Thread(target=_loop, daemon=True, name=f"auto_retrain_{campaign_id}")
    t.start()
    _active_loops[campaign_id] = t


def stop_background_loop(campaign_id: str) -> None:
    """Signal the background loop to stop (non-blocking)."""
    event = _loop_stop_events.get(campaign_id)
    if event:
        event.set()


def is_loop_running(campaign_id: str) -> bool:
    t = _active_loops.get(campaign_id)
    return t is not None and t.is_alive()


def _get_latest_ingest_audit_id(campaign_id: str) -> Optional[int]:
    """Return the id of the most recent INGEST_ASSAY record for this campaign."""
    try:
        from ..compliance.audit_store import AuditStore, AuditAction
        store = AuditStore()
        records = store.get_records(
            action=AuditAction.INGEST_ASSAY,
            resource_id=campaign_id,
            limit=1,
        )
        return records[-1].id if records else None
    except Exception:
        return None
