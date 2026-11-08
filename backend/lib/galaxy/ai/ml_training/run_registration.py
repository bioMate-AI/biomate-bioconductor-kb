"""Central ingestion core for published, run-owned training artifacts.

This module deliberately exposes no HTTP route. Adapters MUST resolve the run
from authenticated execution storage and stage only its canonical published
outputs. Neither callback may accept client-provided paths, metrics, or owners.
Training artifacts remain inert until separately reviewed/promoted.
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import math
import shutil
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

from ..drug_discovery.custom_model_registry import CustomModelRegistry, ModelVersion, artifact_sha256


class RegistrationAccessError(PermissionError):
    pass


class RegistrationConflict(ValueError):
    pass


@dataclass(frozen=True)
class OwnedTrainingRun:
    """Server-resolved launch context; never deserialize this from a public body."""
    run_id: str
    owner_id: str
    project_id: Optional[str]
    status: str
    model_name: str
    model_type: str
    task_type: str
    metric: str
    gate_threshold: Optional[float]
    higher_is_better: bool


@dataclass(frozen=True)
class StagedTrainingOutputs:
    """Exact bound outputs staged by a privileged adapter, with verified tree hash."""
    artifact_dir: str
    expected_artifact_sha256: str
    metrics_document: dict


def _gate(run: OwnedTrainingRun, document: dict) -> dict:
    gate_document = document.get('gate')
    gates = gate_document.get('gates', []) if isinstance(gate_document, dict) else []
    gates = gates if isinstance(gates, list) else []
    matches = [g for g in gates if isinstance(g, dict) and g.get('name') == run.metric]
    if len(matches) != 1:
        return {'passed': False, 'metric': run.metric, 'reason': 'Training gate evidence missing or ambiguous'}
    g = matches[0]
    value, threshold = g.get('measured'), run.gate_threshold
    finite = lambda x: isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)
    metrics = document.get('metrics') or {}
    measured = next((metrics[key] for key in (f'val_{run.metric}', f'test_{run.metric}', run.metric) if key in metrics), None)
    evidence_matches = finite(value) and finite(measured) and value == measured and finite(threshold) and g.get('threshold') == threshold
    comparison = evidence_matches and (value >= threshold if run.higher_is_better else value <= threshold)
    passed = bool(comparison and g.get('status') == 'pass' and run.status == 'completed')
    return {'passed': passed, 'metric': run.metric, 'value': value if finite(value) else None,
            'threshold': threshold if finite(threshold) else None,
            'direction': 'higher_is_better' if run.higher_is_better else 'lower_is_better',
            'reason': g.get('reason') if passed else 'Training gate evidence did not meet the recorded launch threshold'}


def _verify_tree(root: Path, expected: str) -> str:
    if not root.is_dir() or root.is_symlink():
        raise ValueError('Artifact directory must be a real directory')
    files = list(root.rglob('*'))
    if not any(p.is_file() for p in files) or any(p.is_symlink() for p in files):
        raise ValueError('Artifacts must contain files and no symbolic links')
    digest = artifact_sha256(str(root))
    if digest != expected:
        raise RegistrationConflict('Published artifact checksum mismatch')
    return digest


class RunTrainingRegistration:
    def __init__(self, central_root: str,
                 resolve_run: Callable[[str], Optional[OwnedTrainingRun]],
                 stage_outputs: Callable[[OwnedTrainingRun], StagedTrainingOutputs]):
        self.root = Path(central_root)
        self.resolve_run = resolve_run
        self.stage_outputs = stage_outputs

    def register(self, requesting_user_id: Optional[str], run_id: str) -> ModelVersion:
        if not requesting_user_id:
            raise RegistrationAccessError('Authentication required')
        run = self.resolve_run(run_id)
        # Scope registration more narrowly than project viewing: only the owner
        # may turn their execution into a model version. No caller-selected campaign.
        if run is None or run.run_id != run_id or run.owner_id != requesting_user_id:
            raise RegistrationAccessError('Training run is not owned by caller')
        if run.status not in ('completed', 'failed'):
            raise ValueError('Training has not reached a terminal state')
        if run.model_type not in ('sklearn_tabular', 'sklearn_gbr', 'chemprop_gnn', 'ludwig_tabular', 'ludwig_llm', 'trl_dpo', 'trl_grpo'):
            raise ValueError('Unsupported training run type')
        if not run.model_name.strip() or run.task_type not in ('classification', 'regression', 'text_generation'):
            raise ValueError('Missing recorded model launch context')
        staged = self.stage_outputs(run)
        source_hash = _verify_tree(Path(staged.artifact_dir), staged.expected_artifact_sha256)
        document = staged.metrics_document
        if not isinstance(document, dict) or document.get('name') != run.model_name:
            raise ValueError('Training metrics do not match the recorded model name')
        metrics = document.get('metrics')
        if not isinstance(metrics, dict):
            raise ValueError('Training metrics are missing')
        gate = _gate(run, document)
        metadata_hash = hashlib.sha256(json.dumps({'metrics': metrics, 'gate': gate, 'model_type': run.model_type,
            'task_type': run.task_type, 'name': run.model_name}, sort_keys=True, allow_nan=False).encode()).hexdigest()
        scope = hashlib.sha256(json.dumps([run.owner_id, run.project_id], separators=(',', ':')).encode()).hexdigest()
        campaign = 'owned-training-' + scope
        location = self.root / scope
        location.mkdir(parents=True, exist_ok=True)
        # Inter-process lock covers the existing registry transaction plus the
        # sourceRunId replay check. Source run ids need no schema migration.
        with (location / 'ingestion.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            registry = CustomModelRegistry(str(location / 'models.db'))
            with sqlite3.connect(registry.db_path) as db:
                rows = db.execute('SELECT model_name, version, spec_json FROM custom_model_versions WHERE campaign_id=?', (campaign,)).fetchall()
            for name, version, raw in rows:
                spec = json.loads(raw)
                if spec.get('sourceRunId') == run.run_id:
                    if spec.get('sourceArtifactSha256') != source_hash or spec.get('sourceMetadataSha256') != metadata_hash:
                        raise RegistrationConflict('Training source changed after registration')
                    existing = registry.get_version(campaign, name, version)
                    _verify_tree(Path(existing.artifact_dir), existing.artifact_sha256)
                    return existing
            target = location / 'artifacts' / source_hash
            if target.exists():
                _verify_tree(target, source_hash)
            else:
                target.parent.mkdir(exist_ok=True)
                shutil.copytree(staged.artifact_dir, target, symlinks=True)
                _verify_tree(target, source_hash)
            return registry.register_trained_version(campaign, run.model_name, str(target),
                metrics=metrics, gate=gate, task_type=run.task_type, higher_is_better=run.higher_is_better,
                actor=run.owner_id, extra_spec={'model_type': run.model_type,
                    'sourceRunId': run.run_id, 'sourceOwnerId': run.owner_id, 'sourceProjectId': run.project_id,
                    'sourceArtifactSha256': source_hash, 'sourceMetadataSha256': metadata_hash})


def list_registered_run_versions(central_root: str, owner_id: str, project_id: Optional[str],
                                 run_id: Optional[str] = None) -> list:
    """Internal owner-scoped read; caller identity must be resolved by the API adapter."""
    if not owner_id:
        raise RegistrationAccessError('Authentication required')
    scope = hashlib.sha256(json.dumps([owner_id, project_id], separators=(',', ':')).encode()).hexdigest()
    db_path = Path(central_root) / scope / 'models.db'
    if not db_path.exists():
        return []
    with sqlite3.connect(f'file:{db_path}?mode=ro', uri=True) as db:
        rows = db.execute('SELECT campaign_id, model_name, version, spec_json FROM custom_model_versions ORDER BY created_at DESC,version DESC').fetchall()
    registry = CustomModelRegistry(str(db_path))
    out = []
    for campaign, name, version, raw in rows:
        spec = json.loads(raw)
        if spec.get('sourceOwnerId') != owner_id or spec.get('sourceProjectId') != project_id:
            continue
        if run_id and spec.get('sourceRunId') != run_id:
            continue
        row = registry.get_version(campaign, name, version).to_dict()
        row.pop('artifact_dir', None)
        out.append(row)
    return out
