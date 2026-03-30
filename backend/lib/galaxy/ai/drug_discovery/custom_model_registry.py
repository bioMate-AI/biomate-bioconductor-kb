"""
Per-campaign registry for custom scoring models.
"""
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from .custom_model_wrapper import BaseModelWrapper, ModelRunRecord


class CustomModelRegistry:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self._models: dict[str, dict[str, BaseModelWrapper]] = {}  # {campaign_id: {name: wrapper}}
        self._ensure_schema()

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
            conn.commit()

    def register(self, wrapper: BaseModelWrapper, config: dict = None):
        cid = wrapper.campaign_id
        if cid not in self._models:
            self._models[cid] = {}
        self._models[cid][wrapper.name] = wrapper
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT OR REPLACE INTO custom_model_registrations
                (campaign_id, model_name, mode, weight, higher_is_better, enabled, config_json, registered_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                cid, wrapper.name, wrapper._mode(), wrapper.weight,
                int(wrapper.higher_is_better), int(wrapper.enabled),
                json.dumps(config or {}), datetime.now(timezone.utc).isoformat()
            ))
            conn.commit()

    def run_all(self, campaign_id: str, smiles_list: list[str]) -> dict[str, dict[str, float]]:
        """Run all enabled models for a campaign. Returns {model_name: {smiles: score}}."""
        results: dict[str, dict[str, float]] = {}
        models = self._models.get(campaign_id, {})
        for name, wrapper in models.items():
            if not wrapper.enabled:
                continue
            scores, record = wrapper.run(smiles_list)
            results[name] = scores
            self._log_run(record)
        return results

    def _log_run(self, record: ModelRunRecord):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO custom_model_run_log
                (campaign_id, model_name, mode, input_count, output_count,
                 run_at, duration_s, success, error)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                record.campaign_id, record.model_name, record.mode,
                record.input_count, record.output_count, record.run_at,
                record.duration_s, int(record.success), record.error
            ))
            conn.commit()

    def list_models(self, campaign_id: str) -> list[dict]:
        with sqlite3.connect(self.db_path) as conn:
            cur = conn.execute("""
                SELECT model_name, mode, weight, higher_is_better, enabled, registered_at
                FROM custom_model_registrations WHERE campaign_id = ?
            """, (campaign_id,))
            cols = [d[0] for d in cur.description]
            return [dict(zip(cols, row)) for row in cur.fetchall()]

    def get_run_log(self, campaign_id: str, limit: int = 100) -> list[dict]:
        """Return the last `limit` run records for a campaign."""
        with sqlite3.connect(self.db_path) as conn:
            cur = conn.execute("""
                SELECT model_name, mode, input_count, output_count,
                       run_at, duration_s, success, error
                FROM custom_model_run_log
                WHERE campaign_id = ?
                ORDER BY id DESC
                LIMIT ?
            """, (campaign_id, limit))
            cols = [d[0] for d in cur.description]
            return [dict(zip(cols, row)) for row in cur.fetchall()]

    def run_named_model(
        self,
        campaign_id: str,
        model_name: str,
        smiles_list: list[str],
    ) -> tuple[dict[str, float], "ModelRunRecord"]:
        """Run a single registered model by name. Raises KeyError if not found."""
        models = self._models.get(campaign_id, {})
        if model_name not in models:
            # Try loading from DB-persisted registrations — wrapper config is limited
            # without the original callable, so only Docker/REST wrappers can be
            # reconstructed here.
            raise KeyError(f"Model '{model_name}' not loaded in this process session. "
                           "Re-register via POST /models/register before running.")
        wrapper = models[model_name]
        scores, record = wrapper.run(smiles_list)
        self._log_run(record)
        return scores, record

    def toggle(self, campaign_id: str, model_name: str, enabled: bool):
        if campaign_id in self._models and model_name in self._models[campaign_id]:
            self._models[campaign_id][model_name].enabled = enabled
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                "UPDATE custom_model_registrations SET enabled=? WHERE campaign_id=? AND model_name=?",
                (int(enabled), campaign_id, model_name)
            )
            conn.commit()
