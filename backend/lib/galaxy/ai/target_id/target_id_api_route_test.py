"""Route-level tests for /api/target-id/*. Galaxy's Router is replaced by a minimal stand-in so the handlers run
without the full Galaxy environment; no network is used (client tables only, LLM off)."""
import asyncio
import importlib.util
import os
import sys
import types
import unittest
from pathlib import Path

API = Path(__file__).parents[2] / "webapps/galaxy/api/target_id_api.py"


class _Router:
    def __init__(self, **kw):
        self.routes = []

    def _reg(self, path):
        def deco(fn):
            self.routes.append(path)
            return fn
        return deco

    def get(self, path, **kw):
        return self._reg(path)

    def post(self, path, **kw):
        return self._reg(path)


def _load():
    stub = types.ModuleType("galaxy.webapps.galaxy.api")
    stub.Router = _Router
    sys.modules.setdefault("galaxy.webapps", types.ModuleType("galaxy.webapps"))
    sys.modules.setdefault("galaxy.webapps.galaxy", types.ModuleType("galaxy.webapps.galaxy"))
    sys.modules["galaxy.webapps.galaxy.api"] = stub
    spec = importlib.util.spec_from_file_location("target_id_api_under_test", str(API))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod            # pydantic resolves the module's string annotations through sys.modules
    spec.loader.exec_module(mod)
    return mod


def run(coro):
    return asyncio.new_event_loop().run_until_complete(coro)


class RouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m = _load()
        from fastapi import HTTPException
        cls.HTTPException = HTTPException
        cls.rows = [{"gene": "BRAF", "log2FoldChange": 6, "padj": 1e-12}, {"gene": "TP53", "log2FoldChange": 2, "padj": 1e-4}]

    def req(self, **kw):
        base = dict(query="q", use_llm=False, include_network=False)
        base.update(kw)
        return self.m.IdentifyTargetsRequest(**base)

    def test_routes_are_registered(self):
        self.assertEqual(sorted(self.m.router.routes), ["/api/target-id/identify", "/api/target-id/status"])

    def test_status_reports_hosts_and_modes(self):
        os.environ.pop("TARGET_ID_OFFLINE", None); os.environ.pop("BIOMATE_OFFLINE", None)
        s = run(self.m.target_id_status())
        self.assertFalse(s["offline"])
        self.assertEqual({h["host"] for h in s["external_hosts"]}, {"api.platform.opentargets.org", "string-db.org"})
        self.assertIn("differential_expression_up", s["client_table_kinds"]); self.assertEqual(s["ranking_modes"], ["auto", "integrated"])
        os.environ["TARGET_ID_OFFLINE"] = "1"
        try:
            self.assertEqual(run(self.m.target_id_status())["external_hosts"], [])
        finally:
            os.environ.pop("TARGET_ID_OFFLINE", None)

    def test_server_paths_are_refused_without_a_table_root(self):
        os.environ.pop("TARGET_ID_TABLE_ROOT", None)
        with self.assertRaises(self.HTTPException) as cm:
            run(self.m.identify_targets(self.req(tables=[{"path": "/etc/passwd"}])))
        self.assertEqual(cm.exception.status_code, 400); self.assertIn("disabled", cm.exception.detail)

    def test_bad_client_table_and_bad_mode_are_400(self):
        for kw, frag in ((dict(client_tables=[{"kind": "nope", "rows": [{"gene": "A"}]}]), "unknown kind"),
                         (dict(client_tables=[{"kind": "dependency", "rows": [{"gene": "A", "x": 1}]}]), "columns not found"),
                         (dict(ranking_mode="fusion"), "ranking_mode")):
            with self.assertRaises(self.HTTPException) as cm:
                run(self.m.identify_targets(self.req(**kw)))
            self.assertEqual(cm.exception.status_code, 400); self.assertIn(frag, cm.exception.detail)

    def test_nothing_to_run_is_400(self):
        with self.assertRaises(self.HTTPException) as cm:
            run(self.m.identify_targets(self.req()))
        self.assertIn("no evidence channels", cm.exception.detail)

    def test_client_tables_rank_with_links_and_the_requested_mode(self):
        ct = [{"name": "tumour de", "kind": "differential_expression_up", "label": "NPC cohort", "rows": self.rows}]
        out = run(self.m.identify_targets(self.req(client_tables=ct)))
        self.assertEqual([t["target"] for t in out["targets"]][:2], ["BRAF", "TP53"])
        self.assertEqual(out["targets"][0]["evidence_links"]["client_tumour_de"]["kind"], "client_data")
        self.assertIn("NPC cohort", out["targets"][0]["evidence_links"]["client_tumour_de"]["label"])
        integrated = run(self.m.identify_targets(self.req(client_tables=ct, ranking_mode="integrated")))
        self.assertEqual(integrated["ranking"]["mode"], "weighted_harmonic_sum")
        self.assertNotIn("validation_plan", out)

    def test_validation_plan_is_attached_and_never_breaks_the_ranking(self):
        ct = [{"name": "tumour de", "kind": "differential_expression_up", "rows": self.rows}]
        out = run(self.m.identify_targets(self.req(client_tables=ct, validate=True, validate_top_n=1)))
        self.assertIn("validation_plan", out)           # a plan, or a clear error when the catalogue search is unavailable here
        self.assertEqual(out["targets"][0]["target"], "BRAF")

    def test_modality_suggestions_are_opt_in_guidance_and_never_break_the_ranking(self):
        from galaxy.ai.target_id import modality
        ct = [{"name": "tumour de", "kind": "differential_expression_up", "rows": self.rows}]
        off = run(self.m.identify_targets(self.req(client_tables=ct)))
        self.assertNotIn("modality_suggestions", off)
        orig = modality.fetch_features_for_symbol
        modality.fetch_features_for_symbol = lambda *a, **k: None   # UniProt unreachable -> soft per-target error
        try:
            out = run(self.m.identify_targets(self.req(client_tables=ct, suggest_modality=True, modality_top_n=1)))
        finally:
            modality.fetch_features_for_symbol = orig
        self.assertEqual(out["targets"][0]["target"], "BRAF")
        sug = out["modality_suggestions"]
        self.assertEqual(len(sug), 1)
        self.assertIs(sug[0]["validated"], False)
        self.assertIn("error", sug[0])

    def test_run_outputs_are_read_only_from_the_configured_folder(self):
        import tempfile
        os.environ.pop("TARGET_ID_RUN_OUTPUT_ROOT", None)
        with self.assertRaises(self.HTTPException) as cm:
            run(self.m.identify_targets(self.req(run_outputs=[{"path": "x.csv"}])))
        self.assertIn("disabled", cm.exception.detail)
        with tempfile.TemporaryDirectory() as root:
            with open(os.path.join(root, "deseq.csv"), "w") as fh:
                fh.write(",baseMean,log2FoldChange,padj\nBRAF,9,4,1e-20\nTP53,9,1,1e-3\n")
            os.environ["TARGET_ID_RUN_OUTPUT_ROOT"] = root
            try:
                self.assertTrue(run(self.m.target_id_status())["run_outputs_enabled"])
                out = run(self.m.identify_targets(self.req(run_outputs=[{"path": "deseq.csv", "label": "NPC DE", "source_run_id": "r1"}])))
                self.assertEqual(out["targets"][0]["target"], "BRAF")
                self.assertIn("NPC DE", out["targets"][0]["evidence_links"]["client_deseq"]["label"])
                with self.assertRaises(self.HTTPException) as cm:
                    run(self.m.identify_targets(self.req(run_outputs=[{"path": "../x.csv"}])))
                self.assertIn("outside the allowed folder", cm.exception.detail)
            finally:
                os.environ.pop("TARGET_ID_RUN_OUTPUT_ROOT", None)

    def test_the_audited_default_is_not_overridden(self):
        src = API.read_text()
        self.assertNotIn("arbiter=HarmonicSumArbiter()", src)
        self.assertNotIn("TableChannel(**request", src)


if __name__ == "__main__":
    unittest.main()
