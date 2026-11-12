"""HTTP contract of POST /api/model-training/plan (Galaxy router).

galaxy.webapps.galaxy.api pulls in the full Galaxy app (beaker, …), so the
router module is loaded by file path against a minimal Router stand-in that
accepts Galaxy's ``require_admin`` kwarg. The admin check itself is Galaxy's
(covered by Galaxy); this test pins the request/response contract Node relies on.
"""
import importlib.util
import os
import sys
import types

import pytest

fastapi = pytest.importorskip("fastapi")
from fastapi import APIRouter, HTTPException  # noqa: E402

_API = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..",
                                    "webapps", "galaxy", "api", "model_training_plan.py"))


class _Router(APIRouter):
    def post(self, path, *, require_admin=False, **kw):  # Galaxy-compatible kwarg
        assert require_admin is True, "plan endpoint must stay admin-only"
        return super().post(path, **kw)


@pytest.fixture()
def mod(monkeypatch):
    stub = types.ModuleType("galaxy.webapps.galaxy.api")
    stub.Router = _Router
    for name in ("galaxy.webapps", "galaxy.webapps.galaxy"):
        monkeypatch.setitem(sys.modules, name, sys.modules.get(name) or types.ModuleType(name))
    monkeypatch.setitem(sys.modules, "galaxy.webapps.galaxy.api", stub)
    spec = importlib.util.spec_from_file_location("model_training_plan_under_test", _API)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


BODY = {"dataset_s3_uri": "s3://biomate-nextflow-work/uploads/project-p/t.csv",
        "dataset_name": "t.csv", "model_type": "sklearn_tabular",
        "target_col": "label", "task_type": "classification"}


def test_route_is_registered(mod):
    assert [(r.path, sorted(r.methods)) for r in mod.router.routes] == [("/api/model-training/plan", ["POST"])]


def test_plan_returns_workflow_ga(mod):
    body = mod.plan_model_training(dict(BODY), owner_id="u1")
    assert body["nextflow_path"] == "ml_training/chemprop_train.nf"
    assert body["workflow_ga"]["parameters"]["target_col"] == "label"
    assert body["compute_config"]["container"]


def test_plan_requires_owner_header(mod):
    with pytest.raises(HTTPException) as exc:
        mod.plan_model_training(dict(BODY), owner_id=None)
    assert exc.value.status_code == 403


def test_plan_validation_error_is_400_with_message(mod):
    with pytest.raises(HTTPException) as exc:
        mod.plan_model_training({**BODY, "target_col": ""}, owner_id="u1")
    assert exc.value.status_code == 400 and "target_col" in exc.value.detail
