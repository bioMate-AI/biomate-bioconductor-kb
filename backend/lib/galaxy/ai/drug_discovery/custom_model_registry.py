"""
Per-campaign registry for custom scoring models, with immutable versions.

Every registration of a (campaign_id, model_name) creates version N+1 in
``custom_model_versions`` (campaign SQLite DB). Versions are never updated in
place except for their promotion status:

  pending   — reserved for a training run that has not finished
  candidate — trained/registered, awaiting an explicit promotion decision
  active    — the version served by run_named_model / run_all (at most one
              per (campaign_id, model_name), enforced by a partial unique index)
  rejected  — QC gate failed, training failed, or a reviewer rejected it
  retired   — was active, superseded by a promotion or rollback

Platform-trained models (kind ``ml_artifact``) record the artifact directory,
its SHA-256 tree hash, the training-dataset hash, split method, metrics and QC
gate result. Loading an ml_artifact version re-hashes the directory and refuses
to serve on mismatch. Promotion of an ml_artifact version requires a passed
gate and a named reviewer. External scorers (REST/Docker) carry no QC gate
(gate status ``not_applicable``) and are activated by their registering actor.

``custom_model_registrations`` remains as one summary row per model name
(read by the Models catalog); ``active_version`` points at the served version.
"""
import hashlib
import json
import math
import sqlite3
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Optional

from .custom_model_wrapper import (
    BaseModelWrapper, DockerModelWrapper, ModelRunRecord, RESTModelWrapper,
)

STATUSES = ("pending", "candidate", "active", "rejected", "retired")
KIND_ML_ARTIFACT = "ml_artifact"
KIND_REST = "rest"
KIND_DOCKER = "docker"
KIND_PYTHON = "python"
GATE_NOT_APPLICABLE = "not_applicable"


class ModelRegistryError(ValueError):
    """Invalid registry operation (unknown version, illegal transition, ...)."""


class PromotionBlocked(ModelRegistryError):
    """A version may not be promoted (gate not passed, wrong status, no reviewer)."""


class ArtifactIntegrityError(RuntimeError):
    """The artifact on disk does not match the hash recorded at registration."""


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def artifact_sha256(artifact_dir: str) -> str:
    """Deterministic SHA-256 over every file (relative path + content) in a directory."""
    root = Path(artifact_dir)
    if not root.is_dir():
        raise FileNotFoundError(f"artifact directory not found: {artifact_dir}")
    digest = hashlib.sha256()
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        file_hash = hashlib.sha256()
        with path.open("rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                file_hash.update(chunk)
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(b"\0" + file_hash.hexdigest().encode() + b"\n")
    return digest.hexdigest()


def dataset_sha256(rows: list) -> str:
    """SHA-256 of ordered (smiles, label) rows."""
    payload = json.dumps([[str(s), float(y)] for s, y in rows], separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()


def canonical_smiles(smiles: str) -> str:
    try:
        from rdkit import Chem
        mol = Chem.MolFromSmiles(smiles)
        if mol is not None:
            return Chem.MolToSmiles(mol)
    except ImportError:
        pass
    return smiles.strip()


@dataclass
class ModelVersion:
    campaign_id: str
    model_name: str
    version: int
    status: str
    kind: str
    mode: str
    weight: float
    higher_is_better: bool
    task_type: Optional[str]
    artifact_dir: Optional[str]
    artifact_sha256: Optional[str]
    dataset_sha256: Optional[str]
    split: dict
    metrics: dict
    gate: dict
    spec: dict
    parent_version: Optional[int]
    created_at: str
    created_by: Optional[str]
    status_changed_at: Optional[str]
    status_changed_by: Optional[str]
    status_note: Optional[str]
    n_training_molecules: int = 0
    events: list = field(default_factory=list)

    def to_dict(self) -> dict:
        d = dict(self.__dict__)
        d["metrics"] = {k: (v if isinstance(v, (int, float)) and math.isfinite(v) else None)
                        for k, v in self.metrics.items()}
        return d


class CustomModelRegistry:
    def __init__(self, db_path: str):
        self.db_path = db_path
        # In-process wrappers keyed by (campaign_id, model_name, version). Only
        # python-function wrappers depend on this cache; every other kind is
        # rebuilt from its persisted record.
        self._models: dict[tuple[str, str, int], BaseModelWrapper] = {}
        self._lock = threading.Lock()
        self._ensure_schema()

    # ------------------------------------------------------------------ schema
    def _connect(self, write: bool = False) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, isolation_level=None, timeout=30)
        conn.row_factory = sqlite3.Row
        if write:
            conn.execute("BEGIN IMMEDIATE")
        return conn

    def _ensure_schema(self):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS custom_model_registrations (
                    id                INTEGER PRIMARY KEY AUTOINCREMENT,
                    campaign_id       TEXT NOT NULL,
                    model_name        TEXT NOT NULL,
                    mode              TEXT NOT NULL,
                    weight            REAL DEFAULT 1.0,
                    higher_is_better  INTEGER DEFAULT 1,
                    enabled           INTEGER DEFAULT 1,
                    config_json       TEXT,
                    registered_at     TEXT,
                    UNIQUE(campaign_id, model_name)
                )
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS custom_model_run_log (
                    id            INTEGER PRIMARY KEY AUTOINCREMENT,
                    campaign_id   TEXT NOT NULL,
                    model_name    TEXT NOT NULL,
                    mode          TEXT NOT NULL,
                    input_count   INTEGER,
                    output_count  INTEGER,
                    run_at        TEXT,
                    duration_s    REAL,
                    success       INTEGER,
                    error         TEXT
                )
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS custom_model_versions (
                    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
                    campaign_id        TEXT NOT NULL,
                    model_name         TEXT NOT NULL,
                    version            INTEGER NOT NULL,
                    status             TEXT NOT NULL,
                    kind               TEXT NOT NULL,
                    mode               TEXT NOT NULL,
                    weight             REAL NOT NULL DEFAULT 1.0,
                    higher_is_better   INTEGER NOT NULL DEFAULT 1,
                    task_type          TEXT,
                    artifact_dir       TEXT,
                    artifact_sha256    TEXT,
                    dataset_sha256     TEXT,
                    split_json         TEXT NOT NULL DEFAULT '{}',
                    metrics_json       TEXT NOT NULL DEFAULT '{}',
                    gate_json          TEXT NOT NULL DEFAULT '{}',
                    spec_json          TEXT NOT NULL DEFAULT '{}',
                    training_smiles_json TEXT NOT NULL DEFAULT '[]',
                    parent_version     INTEGER,
                    created_at         TEXT NOT NULL,
                    created_by         TEXT,
                    status_changed_at  TEXT,
                    status_changed_by  TEXT,
                    status_note        TEXT,
                    UNIQUE(campaign_id, model_name, version)
                )
            """)
            conn.execute("""
                CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_model_version
                    ON custom_model_versions(campaign_id, model_name)
                    WHERE status = 'active'
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS custom_model_version_events (
                    id           INTEGER PRIMARY KEY AUTOINCREMENT,
                    campaign_id  TEXT NOT NULL,
                    model_name   TEXT NOT NULL,
                    version      INTEGER NOT NULL,
                    from_status  TEXT,
                    to_status    TEXT NOT NULL,
                    actor        TEXT,
                    note         TEXT,
                    at           TEXT NOT NULL
                )
            """)
            conn.execute("""
                CREATE TABLE IF NOT EXISTS custom_model_comparisons (
                    id              INTEGER PRIMARY KEY AUTOINCREMENT,
                    campaign_id     TEXT NOT NULL,
                    model_name      TEXT NOT NULL,
                    version_a       INTEGER NOT NULL,
                    version_b       INTEGER NOT NULL,
                    holdout_sha256  TEXT NOT NULL,
                    n_holdout       INTEGER NOT NULL,
                    task_type       TEXT NOT NULL,
                    metrics_a_json  TEXT NOT NULL,
                    metrics_b_json  TEXT NOT NULL,
                    overlap_json    TEXT NOT NULL,
                    created_at      TEXT NOT NULL,
                    created_by      TEXT
                )
            """)
            for table, column, ddl in (
                ("custom_model_registrations", "active_version", "INTEGER"),
                ("custom_model_run_log", "model_version", "INTEGER"),
            ):
                cols = {r[1] for r in conn.execute(f"PRAGMA table_info({table})")}
                if column not in cols:
                    conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {ddl}")
            conn.commit()

    # --------------------------------------------------------------- versions
    @staticmethod
    def _next_version(conn, campaign_id: str, model_name: str) -> int:
        row = conn.execute(
            "SELECT COALESCE(MAX(version), 0) FROM custom_model_versions "
            "WHERE campaign_id = ? AND model_name = ?", (campaign_id, model_name)).fetchone()
        return int(row[0]) + 1

    @staticmethod
    def _active_version(conn, campaign_id: str, model_name: str) -> Optional[int]:
        row = conn.execute(
            "SELECT version FROM custom_model_versions WHERE campaign_id = ? "
            "AND model_name = ? AND status = 'active'", (campaign_id, model_name)).fetchone()
        return int(row[0]) if row else None

    @staticmethod
    def _event(conn, campaign_id, model_name, version, from_status, to_status, actor, note):
        conn.execute(
            "INSERT INTO custom_model_version_events (campaign_id, model_name, version, "
            "from_status, to_status, actor, note, at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (campaign_id, model_name, version, from_status, to_status, actor, note, _now()))

    def _insert_version(self, conn, *, campaign_id: str, model_name: str, status: str,
                        kind: str, mode: str, weight: float, higher_is_better: bool,
                        actor: Optional[str], note: Optional[str], task_type=None,
                        artifact_dir=None, artifact_hash=None, dataset_hash=None,
                        split=None, metrics=None, gate=None, spec=None,
                        training_smiles=None) -> int:
        version = self._next_version(conn, campaign_id, model_name)
        parent = self._active_version(conn, campaign_id, model_name)
        if parent is None:
            row = conn.execute(
                "SELECT MAX(version) FROM custom_model_versions WHERE campaign_id = ? "
                "AND model_name = ?", (campaign_id, model_name)).fetchone()
            parent = row[0]
        ts = _now()
        conn.execute("""
            INSERT INTO custom_model_versions
            (campaign_id, model_name, version, status, kind, mode, weight, higher_is_better,
             task_type, artifact_dir, artifact_sha256, dataset_sha256, split_json, metrics_json,
             gate_json, spec_json, training_smiles_json, parent_version, created_at, created_by,
             status_changed_at, status_changed_by, status_note)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (campaign_id, model_name, version, status, kind, mode, float(weight),
              int(higher_is_better), task_type, artifact_dir, artifact_hash, dataset_hash,
              json.dumps(split or {}), json.dumps(_finite_metrics(metrics or {})),
              json.dumps(gate or {}), json.dumps(spec or {}),
              json.dumps(sorted(set(training_smiles or []))), parent, ts, actor,
              ts, actor, note))
        self._event(conn, campaign_id, model_name, version, None, status, actor, note)
        return version

    def _set_status(self, conn, mv: "ModelVersion", to_status: str, actor, note) -> None:
        conn.execute(
            "UPDATE custom_model_versions SET status = ?, status_changed_at = ?, "
            "status_changed_by = ?, status_note = ? WHERE campaign_id = ? AND model_name = ? "
            "AND version = ?",
            (to_status, _now(), actor, note, mv.campaign_id, mv.model_name, mv.version))
        self._event(conn, mv.campaign_id, mv.model_name, mv.version, mv.status, to_status,
                    actor, note)

    def _sync_summary(self, conn, campaign_id: str, model_name: str) -> None:
        """Keep the per-name summary row (Models catalog) pointing at the active version."""
        active = self._active_version(conn, campaign_id, model_name)
        version = active or self._next_version(conn, campaign_id, model_name) - 1
        mv = self._get(conn, campaign_id, model_name, version)
        prior = conn.execute(
            "SELECT enabled FROM custom_model_registrations WHERE campaign_id = ? "
            "AND model_name = ?", (campaign_id, model_name)).fetchone()
        enabled = 1 if prior is None else int(prior[0])
        conn.execute("""
            INSERT INTO custom_model_registrations
              (campaign_id, model_name, mode, weight, higher_is_better, enabled, config_json,
               registered_at, active_version)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(campaign_id, model_name) DO UPDATE SET
              mode = excluded.mode, weight = excluded.weight,
              higher_is_better = excluded.higher_is_better,
              config_json = excluded.config_json, registered_at = excluded.registered_at,
              active_version = excluded.active_version
        """, (campaign_id, model_name, mv.mode, mv.weight, int(mv.higher_is_better), enabled,
              json.dumps({"kind": mv.kind, "latest_version": mv.version}), mv.created_at,
              active))

    def _get(self, conn, campaign_id: str, model_name: str, version: int) -> "ModelVersion":
        row = conn.execute(
            "SELECT * FROM custom_model_versions WHERE campaign_id = ? AND model_name = ? "
            "AND version = ?", (campaign_id, model_name, version)).fetchone()
        if row is None:
            raise ModelRegistryError(f"{campaign_id}/{model_name} has no version {version}")
        return _row_to_version(row)

    # ---------------------------------------------------- registration paths
    def register(self, wrapper: BaseModelWrapper, config: dict = None) -> ModelVersion:
        """Register an external scorer (REST / Docker / python function) as a new
        version and activate it. External scorers have no QC gate; the
        registering actor (config['registered_by']) is recorded as promoter.

        Platform-trained artifacts must use register_trained_version()."""
        from ..ml_training.chemprop_wrapper import ChempropModelWrapper
        if isinstance(wrapper, ChempropModelWrapper):
            raise ModelRegistryError(
                "trained model artifacts must be registered with register_trained_version() "
                "so their hash, dataset and QC gate are recorded")
        config = dict(config or {})
        actor = config.pop("registered_by", None) or "register"
        kind, spec = _external_spec(wrapper)
        conn = self._connect(write=True)
        try:
            version = self._insert_version(
                conn, campaign_id=wrapper.campaign_id, model_name=wrapper.name,
                status="candidate", kind=kind, mode=wrapper._mode(), weight=wrapper.weight,
                higher_is_better=wrapper.higher_is_better, actor=actor,
                note="external scorer registered", gate={"status": GATE_NOT_APPLICABLE},
                spec={**spec, "config": config})
            mv = self._get(conn, wrapper.campaign_id, wrapper.name, version)
            self._promote_in_txn(conn, mv, actor, "external scorer activated on registration")
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()
        with self._lock:
            self._models[(wrapper.campaign_id, wrapper.name, version)] = wrapper
        return self.get_version(wrapper.campaign_id, wrapper.name, version)

    def reserve_version(self, campaign_id: str, model_name: str, artifact_root: str,
                        actor: Optional[str] = None) -> tuple[int, str]:
        """Reserve the next version for a training run; returns (version, artifact_dir).

        The artifact directory is keyed by version and must not exist yet, so a
        reserved version can never overwrite a previous version's artifact."""
        conn = self._connect(write=True)
        try:
            version = self._next_version(conn, campaign_id, model_name)
            slug = _slug(model_name)
            artifact_dir = Path(artifact_root) / _slug(campaign_id) / slug / (
                f"v{version:04d}-{hashlib.sha256(f'{self.db_path}|{_now()}'.encode()).hexdigest()[:8]}")
            if artifact_dir.exists():
                raise ModelRegistryError(f"artifact directory already exists: {artifact_dir}")
            artifact_dir.mkdir(parents=True)
            self._insert_version(
                conn, campaign_id=campaign_id, model_name=model_name, status="pending",
                kind=KIND_ML_ARTIFACT, mode="python", weight=1.0, higher_is_better=True,
                actor=actor or "ml_training", note="reserved for training",
                artifact_dir=str(artifact_dir))
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()
        return version, str(artifact_dir)

    def register_trained_version(
        self, campaign_id: str, model_name: str, artifact_dir: str, *,
        metrics: dict, gate: dict, task_type: str, higher_is_better: bool,
        dataset_rows: Optional[list] = None, split: Optional[dict] = None,
        version: Optional[int] = None, actor: Optional[str] = None, weight: float = 1.0,
        extra_spec: Optional[dict] = None,
    ) -> ModelVersion:
        """Record a trained artifact as an immutable version.

        Finalizes a reserved (pending) version when ``version`` is given, else
        creates the next version. The artifact hash is computed now; status is
        ``candidate`` when the gate passed, else ``rejected``."""
        artifact_hash = artifact_sha256(artifact_dir)
        dataset_hash = dataset_sha256(dataset_rows) if dataset_rows else None
        training_smiles = [canonical_smiles(s) for s, _ in (dataset_rows or [])]
        passed = gate.get("passed") is True
        status = "candidate" if passed else "rejected"
        note = None if passed else f"qc_gate_failed: {gate.get('reason') or 'gate not passed'}"
        actor = actor or "ml_training"
        conn = self._connect(write=True)
        try:
            if version is None:
                version = self._insert_version(
                    conn, campaign_id=campaign_id, model_name=model_name, status=status,
                    kind=KIND_ML_ARTIFACT, mode="python", weight=weight,
                    higher_is_better=higher_is_better, actor=actor, note=note,
                    task_type=task_type, artifact_dir=str(artifact_dir),
                    artifact_hash=artifact_hash, dataset_hash=dataset_hash, split=split,
                    metrics=metrics, gate=gate, spec=extra_spec,
                    training_smiles=training_smiles)
            else:
                mv = self._get(conn, campaign_id, model_name, version)
                if mv.status != "pending":
                    raise ModelRegistryError(
                        f"version {version} is {mv.status}; only a pending version can be finalized")
                if Path(mv.artifact_dir).resolve() != Path(artifact_dir).resolve():
                    raise ModelRegistryError(
                        f"artifact_dir {artifact_dir} differs from reserved {mv.artifact_dir}")
                conn.execute("""
                    UPDATE custom_model_versions SET weight = ?, higher_is_better = ?,
                      task_type = ?, artifact_sha256 = ?, dataset_sha256 = ?, split_json = ?,
                      metrics_json = ?, gate_json = ?, spec_json = ?, training_smiles_json = ?
                    WHERE campaign_id = ? AND model_name = ? AND version = ?
                """, (float(weight), int(higher_is_better), task_type, artifact_hash,
                      dataset_hash, json.dumps(split or {}),
                      json.dumps(_finite_metrics(metrics)), json.dumps(gate),
                      json.dumps(extra_spec or {}), json.dumps(sorted(set(training_smiles))),
                      campaign_id, model_name, version))
                self._set_status(conn, mv, status, actor, note)
            self._sync_summary(conn, campaign_id, model_name)
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()
        return self.get_version(campaign_id, model_name, version)

    def fail_version(self, campaign_id: str, model_name: str, version: int, reason: str,
                     actor: Optional[str] = None) -> ModelVersion:
        """Mark a pending version rejected because training did not complete."""
        conn = self._connect(write=True)
        try:
            mv = self._get(conn, campaign_id, model_name, version)
            if mv.status != "pending":
                raise ModelRegistryError(f"version {version} is {mv.status}, not pending")
            self._set_status(conn, mv, "rejected", actor or "ml_training",
                             f"training_failed: {reason}")
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()
        return self.get_version(campaign_id, model_name, version)

    # ---------------------------------------------------------- promotions
    def _promote_in_txn(self, conn, mv: "ModelVersion", actor: str, note: Optional[str]):
        if not actor or not str(actor).strip():
            raise PromotionBlocked("promotion requires a named reviewer/user")
        if mv.kind == KIND_ML_ARTIFACT and mv.gate.get("passed") is not True:
            raise PromotionBlocked(
                f"version {mv.version} QC gate did not pass "
                f"({mv.gate.get('reason') or 'no gate result recorded'})")
        if mv.kind != KIND_ML_ARTIFACT and mv.gate.get("status") != GATE_NOT_APPLICABLE \
                and mv.gate.get("passed") is not True:
            raise PromotionBlocked(f"version {mv.version} has no passed gate")
        if mv.status not in ("candidate", "retired"):
            raise PromotionBlocked(
                f"version {mv.version} is {mv.status}; only candidate or retired versions "
                "can be promoted")
        current = self._active_version(conn, mv.campaign_id, mv.model_name)
        if current is not None:
            self._set_status(conn, self._get(conn, mv.campaign_id, mv.model_name, current),
                             "retired", actor, f"superseded by v{mv.version}")
        self._set_status(conn, mv, "active", actor, note)
        self._sync_summary(conn, mv.campaign_id, mv.model_name)

    def promote(self, campaign_id: str, model_name: str, version: int, actor: str,
                note: Optional[str] = None) -> ModelVersion:
        """Make ``version`` the single active version; the previous one is retired."""
        if self._load_version_record(campaign_id, model_name, version).kind == KIND_ML_ARTIFACT:
            self.verify_artifact(campaign_id, model_name, version)
        conn = self._connect(write=True)
        try:
            self._promote_in_txn(conn, self._get(conn, campaign_id, model_name, version),
                                 actor, note)
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()
        return self.get_version(campaign_id, model_name, version)

    def reject(self, campaign_id: str, model_name: str, version: int, actor: str,
               note: Optional[str] = None) -> ModelVersion:
        if not actor or not str(actor).strip():
            raise ModelRegistryError("rejection requires a named reviewer/user")
        conn = self._connect(write=True)
        try:
            mv = self._get(conn, campaign_id, model_name, version)
            if mv.status != "candidate":
                raise ModelRegistryError(f"version {version} is {mv.status}, not candidate")
            self._set_status(conn, mv, "rejected", actor, note)
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise
        finally:
            conn.close()
        return self.get_version(campaign_id, model_name, version)

    def rollback(self, campaign_id: str, model_name: str, actor: str,
                 to_version: Optional[int] = None, note: Optional[str] = None) -> ModelVersion:
        """Re-activate a previously active (now retired) version.

        Defaults to the most recently retired version."""
        if to_version is None:
            with sqlite3.connect(self.db_path) as conn:
                row = conn.execute(
                    "SELECT version FROM custom_model_versions WHERE campaign_id = ? AND "
                    "model_name = ? AND status = 'retired' ORDER BY status_changed_at DESC, "
                    "version DESC LIMIT 1", (campaign_id, model_name)).fetchone()
            if row is None:
                raise ModelRegistryError(f"{campaign_id}/{model_name} has no retired version")
            to_version = int(row[0])
        mv = self._load_version_record(campaign_id, model_name, to_version)
        if mv.status != "retired":
            raise ModelRegistryError(
                f"rollback target v{to_version} is {mv.status}; only a previously active "
                "(retired) version can be restored")
        return self.promote(campaign_id, model_name, to_version, actor,
                            note or f"rollback to v{to_version}")

    # ---------------------------------------------------------------- reads
    def _load_version_record(self, campaign_id, model_name, version) -> ModelVersion:
        conn = self._connect()
        try:
            return self._get(conn, campaign_id, model_name, version)
        finally:
            conn.close()

    def get_version(self, campaign_id: str, model_name: str, version: int) -> ModelVersion:
        conn = self._connect()
        try:
            mv = self._get(conn, campaign_id, model_name, version)
            mv.events = [dict(r) for r in conn.execute(
                "SELECT from_status, to_status, actor, note, at FROM custom_model_version_events "
                "WHERE campaign_id = ? AND model_name = ? AND version = ? ORDER BY id",
                (campaign_id, model_name, version))]
            return mv
        finally:
            conn.close()

    def list_versions(self, campaign_id: str, model_name: str) -> list[ModelVersion]:
        conn = self._connect()
        try:
            rows = conn.execute(
                "SELECT * FROM custom_model_versions WHERE campaign_id = ? AND model_name = ? "
                "ORDER BY version", (campaign_id, model_name)).fetchall()
            return [_row_to_version(r) for r in rows]
        finally:
            conn.close()

    def get_active_version(self, campaign_id: str, model_name: str) -> Optional[ModelVersion]:
        conn = self._connect()
        try:
            v = self._active_version(conn, campaign_id, model_name)
            return None if v is None else self._get(conn, campaign_id, model_name, v)
        finally:
            conn.close()

    def list_models(self, campaign_id: str) -> list[dict]:
        with sqlite3.connect(self.db_path) as conn:
            cur = conn.execute("""
                SELECT r.model_name, r.mode, r.weight, r.higher_is_better, r.enabled,
                       r.registered_at, r.active_version,
                       (SELECT MAX(v.version) FROM custom_model_versions v
                        WHERE v.campaign_id = r.campaign_id
                          AND v.model_name = r.model_name) AS latest_version
                FROM custom_model_registrations r WHERE r.campaign_id = ?
            """, (campaign_id,))
            cols = [d[0] for d in cur.description]
            return [dict(zip(cols, row)) for row in cur.fetchall()]

    def get_run_log(self, campaign_id: str, limit: int = 100) -> list[dict]:
        """Return the last `limit` run records for a campaign."""
        with sqlite3.connect(self.db_path) as conn:
            cur = conn.execute("""
                SELECT model_name, model_version, mode, input_count, output_count,
                       run_at, duration_s, success, error
                FROM custom_model_run_log
                WHERE campaign_id = ?
                ORDER BY id DESC
                LIMIT ?
            """, (campaign_id, limit))
            cols = [d[0] for d in cur.description]
            return [dict(zip(cols, row)) for row in cur.fetchall()]

    # -------------------------------------------------------------- loading
    def verify_artifact(self, campaign_id: str, model_name: str, version: int) -> ModelVersion:
        mv = self._load_version_record(campaign_id, model_name, version)
        if mv.kind != KIND_ML_ARTIFACT:
            return mv
        if not mv.artifact_sha256:
            raise ArtifactIntegrityError(f"v{version} has no recorded artifact hash")
        actual = artifact_sha256(mv.artifact_dir)
        if actual != mv.artifact_sha256:
            raise ArtifactIntegrityError(
                f"{campaign_id}/{model_name} v{version}: artifact at {mv.artifact_dir} has "
                f"sha256 {actual}, registered {mv.artifact_sha256}; refusing to load")
        return mv

    def load_version(self, campaign_id: str, model_name: str,
                     version: Optional[int] = None) -> BaseModelWrapper:
        """Return a scorer for ``version`` (default: the active version).

        ml_artifact versions are re-hashed on every load from disk; REST/Docker
        versions are rebuilt from their persisted spec."""
        if version is None:
            active = self.get_active_version(campaign_id, model_name)
            if active is None:
                raise KeyError(f"Model '{model_name}' has no active version in campaign "
                               f"'{campaign_id}'")
            version = active.version
        key = (campaign_id, model_name, version)
        with self._lock:
            cached = self._models.get(key)
        mv = self._load_version_record(campaign_id, model_name, version)
        if cached is not None and mv.kind != KIND_ML_ARTIFACT:
            return cached
        if mv.kind == KIND_ML_ARTIFACT:
            self.verify_artifact(campaign_id, model_name, version)
            if cached is not None:
                return cached
            from ..ml_training.chemprop_wrapper import ChempropModelWrapper
            wrapper: BaseModelWrapper = ChempropModelWrapper(
                name=model_name, campaign_id=campaign_id, artifact_dir=mv.artifact_dir,
                weight=mv.weight, higher_is_better=mv.higher_is_better)
        elif mv.kind == KIND_REST:
            wrapper = RESTModelWrapper(name=model_name, campaign_id=campaign_id,
                                       weight=mv.weight, higher_is_better=mv.higher_is_better,
                                       **mv.spec["params"])
        elif mv.kind == KIND_DOCKER:
            wrapper = DockerModelWrapper(name=model_name, campaign_id=campaign_id,
                                         weight=mv.weight, higher_is_better=mv.higher_is_better,
                                         **mv.spec["params"])
        else:
            raise KeyError(
                f"Model '{model_name}' v{version} is an in-process python function and is not "
                "loaded in this process; it cannot be rebuilt from the database. Re-register it.")
        with self._lock:
            self._models[key] = wrapper
        return wrapper

    # -------------------------------------------------------------- running
    def _log_run(self, record: ModelRunRecord, version: Optional[int] = None):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO custom_model_run_log
                (campaign_id, model_name, model_version, mode, input_count, output_count,
                 run_at, duration_s, success, error)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                record.campaign_id, record.model_name, version, record.mode,
                record.input_count, record.output_count, record.run_at,
                record.duration_s, int(record.success), record.error
            ))
            conn.commit()

    def run_named_model(
        self,
        campaign_id: str,
        model_name: str,
        smiles_list: list[str],
        version: Optional[int] = None,
    ) -> tuple[dict[str, float], ModelRunRecord]:
        """Run the active (or a given) version. Raises KeyError if the model or an
        active version is unknown; ArtifactIntegrityError on hash mismatch."""
        if version is None and self.get_active_version(campaign_id, model_name) is None:
            known = {m["model_name"] for m in self.list_models(campaign_id)}
            if model_name not in known:
                raise KeyError(f"Model '{model_name}' not registered for campaign '{campaign_id}'")
        wrapper = self.load_version(campaign_id, model_name, version)
        resolved = version or self.get_active_version(campaign_id, model_name).version
        scores, record = wrapper.run(smiles_list)
        self._log_run(record, resolved)
        return scores, record

    def run_all(self, campaign_id: str, smiles_list: list[str]) -> dict[str, dict[str, float]]:
        """Run the active version of every enabled model. Returns {model_name: {smiles: score}}."""
        results: dict[str, dict[str, float]] = {}
        for m in self.list_models(campaign_id):
            if not m["enabled"] or m["active_version"] is None:
                continue
            scores, _ = self.run_named_model(campaign_id, m["model_name"], smiles_list,
                                             version=m["active_version"])
            results[m["model_name"]] = scores
        return results

    def toggle(self, campaign_id: str, model_name: str, enabled: bool):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                "UPDATE custom_model_registrations SET enabled=? WHERE campaign_id=? AND model_name=?",
                (int(enabled), campaign_id, model_name)
            )
            conn.commit()

    # ----------------------------------------------------------- comparison
    def compare_versions(self, campaign_id: str, model_name: str, version_a: int,
                         version_b: int, holdout: list, actor: Optional[str] = None,
                         allow_training_overlap: bool = False) -> dict:
        """Score two versions on the same holdout [(smiles, label), ...] and record it.

        Both versions are loaded hash-verified and evaluated with identical
        metrics. A holdout molecule that appears in either version's training
        data is refused unless allow_training_overlap is set (and then reported)."""
        if not holdout:
            raise ModelRegistryError("holdout must contain at least one (smiles, label) row")
        a = self._load_version_record(campaign_id, model_name, version_a)
        b = self._load_version_record(campaign_id, model_name, version_b)
        task_type = a.task_type or b.task_type
        if a.task_type and b.task_type and a.task_type != b.task_type:
            raise ModelRegistryError(
                f"versions have different task types ({a.task_type} vs {b.task_type})")
        if task_type not in ("classification", "regression"):
            raise ModelRegistryError(f"cannot compare task_type={task_type!r}")
        rows = [(str(s), float(y)) for s, y in holdout]
        holdout_canon = {canonical_smiles(s) for s, _ in rows}
        overlap = {}
        for mv in (a, b):
            training = set(_training_smiles(self.db_path, campaign_id, model_name, mv.version))
            overlap[f"v{mv.version}"] = sorted(holdout_canon & training)
        if any(overlap.values()) and not allow_training_overlap:
            raise ModelRegistryError(
                f"holdout is not untouched: molecules overlap training data {overlap}")

        smiles = [s for s, _ in rows]
        labels = [y for _, y in rows]
        metrics = {}
        for mv in (a, b):
            scores = self.load_version(campaign_id, model_name, mv.version).score(smiles)
            metrics[mv.version] = _holdout_metrics(task_type, labels,
                                                   [scores.get(s, float("nan")) for s in smiles])
        holdout_hash = dataset_sha256(rows)
        with sqlite3.connect(self.db_path) as conn:
            cur = conn.execute("""
                INSERT INTO custom_model_comparisons
                (campaign_id, model_name, version_a, version_b, holdout_sha256, n_holdout,
                 task_type, metrics_a_json, metrics_b_json, overlap_json, created_at, created_by)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (campaign_id, model_name, version_a, version_b, holdout_hash, len(rows),
                  task_type, json.dumps(metrics[version_a]), json.dumps(metrics[version_b]),
                  json.dumps(overlap), _now(), actor))
            comparison_id = cur.lastrowid
        return {
            "id": comparison_id, "campaign_id": campaign_id, "model_name": model_name,
            "holdout_sha256": holdout_hash, "n_holdout": len(rows), "task_type": task_type,
            "versions": {
                f"v{version_a}": {"version": version_a, "artifact_sha256": a.artifact_sha256,
                                  "metrics": metrics[version_a]},
                f"v{version_b}": {"version": version_b, "artifact_sha256": b.artifact_sha256,
                                  "metrics": metrics[version_b]},
            },
            "training_overlap": overlap,
        }

    def list_comparisons(self, campaign_id: str, model_name: str) -> list[dict]:
        with sqlite3.connect(self.db_path) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(
                "SELECT * FROM custom_model_comparisons WHERE campaign_id = ? AND model_name = ? "
                "ORDER BY id DESC", (campaign_id, model_name)).fetchall()
        out = []
        for r in rows:
            d = dict(r)
            for k in ("metrics_a_json", "metrics_b_json", "overlap_json"):
                d[k[:-5]] = json.loads(d.pop(k))
            out.append(d)
        return out


# --------------------------------------------------------------- helpers
_REGISTRIES: dict[str, CustomModelRegistry] = {}
_REGISTRIES_LOCK = threading.Lock()


def get_registry(db_path: str) -> CustomModelRegistry:
    """Process-wide registry per campaign DB, so in-process wrappers survive
    across requests. Persisted versions load from the DB regardless."""
    key = str(Path(db_path).resolve())
    with _REGISTRIES_LOCK:
        reg = _REGISTRIES.get(key)
        if reg is None:
            reg = _REGISTRIES[key] = CustomModelRegistry(db_path)
        return reg


def _row_to_version(row) -> ModelVersion:
    split = json.loads(row["split_json"] or "{}")
    return ModelVersion(
        campaign_id=row["campaign_id"], model_name=row["model_name"],
        version=int(row["version"]), status=row["status"], kind=row["kind"],
        mode=row["mode"], weight=float(row["weight"]),
        higher_is_better=bool(row["higher_is_better"]), task_type=row["task_type"],
        artifact_dir=row["artifact_dir"], artifact_sha256=row["artifact_sha256"],
        dataset_sha256=row["dataset_sha256"], split=split,
        metrics=json.loads(row["metrics_json"] or "{}"),
        gate=json.loads(row["gate_json"] or "{}"),
        spec=json.loads(row["spec_json"] or "{}"),
        parent_version=row["parent_version"], created_at=row["created_at"],
        created_by=row["created_by"], status_changed_at=row["status_changed_at"],
        status_changed_by=row["status_changed_by"], status_note=row["status_note"],
        n_training_molecules=len(json.loads(row["training_smiles_json"] or "[]")),
    )


def _training_smiles(db_path, campaign_id, model_name, version) -> list[str]:
    with sqlite3.connect(db_path) as conn:
        row = conn.execute(
            "SELECT training_smiles_json FROM custom_model_versions WHERE campaign_id = ? "
            "AND model_name = ? AND version = ?", (campaign_id, model_name, version)).fetchone()
    return json.loads(row[0]) if row else []


def _finite_metrics(metrics: dict) -> dict:
    out = {}
    for k, v in metrics.items():
        try:
            f = float(v)
        except (TypeError, ValueError):
            continue
        out[k] = f if math.isfinite(f) else None
    return out


def _external_spec(wrapper: BaseModelWrapper) -> tuple[str, dict]:
    if isinstance(wrapper, RESTModelWrapper):
        return KIND_REST, {"params": {
            "endpoint": wrapper.endpoint, "input_key": wrapper.input_key,
            "output_path": wrapper.output_path, "headers": wrapper.headers,
            "timeout": wrapper.timeout}}
    if isinstance(wrapper, DockerModelWrapper):
        return KIND_DOCKER, {"params": {
            "image": wrapper.image, "input_format": wrapper.input_format,
            "output_format": wrapper.output_format, "extra_args": wrapper.extra_args,
            "command": wrapper.command}}
    return KIND_PYTHON, {}


def _holdout_metrics(task_type: str, labels: list, preds: list) -> dict:
    """Identical metric set for every compared version."""
    pairs = [(y, p) for y, p in zip(labels, preds) if p is not None and math.isfinite(p)]
    out: dict[str, Any] = {"n": len(labels), "n_scored": len(pairs)}
    if not pairs:
        return out
    ys = [y for y, _ in pairs]
    ps = [p for _, p in pairs]
    if task_type == "classification":
        out["accuracy"] = sum((p >= 0.5) == (y >= 0.5) for y, p in pairs) / len(pairs)
        pos = [p for y, p in pairs if y >= 0.5]
        neg = [p for y, p in pairs if y < 0.5]
        if pos and neg:
            wins = sum(1.0 if pp > pn else 0.5 if pp == pn else 0.0 for pp in pos for pn in neg)
            out["auc"] = wins / (len(pos) * len(neg))
        else:
            out["auc"] = None
            out["auc_unavailable"] = "holdout contains a single class"
    else:
        errs = [p - y for y, p in pairs]
        out["mae"] = sum(abs(e) for e in errs) / len(errs)
        out["rmse"] = math.sqrt(sum(e * e for e in errs) / len(errs))
        mean_y = sum(ys) / len(ys)
        ss_tot = sum((y - mean_y) ** 2 for y in ys)
        out["r2"] = 1 - sum(e * e for e in errs) / ss_tot if ss_tot > 0 else None
    return out


def _slug(name: str) -> str:
    return "".join(c if c.isalnum() or c in "-_" else "-" for c in name.strip().lower())
