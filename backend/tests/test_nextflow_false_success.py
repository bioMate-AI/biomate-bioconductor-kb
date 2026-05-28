"""Tests for Nextflow false-success detection in nextflow_executor.py."""
import importlib.util
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import MagicMock

_NF_EXEC_PATH = (
    Path(__file__).parents[1]
    / "lib/galaxy/webapps/galaxy/api/nextflow_executor.py"
)


def _make_stub(name: str) -> types.ModuleType:
    m = types.ModuleType(name)
    m.__spec__ = None
    return m


for _sname in [
    "galaxy", "galaxy.managers", "galaxy.managers.context",
    "galaxy.webapps", "galaxy.webapps.galaxy",
    "a2wsgi", "a2wsgi.wsgi", "dotenv",
]:
    sys.modules.setdefault(_sname, _make_stub(_sname))

_ctx_stub = sys.modules["galaxy.managers.context"]
if not hasattr(_ctx_stub, "ProvidesUserContext"):
    _ctx_stub.ProvidesUserContext = object

_pydantic_stub = _make_stub("pydantic")
_pydantic_stub.BaseModel = object
sys.modules["pydantic"] = _pydantic_stub


class _FakeHTTPException(Exception):
    def __init__(self, status_code=None, detail=None):
        self.status_code = status_code
        self.detail = detail


_fastapi_stub = _make_stub("fastapi")
_fastapi_stub.HTTPException = _FakeHTTPException
_fastapi_stub.Request = object
_fastapi_stub.Response = object
_fastapi_stub.responses = _make_stub("fastapi.responses")
_fastapi_stub.responses.HTMLResponse = MagicMock()
sys.modules["fastapi"] = _fastapi_stub
sys.modules["fastapi.responses"] = _fastapi_stub.responses

_gwa_api_stub = _make_stub("galaxy.webapps.galaxy.api")
_gwa_api_stub.Router = MagicMock(return_value=MagicMock(
    post=MagicMock(return_value=lambda f: f),
    get=MagicMock(return_value=lambda f: f),
))
_gwa_api_stub.DependsOnTrans = None
sys.modules["galaxy.webapps.galaxy.api"] = _gwa_api_stub

_spec = importlib.util.spec_from_file_location("_nf_executor_false_success", _NF_EXEC_PATH)
_nf = importlib.util.module_from_spec(_spec)
assert _spec.loader is not None
_spec.loader.exec_module(_nf)

# NetMHCpan run 530c1284 — Groovy stack trace in log_tail, no S3 outputs, 18s.
_NETMHCPAN_LOG_TAIL = [
    "\tat java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)",
    "\tat org.codehaus.groovy.reflection.CachedMethod.invoke(CachedMethod.java:343)",
    "\tat nextflow.script.WorkflowDef.run(WorkflowDef.groovy:189)",
]


class TestNextflowFalseSuccess(unittest.TestCase):
    def test_groovy_stack_trace_in_log_tail_is_failure(self):
        self.assertTrue(
            _nf._log_indicates_nextflow_failure(log_full_text="", log_tail=_NETMHCPAN_LOG_TAIL)
        )

    def test_netmhcpan_manifest_shape_looks_like_false_success(self):
        self.assertTrue(
            _nf._looks_like_false_success(
                log_tail=_NETMHCPAN_LOG_TAIL,
                total_steps=0,
                duration_s=18,
                s3_output_files=[],
                workflow_domain="epitope_prediction",
                nextflow_path="nfcore/epitopeprediction/main.nf",
            )
        )

    def test_quick_fail_zero_steps_no_outputs(self):
        self.assertTrue(
            _nf._looks_like_false_success(
                total_steps=0,
                duration_s=30,
                s3_output_files=[],
            )
        )

    def test_epitope_domain_requires_s3_outputs(self):
        self.assertTrue(
            _nf._looks_like_false_success(
                workflow_domain="epitope_prediction",
                s3_output_files=[],
            )
        )

    def test_real_success_with_outputs_not_flagged(self):
        self.assertFalse(
            _nf._looks_like_false_success(
                total_steps=10,
                duration_s=600,
                s3_output_files=[{"s3_uri": "s3://b/o/predictions.tsv", "filename": "predictions.tsv"}],
                workflow_domain="epitope_prediction",
            )
        )


if __name__ == "__main__":
    unittest.main()
