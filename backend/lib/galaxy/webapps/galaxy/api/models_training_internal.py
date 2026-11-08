"""Admin-only bridge; Node authenticates owners and resolves exact canonical outputs.

Normal user Galaxy keys cannot invoke these endpoints. Never add a generic
browser proxy: owner/run launch context is supplied only by the Node server.
"""
from __future__ import annotations
import os
import tempfile
from typing import List, Optional
from fastapi import HTTPException
from pydantic import BaseModel
from galaxy.webapps.galaxy.api import Router
from galaxy.ai.ml_training.run_registration import (
    OwnedTrainingRun, RunTrainingRegistration, RegistrationAccessError, RegistrationConflict,
    list_registered_run_versions,
)
from galaxy.ai.ml_training.published_output_staging import (
    configured_buckets, configured_s3_client, stage_published_outputs,
)
router = Router(tags=['models-training-internal'])


class TrainingRunContext(BaseModel):
    run_id: str
    owner_id: str
    project_id: Optional[str] = None
    status: str
    model_name: str
    model_type: str
    task_type: str
    metric: str
    gate_threshold: Optional[float] = None
    higher_is_better: bool


class ArtifactReference(BaseModel):
    s3_uri: str
    relative_path: str


class RegistrationRequest(BaseModel):
    run: TrainingRunContext
    artifacts: List[ArtifactReference]
    metrics_s3_uri: str


def _root():
    return os.environ.get('BIOMATE_MODEL_REGISTRY_ROOT', '/app/database/model_registry')


@router.post('/api/internal/model-training/register', require_admin=True)
def register_training_output(body: RegistrationRequest):
    try:
        run = OwnedTrainingRun(**body.run.dict())
        if not run.owner_id or not run.run_id:
            raise ValueError('Missing server-resolved owner or run identity')
        with tempfile.TemporaryDirectory(prefix='model-registration-') as directory:
            def stage(_):
                return stage_published_outputs(configured_s3_client(), configured_buckets(),
                    [item.dict() for item in body.artifacts], body.metrics_s3_uri, directory)
            core = RunTrainingRegistration(_root(), lambda rid: run if rid == run.run_id else None, stage)
            result = core.register(run.owner_id, run.run_id).to_dict()
            result.pop('artifact_dir', None)
            return result
    except RegistrationAccessError as exc:
        raise HTTPException(status_code=403, detail=str(exc))
    except RegistrationConflict as exc:
        raise HTTPException(status_code=409, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get('/api/internal/model-training/versions', require_admin=True)
def registered_training_versions(owner_id: str, project_id: Optional[str] = None,
                                 run_id: Optional[str] = None):
    if not owner_id:
        raise HTTPException(status_code=400, detail='Missing server-resolved owner')
    return {'versions': list_registered_run_versions(_root(), owner_id, project_id, run_id)}
