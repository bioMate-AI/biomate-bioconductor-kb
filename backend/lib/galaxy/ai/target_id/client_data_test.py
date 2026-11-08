"""The hospital's own analysis results as an evidence channel: adapters, validation, weighting, ranking, path safety."""
import os
import tempfile
import unittest

from galaxy.ai.target_id import HarmonicSumArbiter, MockChannel, TargetIDOrchestrator, build_client_channels
from galaxy.ai.target_id.table_policy import safe_table_specs


def scores(kind, rows, **spec):
    ch = build_client_channels([dict(name="t", kind=kind, rows=rows, **spec)])[0]
    return ch.run({}).scores


class AdapterTests(unittest.TestCase):
    def test_differential_expression_up(self):
        s = scores("differential_expression_up", [
            {"gene": "A", "log2FoldChange": 2, "padj": 1e-5},     # 0.5 x 1.0
            {"gene": "B", "log2FoldChange": 8, "padj": 1e-10},    # capped at 1.0
            {"gene": "C", "log2FoldChange": -2, "padj": 1e-9},    # down-regulated: 0
            {"gene": "D", "log2FoldChange": 3, "padj": 0.5},      # not significant: 0
        ])
        self.assertAlmostEqual(s["A"], 0.5); self.assertAlmostEqual(s["B"], 1.0)
        self.assertEqual(s["C"], 0.0); self.assertEqual(s["D"], 0.0)

    def test_survival_recurrence_dependency_specificity_surface(self):
        self.assertAlmostEqual(scores("survival_adverse", [{"gene": "A", "HR": 1.5, "p": 1e-3}, {"gene": "B", "HR": 0.7, "p": 1e-4}])["A"], 0.6)
        self.assertEqual(scores("survival_adverse", [{"gene": "A", "HR": 1.5, "p": 1e-3}, {"gene": "B", "HR": 0.7, "p": 1e-4}])["B"], 0.0)
        r = scores("mutation_recurrence", [{"gene": "A", "frequency": 0.1}, {"gene": "B", "frequency": 15}, {"gene": "C", "frequency": 0.5}])
        self.assertAlmostEqual(r["A"], 0.5); self.assertAlmostEqual(r["B"], 0.75); self.assertEqual(r["C"], 1.0)
        d = scores("dependency", [{"gene": "A", "effect": -0.5}, {"gene": "B", "effect": 0.2}])
        self.assertAlmostEqual(d["A"], 0.5); self.assertEqual(d["B"], 0.0)
        c = scores("cell_type_specificity", [{"gene": "A", "tumour_fraction": 0.8, "normal_fraction": 0.1}, {"gene": "B", "tumour_fraction": 0.1, "normal_fraction": 0.6}])
        self.assertAlmostEqual(c["A"], 0.7); self.assertEqual(c["B"], 0.0)
        sf = scores("surface_expression", [{"gene": "A", "surface": "membrane"}, {"gene": "B", "surface": "false"}, {"gene": "C", "surface": 0.3}])
        self.assertEqual((sf["A"], sf["B"], sf["C"]), (1.0, 0.0, 0.3))

    def test_duplicate_genes_keep_the_best_score_and_symbols_are_normalised(self):
        s = scores("dependency", [{"gene": " braf ", "effect": -0.2}, {"gene": "BRAF", "effect": -0.9}])
        self.assertAlmostEqual(s["BRAF"], 0.9)

    def test_column_mapping_and_provenance(self):
        ch = build_client_channels([{"name": "NPC cohort", "kind": "dependency", "label": "NPC screen", "source_run_id": "run-7",
                                     "columns": {"gene": "symbol", "effect": "chronos"}, "rows": [{"symbol": "KRAS", "chronos": -0.8}]}])[0]
        r = ch.run({})
        self.assertEqual(ch.name, "client_npc_cohort"); self.assertEqual(r.evidence_kind, "client_data")
        self.assertEqual((r.provenance["n_rows"], r.provenance["n_scored"], r.provenance["source_run_id"]), (1, 1, "run-7"))
        self.assertIn("gene effect", r.provenance["adapter"])


class ValidationTests(unittest.TestCase):
    def check(self, spec, fragment):
        with self.assertRaises(ValueError) as cm:
            build_client_channels([spec])
        self.assertIn(fragment, str(cm.exception))

    def test_actionable_errors(self):
        self.check({"kind": "nope", "rows": [{"gene": "A"}]}, "unknown kind")
        self.check({"kind": "dependency", "rows": []}, "non-empty list")
        self.check({"kind": "dependency", "rows": [{"gene": "A", "wrong": 1}]}, "Present: ['gene', 'wrong']")
        self.check({"kind": "dependency", "rows": [{"gene": "A", "effect": 0.3}]}, "no gene received a positive score")
        with self.assertRaises(ValueError):
            build_client_channels([{"kind": "dependency", "rows": [{"gene": "A", "effect": -1}, {"gene": "B", "effect": -1}]}], max_rows=1)
        with self.assertRaises(ValueError):
            build_client_channels([{"name": "x", "kind": "dependency", "rows": [{"gene": "A", "effect": -1}]}] * 2)


class RankingTests(unittest.TestCase):
    def _channels(self):
        ot = MockChannel("genetics_ot", {"A": 0.9, "B": 0.6})
        client = build_client_channels([{"name": "de", "kind": "dependency", "rows": [{"gene": "A", "effect": 0.0}, {"gene": "B", "effect": -1.0}]}])
        return ot, client

    def test_default_keeps_open_targets_order_but_shows_the_client_corroboration(self):
        ot, client = self._channels()
        res = TargetIDOrchestrator([ot] + client).identify("q").to_dict()
        self.assertEqual([t["target"] for t in res["targets"]], ["A", "B"])
        b = res["targets"][1]
        self.assertIn("client_de", b["fired_channels"])
        self.assertEqual(b["tier"], "corroborated")

    def test_integrated_mode_lets_the_hospital_data_change_the_ranking(self):
        ot, client = self._channels()
        res = TargetIDOrchestrator([ot] + client, arbiter=HarmonicSumArbiter(primary_channel=None)).identify("q").to_dict()
        self.assertEqual(res["ranking"]["mode"], "weighted_harmonic_sum")
        self.assertEqual([t["target"] for t in res["targets"]], ["B", "A"])   # client evidence lifts B above A

    def test_client_channels_get_the_client_weight_and_it_can_be_overridden(self):
        self.assertEqual(HarmonicSumArbiter()._weight("client_anything"), 0.8)
        self.assertEqual(HarmonicSumArbiter(channel_weights={"client_*": 0.3})._weight("client_x"), 0.3)
        self.assertEqual(HarmonicSumArbiter(channel_weights={"client_x": 1.0})._weight("client_x"), 1.0)


class TablePolicyTests(unittest.TestCase):
    def test_server_paths_are_confined_to_the_configured_root(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as outside:
            open(os.path.join(root, "ok.csv"), "w").write("target,score\nA,1\n")
            secret = os.path.join(outside, "secret.csv"); open(secret, "w").write("x")
            os.symlink(secret, os.path.join(root, "link.csv"))
            good = safe_table_specs([{"path": "ok.csv", "name": "d", "reader": lambda p: [], "evil": 1}], root=root)
            self.assertEqual(good[0]["path"], os.path.realpath(os.path.join(root, "ok.csv")))
            self.assertNotIn("reader", good[0]); self.assertNotIn("evil", good[0])
            for bad in ("../" + os.path.basename(outside) + "/secret.csv", secret, "/etc/passwd", "link.csv"):
                with self.assertRaises(ValueError, msg=bad):
                    safe_table_specs([{"path": bad}], root=root)

    def test_disabled_without_a_root(self):
        os.environ.pop("TARGET_ID_TABLE_ROOT", None)
        with self.assertRaises(ValueError) as cm:
            safe_table_specs([{"path": "/etc/passwd"}])
        self.assertIn("disabled", str(cm.exception))
        self.assertEqual(safe_table_specs(None), [])


if __name__ == "__main__":
    unittest.main()
