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
                          created_at)
"""

import json
import logging
import os
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)

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
            saved_at        TEXT NOT NULL
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
            created_at       TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_auto_proposals_campaign
            ON auto_proposals(campaign_id, created_at DESC);
    """


def _init_tables(db_path: str) -> None:
    import sqlite3
    with sqlite3.connect(db_path) as conn:
        conn.executescript(_schema_sql())


def _connect(db_path: str):
    import sqlite3
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
) -> None:
    """Persist the last-used virtual library for auto-retrain use."""
    _init_tables(db_path)
    ts = datetime.now(timezone.utc).isoformat()
    with _connect(db_path) as conn:
        conn.execute(
            """
            INSERT INTO virtual_library_cache
              (campaign_id, smiles_json, n_propose, diversity_weight, saved_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(campaign_id) DO UPDATE SET
              smiles_json = excluded.smiles_json,
              n_propose   = excluded.n_propose,
              diversity_weight = excluded.diversity_weight,
              saved_at    = excluded.saved_at
            """,
            (campaign_id, json.dumps(smiles_list), n_propose, diversity_weight, ts),
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
    return {
        "smiles_list": json.loads(row["smiles_json"]),
        "n_propose": row["n_propose"],
        "diversity_weight": row["diversity_weight"],
        "saved_at": row["saved_at"],
    }


# ---------------------------------------------------------------------------
# Auto-proposal persistence
# ---------------------------------------------------------------------------

def save_auto_proposal(
    db_path: str,
    campaign_id: str,
    proposal,               # RoundProposal from BayesianOptimizer
    triggered_by: str = "auto_retrain",
) -> AutoProposal:
    """Save a BayesianOptimizer proposal to the auto_proposals table."""
    _init_tables(db_path)
    ts = datetime.now(timezone.utc).isoformat()
    with _connect(db_path) as conn:
        cur = conn.execute(
            """
            INSERT INTO auto_proposals
              (campaign_id, round_number, proposed_smiles_json, scores_json,
               ci_json, ad_statuses_json, triggered_by, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
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
            ),
        )
        row_id = cur.lastrowid

    return AutoProposal(
        id=row_id,
        campaign_id=campaign_id,
        round_number=proposal.round_number,
        proposed_smiles=proposal.proposed_compounds,
        scores=proposal.scores,
        confidence_intervals=proposal.confidence_intervals,
        ad_statuses=proposal.ad_statuses,
        triggered_by=triggered_by,
        created_at=ts,
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
    return AutoProposal(
        id=row["id"],
        campaign_id=row["campaign_id"],
        round_number=row["round_number"],
        proposed_smiles=json.loads(row["proposed_smiles_json"]),
        scores=json.loads(row["scores_json"]),
        confidence_intervals=json.loads(row["ci_json"]),
        ad_statuses=json.loads(row["ad_statuses_json"]),
        triggered_by=row["triggered_by"],
        created_at=row["created_at"],
    )


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
    return [
        AutoProposal(
            id=r["id"],
            campaign_id=r["campaign_id"],
            round_number=r["round_number"],
            proposed_smiles=json.loads(r["proposed_smiles_json"]),
            scores=json.loads(r["scores_json"]),
            confidence_intervals=json.loads(r["ci_json"]),
            ad_statuses=json.loads(r["ad_statuses_json"]),
            triggered_by=r["triggered_by"],
            created_at=r["created_at"],
        )
        for r in rows
    ]


# ---------------------------------------------------------------------------
# Core refit logic (synchronous — called by background thread or directly)
# ---------------------------------------------------------------------------

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
    """
    try:
        from .assay_ingestion import AssayIngestionService
        from .bayesian_optimizer import BayesianOptimizer
    except ImportError as exc:
        log.error("auto_retrain: missing dependency — %s", exc)
        return None

    # Load current compound ranks
    try:
        svc = AssayIngestionService(db_path)
        ranked = svc.get_ranked_compounds(campaign_id)
    except Exception as exc:
        log.error("auto_retrain[%s]: failed to load compounds — %s", campaign_id, exc)
        return None

    if not ranked:
        log.info("auto_retrain[%s]: no assay data yet — skipping", campaign_id)
        return None

    # Load cached virtual library
    vl = load_virtual_library(db_path, campaign_id)
    if vl is None:
        log.info("auto_retrain[%s]: no virtual library cached — skipping", campaign_id)
        return None

    # Refit GP
    try:
        import numpy as np
        from .bayesian_optimizer import CampaignDataset

        smiles_list = [r["smiles"] for r in ranked if r.get("smiles")]
        scores_list = [min(1.0, max(0.0, r.get("composite_score", 0.5))) for r in ranked]
        compound_ids = [r.get("compound_id", f"c{i}") for i, r in enumerate(ranked)]

        # n_initial: lower threshold to match actual training set size so the
        # optimizer can run on any non-trivial dataset (≥2 compounds).
        opt = BayesianOptimizer(campaign_id=campaign_id, db_path=db_path,
                                n_initial=max(2, len(smiles_list)))
        features = opt._featurise(smiles_list)
        dataset = CampaignDataset(
            compound_ids=compound_ids,
            smiles_list=smiles_list,
            features=features,
            objectives={"composite_score": np.array(scores_list)},
            objective_directions={"composite_score": "maximize"},
        )
        opt.fit(dataset)
        proposal = opt.propose_next_round(
            virtual_library_smiles=vl["smiles_list"],
            n_propose=vl["n_propose"],
            diversity_weight=vl["diversity_weight"],
        )
    except Exception as exc:
        log.error("auto_retrain[%s]: optimizer failed — %s", campaign_id, exc)
        return None

    # Persist and audit
    auto_p = save_auto_proposal(db_path, campaign_id, proposal, triggered_by)

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
