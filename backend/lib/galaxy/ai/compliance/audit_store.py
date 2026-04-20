"""
BioMate Tamper-Evident Audit Store — Phase 2 CRO Compliance

21 CFR Part 11 §11.10(e) requires computer-generated, date/time-stamped audit
trails for all operations that create, modify, or delete electronic records.

Design:
  - Single global SQLite database (WAL mode) in database/compliance/audit.db
  - SHA-256 hash chaining: record_hash = SHA256(fields + previous_hash)
  - No UPDATE or DELETE methods; records are immutable once written
  - verify_chain() re-derives every hash and flags any tampered record
  - Per-record payload_hash allows detection of out-of-band DB modification

References:
  21 CFR Part 11 §11.10(a) — validation of systems
  21 CFR Part 11 §11.10(e) — audit trails
  FDA Guidance: 21 CFR Part 11; Electronic Records; Electronic Signatures (2003)
"""

import hashlib
import logging
import os
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_GENESIS_HASH = "0" * 64  # Sentinel for the first record (no predecessor)

# Actions recorded in the audit log.
# Using uppercase string constants so they appear verbatim in the DB.
class AuditAction:
    INGEST_ASSAY          = "INGEST_ASSAY"
    PROPOSE_ROUND         = "PROPOSE_ROUND"
    EXPORT_CRO_ORDER      = "EXPORT_CRO_ORDER"
    REGISTER_MODEL        = "REGISTER_MODEL"
    RUN_MODEL             = "RUN_MODEL"
    POLL_LIMS             = "POLL_LIMS"
    ESIG                  = "ESIG"
    MODEL_VALIDATION      = "MODEL_VALIDATION"
    CAMPAIGN_CREATE       = "CAMPAIGN_CREATE"
    SYSTEM                = "SYSTEM"          # internal / automated actions


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass
class AuditEvent:
    """Input to AuditStore.append()."""
    user_id: str
    action: str                   # one of AuditAction.*
    resource_type: str            # e.g. "campaign", "proposal", "model"
    resource_id: str              # e.g. campaign_id
    payload_hash: str             # SHA-256 of the request body / relevant data
    details: str = ""             # free-text (searchable; not part of the hash chain)


@dataclass
class AuditRecord:
    """A single immutable record as stored in the DB."""
    id: int
    timestamp_utc: str
    user_id: str
    action: str
    resource_type: str
    resource_id: str
    payload_hash: str
    details: str
    previous_hash: str
    record_hash: str


@dataclass
class ChainVerificationResult:
    valid: bool
    total_records: int
    first_tampered_id: Optional[int]   # None if valid
    error: Optional[str]               # human-readable diagnosis


# ---------------------------------------------------------------------------
# Hash helpers
# ---------------------------------------------------------------------------

def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _derive_record_hash(
    timestamp_utc: str,
    user_id: str,
    action: str,
    resource_type: str,
    resource_id: str,
    payload_hash: str,
    previous_hash: str,
) -> str:
    """
    Deterministically derive a record's hash from its content fields.
    The details field is intentionally excluded so it can be updated for
    human-readable annotations without breaking the chain.
    """
    canonical = "|".join([
        timestamp_utc,
        user_id,
        action,
        resource_type,
        resource_id,
        payload_hash,
        previous_hash,
    ])
    return _sha256(canonical)


def hash_payload(data: str | bytes) -> str:
    """Convenience function for callers to hash a request body / data blob."""
    if isinstance(data, str):
        data = data.encode("utf-8")
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------------------
# Audit Store
# ---------------------------------------------------------------------------

class AuditStore:
    """
    Append-only, hash-chained audit log.

    Usage:
        store = AuditStore()   # uses default path
        store.append(AuditEvent(
            user_id="alice",
            action=AuditAction.INGEST_ASSAY,
            resource_type="campaign",
            resource_id="cmp-001",
            payload_hash=hash_payload(csv_bytes),
        ))
        result = store.verify_chain()
        assert result.valid
    """

    _DEFAULT_DB_DIR = os.environ.get(
        "BIOMATE_COMPLIANCE_DB_DIR",
        str(Path(__file__).parent.parent.parent.parent.parent
            / "database" / "compliance"),
    )

    def __init__(self, db_path: Optional[str] = None):
        if db_path is None:
            Path(self._DEFAULT_DB_DIR).mkdir(parents=True, exist_ok=True)
            db_path = str(Path(self._DEFAULT_DB_DIR) / "audit.db")
        self._db_path = db_path
        self._init_db()

    # ------------------------------------------------------------------
    # Initialisation
    # ------------------------------------------------------------------

    def _init_db(self) -> None:
        with self._connect() as conn:
            conn.executescript("""
                PRAGMA journal_mode = WAL;
                PRAGMA synchronous = FULL;
                PRAGMA foreign_keys = ON;

                CREATE TABLE IF NOT EXISTS audit_log (
                    id             INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp_utc  TEXT    NOT NULL,
                    user_id        TEXT    NOT NULL,
                    action         TEXT    NOT NULL,
                    resource_type  TEXT    NOT NULL DEFAULT '',
                    resource_id    TEXT    NOT NULL DEFAULT '',
                    payload_hash   TEXT    NOT NULL,
                    details        TEXT    NOT NULL DEFAULT '',
                    previous_hash  TEXT    NOT NULL,
                    record_hash    TEXT    NOT NULL UNIQUE
                );

                -- Fast look-ups for compliance queries
                CREATE INDEX IF NOT EXISTS idx_audit_user     ON audit_log(user_id);
                CREATE INDEX IF NOT EXISTS idx_audit_action   ON audit_log(action);
                CREATE INDEX IF NOT EXISTS idx_audit_resource ON audit_log(resource_id);
                CREATE INDEX IF NOT EXISTS idx_audit_ts       ON audit_log(timestamp_utc);
            """)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self._db_path)
        conn.row_factory = sqlite3.Row
        return conn

    # ------------------------------------------------------------------
    # Write (append-only)
    # ------------------------------------------------------------------

    def append(self, event: AuditEvent) -> AuditRecord:
        """
        Append a new audit record to the chain.  Thread-safe via SQLite WAL.
        """
        timestamp_utc = datetime.now(timezone.utc).isoformat()
        previous_hash = self._get_latest_hash()
        record_hash = _derive_record_hash(
            timestamp_utc,
            event.user_id,
            event.action,
            event.resource_type,
            event.resource_id,
            event.payload_hash,
            previous_hash,
        )
        with self._connect() as conn:
            cur = conn.execute(
                """
                INSERT INTO audit_log
                  (timestamp_utc, user_id, action, resource_type, resource_id,
                   payload_hash, details, previous_hash, record_hash)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    timestamp_utc,
                    event.user_id,
                    event.action,
                    event.resource_type,
                    event.resource_id,
                    event.payload_hash,
                    event.details,
                    previous_hash,
                    record_hash,
                ),
            )
            record_id = cur.lastrowid

        return AuditRecord(
            id=record_id,
            timestamp_utc=timestamp_utc,
            user_id=event.user_id,
            action=event.action,
            resource_type=event.resource_type,
            resource_id=event.resource_id,
            payload_hash=event.payload_hash,
            details=event.details,
            previous_hash=previous_hash,
            record_hash=record_hash,
        )

    # ------------------------------------------------------------------
    # Read
    # ------------------------------------------------------------------

    def _get_latest_hash(self) -> str:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT record_hash FROM audit_log ORDER BY id DESC LIMIT 1"
            ).fetchone()
        return row["record_hash"] if row else _GENESIS_HASH

    def get_records(
        self,
        *,
        since_utc: Optional[str] = None,
        user_id: Optional[str] = None,
        action: Optional[str] = None,
        resource_id: Optional[str] = None,
        limit: int = 200,
    ) -> list[AuditRecord]:
        """Return records matching the given filters, oldest-first."""
        clauses, params = [], []
        if since_utc:
            clauses.append("timestamp_utc >= ?")
            params.append(since_utc)
        if user_id:
            clauses.append("user_id = ?")
            params.append(user_id)
        if action:
            clauses.append("action = ?")
            params.append(action)
        if resource_id:
            clauses.append("resource_id = ?")
            params.append(resource_id)

        where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
        params.append(limit)

        with self._connect() as conn:
            rows = conn.execute(
                f"SELECT * FROM audit_log {where} ORDER BY id ASC LIMIT ?",
                params,
            ).fetchall()

        return [_row_to_record(r) for r in rows]

    def count(self) -> int:
        with self._connect() as conn:
            return conn.execute("SELECT COUNT(*) FROM audit_log").fetchone()[0]

    # ------------------------------------------------------------------
    # Chain verification (tamper detection)
    # ------------------------------------------------------------------

    def verify_chain(self) -> ChainVerificationResult:
        """
        Walk the entire audit log and re-derive every record_hash.

        Detects:
          - Modified field values (hash mismatch)
          - Deleted records (gap in previous_hash chain)
          - Inserted records (previous_hash references unknown predecessor)
        """
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM audit_log ORDER BY id ASC"
            ).fetchall()

        records = [_row_to_record(r) for r in rows]
        total = len(records)

        if total == 0:
            return ChainVerificationResult(
                valid=True, total_records=0,
                first_tampered_id=None, error=None,
            )

        expected_previous = _GENESIS_HASH

        for rec in records:
            # 1 — check the previous_hash link
            if rec.previous_hash != expected_previous:
                return ChainVerificationResult(
                    valid=False,
                    total_records=total,
                    first_tampered_id=rec.id,
                    error=(
                        f"Record id={rec.id}: previous_hash mismatch. "
                        f"Expected {expected_previous[:16]}… "
                        f"got {rec.previous_hash[:16]}…"
                    ),
                )

            # 2 — re-derive and compare record_hash
            expected_hash = _derive_record_hash(
                rec.timestamp_utc,
                rec.user_id,
                rec.action,
                rec.resource_type,
                rec.resource_id,
                rec.payload_hash,
                rec.previous_hash,
            )
            if rec.record_hash != expected_hash:
                return ChainVerificationResult(
                    valid=False,
                    total_records=total,
                    first_tampered_id=rec.id,
                    error=(
                        f"Record id={rec.id}: record_hash mismatch — "
                        f"content has been modified"
                    ),
                )

            expected_previous = rec.record_hash

        return ChainVerificationResult(
            valid=True, total_records=total,
            first_tampered_id=None, error=None,
        )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _row_to_record(row: sqlite3.Row) -> AuditRecord:
    return AuditRecord(
        id=row["id"],
        timestamp_utc=row["timestamp_utc"],
        user_id=row["user_id"],
        action=row["action"],
        resource_type=row["resource_type"],
        resource_id=row["resource_id"],
        payload_hash=row["payload_hash"],
        details=row["details"],
        previous_hash=row["previous_hash"],
        record_hash=row["record_hash"],
    )
