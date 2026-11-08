"""Routing-time runnability must judge the file the EXECUTOR runs, not the display stub.

_find_nf_file prefers biomni_workflows/ stubs (params only, no workflow block); the executor resolves
nfcore/<name>/main.nf to the real downloaded pipeline first. Judging the stub flagged every nf-core
pipeline as non-executable (dev log: "proteomicslfq failed executability check ... keeping as routing
result"), though 128/131 have a real copy (2026-11-05).

Run: cd backend && PYTHONPATH=lib pytest tests/test_executability_uses_executor_resolver.py -v
"""
import sys
import types
from types import SimpleNamespace

from galaxy.ai.ai_assistant import AIAssistant

EXECUTOR = "galaxy.webapps.galaxy.api.nextflow_executor"  # imported lazily by _resolve_execution_nf


def _executor(monkeypatch, resolve):
    # The real module needs Galaxy's web stack (absent outside the container); stand in for it.
    monkeypatch.setitem(sys.modules, EXECUTOR, types.SimpleNamespace(_resolve_nextflow_path=resolve))

STUB = "params.input = null\nprocess FOO { script: 'echo hi' }\n"
REAL = "include { PIPE } from './workflows/pipe'\nworkflow {\n  PIPE()\n}\n"


def _assistant(stub_path):
    a = AIAssistant.__new__(AIAssistant)
    a._find_nf_file = lambda _f: stub_path
    return a


def _match():
    return SimpleNamespace(executable=1, format="nextflow", filename="nfcore/proteomicslfq/main.nf",
                           name="nf-core/proteomicslfq", tags=[])


def test_real_pipeline_makes_the_stub_entry_executable(tmp_path, monkeypatch):
    stub, real = tmp_path / "stub.nf", tmp_path / "real.nf"
    stub.write_text(STUB); real.write_text(REAL)
    _executor(monkeypatch, lambda _p: real)
    assert _assistant(stub)._is_executable_nextflow_match(_match()) is True


def test_stub_only_pipeline_is_still_rejected(tmp_path, monkeypatch):
    stub = tmp_path / "stub.nf"; stub.write_text(STUB)
    _executor(monkeypatch, lambda _p: stub)  # executor finds only the stub
    assert _assistant(stub)._is_executable_nextflow_match(_match()) is False


def test_unresolvable_by_executor_falls_back_to_find_nf_file(tmp_path, monkeypatch):
    stub = tmp_path / "stub.nf"; stub.write_text(STUB)
    def _raise(_p):
        raise FileNotFoundError("no")
    _executor(monkeypatch, _raise)
    assert _assistant(stub)._is_executable_nextflow_match(_match()) is False
