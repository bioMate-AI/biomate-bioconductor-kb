"""API contract tests with only the Galaxy Router import isolated.

The actual Pydantic models, API functions, persistence and DAG validator are loaded.
This is not a full Galaxy application or AWS execution test.
"""
import asyncio
import importlib.util
from pathlib import Path
import sys
import types
from unittest.mock import patch
import pytest
from fastapi import APIRouter, HTTPException


@pytest.fixture
def api(tmp_path, monkeypatch):
    wrapper = types.ModuleType('galaxy.webapps.galaxy.api')
    wrapper.Router = APIRouter
    location = Path(__file__).parents[1] / 'lib/galaxy/webapps/galaxy/api/workflow_chain.py'
    spec = importlib.util.spec_from_file_location('dag_api_test', location)
    module = importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules, {'galaxy.webapps.galaxy.api': wrapper}):
        spec.loader.exec_module(module)
    monkeypatch.setattr(module, '_CHAINS_DIR', tmp_path)
    monkeypatch.setattr(module, 'ensure_chain_reconciler_started', lambda: None)
    monkeypatch.setattr(module.threading, 'Thread', lambda **kwargs: types.SimpleNamespace(start=lambda: None))
    return module


def test_request_retains_dependencies_dimensions_and_persistence(api):
    req = api.ChainSubmitRequest(steps=[
        {'nextflow_path':'one.nf','depends_on':[], 'dimensions':{'target':'X'}},
        {'nextflow_path':'two.nf','depends_on':[1]},
    ])
    result = asyncio.run(api.submit_chain(req))
    saved = api._load_chain(result['chain_run_id'])
    assert saved['execution_mode'] == 'dag'
    assert saved['steps'][0]['dimensions'] == {'target':'X'}
    assert saved['steps'][1]['depends_on'] == [1]
    assert api._resolve_submit_steps(req.steps)[1]['depends_on'] == [1]


def test_legacy_request_stays_sequential(api):
    result = asyncio.run(api.submit_chain(api.ChainSubmitRequest(steps=[{'nextflow_path':'one.nf'}])))
    assert api._get_chain(result['chain_run_id'])['execution_mode'] == 'sequential'


def test_rejects_mixed_implicit_dependencies_before_dispatch(api):
    req = api.ChainSubmitRequest(steps=[{'nextflow_path':'one.nf','depends_on':[]}, {'nextflow_path':'two.nf'}])
    with pytest.raises(HTTPException) as exc: asyncio.run(api.submit_chain(req))
    assert exc.value.status_code == 400
    assert not api._chains


def test_existing_dag_cannot_be_overwritten_by_legacy_submit(api):
    result = asyncio.run(api.submit_chain(api.ChainSubmitRequest(steps=[{'nextflow_path':'one.nf','depends_on':[]}])))
    with pytest.raises(HTTPException) as exc:
        asyncio.run(api.submit_chain(api.ChainSubmitRequest(chain_run_id=result['chain_run_id'], steps=[{'nextflow_path':'two.nf'}])))
    assert exc.value.status_code == 409


def test_dag_adapter_does_not_promote_empty_output_success(api, monkeypatch):
    executor = types.ModuleType('galaxy.webapps.galaxy.api.nextflow_executor')
    executor.NextflowExecuteRequest = types.SimpleNamespace
    executor.execute_nextflow = lambda request: {'run_id': 'recorded-run'}
    executor.get_nextflow_status = lambda rid: {'status': 'completed', 'returncode': 0}
    monkeypatch.setattr(api, '_list_run_output_files', lambda rid: [])
    state = {'chain_run_id': 'empty-output', 'execution_mode': 'dag', 'status': 'running',
             'steps': [{'nextflow_path':'one.nf','depends_on':[],'params':{},'status':'pending'}]}
    from galaxy.chain import dag
    original = dag.run_plan
    monkeypatch.setattr(dag, 'run_plan', lambda *a, **kw: original(*a, **kw, sleep=lambda _: None))
    with patch.dict(sys.modules, {'galaxy.webapps.galaxy.api.nextflow_executor': executor}):
        api._run_dag_chain(state)
    assert state['status'] == 'failed'
    assert state['steps'][0]['error'] == 'Completed without published result artifacts'
    assert not state['report']['complete']
