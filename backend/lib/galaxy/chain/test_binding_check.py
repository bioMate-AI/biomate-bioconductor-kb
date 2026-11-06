"""Offline tests for galaxy.chain.binding_check and the pre-launch stop in
workflow_chain._run_chain."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from galaxy.chain import binding_check as bc


def _wf(root, name, nf_text, schema=None):
    d = Path(root) / name
    d.mkdir(parents=True)
    (d / "main.nf").write_text(nf_text)
    if schema is not None:
        (d / "nextflow_schema.json").write_text(json.dumps(schema))


def _load_workflow_chain(tc):
    """Import workflow_chain; fall back to a file load with the Galaxy web stack
    stubbed when the full Galaxy API package cannot be imported (a2wsgi etc.)."""
    try:
        from galaxy.webapps.galaxy.api import workflow_chain as wc
        return wc
    except Exception:
        pass
    import importlib.util
    import sys
    import types
    stubs = {}
    for n in ("galaxy.webapps", "galaxy.webapps.galaxy", "galaxy.webapps.galaxy.api",
              "galaxy.webapps.galaxy.api.nextflow_executor"):
        m = types.ModuleType(n)
        m.__path__ = []
        stubs[n] = m
    class _Router:
        def __init__(self, *a, **k):
            pass
        def __getattr__(self, name):
            return lambda *a, **k: (lambda f: f)
    stubs["galaxy.webapps.galaxy.api"].Router = _Router
    stubs["galaxy.webapps.galaxy.api.nextflow_executor"].execute_nextflow = mock.MagicMock()
    old = {n: sys.modules.get(n) for n in stubs}
    sys.modules.update(stubs)
    try:
        path = Path(bc.__file__).resolve().parents[1] / "webapps" / "galaxy" / "api" / "workflow_chain.py"
        spec = importlib.util.spec_from_file_location("_wc_under_test", str(path))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except Exception as exc:
        tc.skipTest("workflow_chain not importable: %s" % exc)
    finally:
        for n, v in old.items():
            if v is None:
                sys.modules.pop(n, None)
            else:
                sys.modules[n] = v


class BindingCheckTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.roots = [self.root]
        _wf(self.root, "down", "workflow { println params.counts_matrix; println params.genome }")
        _wf(self.root, "schema_only", "workflow { }",
            {"properties": {"top": {}}, "definitions": {"g": {"properties": {"sheet": {}}}}})

    def tearDown(self):
        self.tmp.cleanup()

    def steps(self, down="down/main.nf"):
        return [{"nextflow_path": "up/main.nf", "workflow_name": "Up"},
                {"nextflow_path": down, "workflow_name": "Down"}]

    def conn(self, to_input):
        return [{"from_step": 1, "to_step": 2, "from_output": "x", "to_input": to_input}]

    def test_matching_name_no_problem(self):
        p, u = bc.check_connections(self.steps(), self.conn("counts_matrix"), roots=self.roots)
        self.assertEqual((p, u), ([], []))

    def test_non_matching_reports_declared(self):
        p, u = bc.check_connections(self.steps(), self.conn("bogus"), roots=self.roots)
        self.assertEqual(u, [])
        self.assertEqual(len(p), 1)
        self.assertEqual(p[0]["declared"], ["counts_matrix", "genome"])
        self.assertEqual((p[0]["from_step"], p[0]["to_step"], p[0]["to_input"]), (1, 2, "bogus"))
        self.assertIn("counts_matrix", p[0]["message"])
        self.assertIn("'bogus'", p[0]["message"])

    def test_missing_file_is_undeterminable(self):
        self.assertIsNone(bc.declared_params("nope/main.nf", roots=self.roots))
        p, u = bc.check_connections(self.steps("nope/main.nf"), self.conn("x"), roots=self.roots)
        self.assertEqual(p, [])
        self.assertEqual(len(u), 1)

    def test_schema_only_params_recognised(self):
        self.assertEqual(bc.declared_params("schema_only/main.nf", roots=self.roots), {"top", "sheet"})
        p, _ = bc.check_connections(self.steps("schema_only/main.nf"), self.conn("sheet"), roots=self.roots)
        self.assertEqual(p, [])


class RunPathStopsBeforeLaunchTest(unittest.TestCase):
    def test_run_chain_fails_without_launching(self):
        wc = _load_workflow_chain(self)
        state = {
            "chain_run_id": "c1", "status": "running", "execution_mode": "sequential",
            "connections": [{"from_step": 1, "to_step": 2, "from_output": "x", "to_input": "bogus"}],
            "steps": [
                {"nextflow_path": "up/main.nf", "params": {}, "status": "succeeded", "run_id": "r1"},
                {"nextflow_path": "down/main.nf", "params": {}, "status": "pending"},
            ],
        }
        problem = {"message": "boom", "to_step": 2}
        saved = []
        with mock.patch.object(wc, "_get_chain", return_value=state), \
                mock.patch.object(wc, "_update_chain", side_effect=lambda s: saved.append(json.dumps(s))), \
                mock.patch.object(wc, "_check_bindings", return_value=([problem], [])) as _cb, \
                mock.patch.object(wc, "_apply_connection_handoffs") as ex:
            wc._run_chain("c1", start_from_step=1)
        ex.assert_not_called()  # returned before wiring / any job launch
        self.assertEqual(state["status"], "failed")
        self.assertEqual(state["steps"][1]["status"], "failed")
        self.assertEqual(state["steps"][1]["error"], "boom")


if __name__ == "__main__":
    unittest.main()
