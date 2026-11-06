"""The general QC gate engine evaluates workflow-DECLARED gates for ANY domain,
with no per-process hardcoding — the general counterpart to qc_trace_monitor's
if/elif chains. A brand-new domain gets real pass/advisory/halt gates purely from
data it declares."""
import unittest

from galaxy.ai.qc_gate_engine import (
    evaluate_gates, parse_gate_specs, GateSpec, GateSpecError, HALT, ADVISORY, PASS,
)


class GeneralQCGateTest(unittest.TestCase):
    def test_declared_gates_classify_pass_advisory_halt(self):
        declared = [
            {"name": "read_depth", "metric": "read_depth", "op": ">=", "threshold": 20,
             "severity": "halt", "evidence": "ENCODE post-2020", "provenance": "standard"},
            {"name": "mapping_rate", "metric": "mapping_rate", "op": ">=", "threshold": 0.7,
             "severity": "advisory", "provenance": "literature"},
            {"name": "batch_effect", "metric": "batch_effect", "op": "<=", "threshold": 0.3,
             "severity": "halt", "provenance": "institutional"},
        ]
        metrics = {"read_depth": 25, "mapping_rate": 0.6, "batch_effect": 0.5}
        rep = evaluate_gates(declared, metrics)
        by = {r.metric: r for r in rep.results}
        self.assertEqual(by["read_depth"].action, PASS)       # 25 >= 20
        self.assertEqual(by["mapping_rate"].action, ADVISORY) # 0.6 < 0.7, advisory severity
        self.assertEqual(by["mapping_rate"].action_zh, "提醒")
        self.assertEqual(by["batch_effect"].action, HALT)     # 0.5 > 0.3, halt severity
        self.assertEqual(by["batch_effect"].action_zh, "中止")
        self.assertTrue(rep.blocked)                          # a halt gate failed
        self.assertEqual(rep.n_halt, 1)
        self.assertEqual(rep.n_advisory, 1)
        # provenance / evidence carried through for the UI
        self.assertEqual(by["read_depth"].evidence, "ENCODE post-2020")
        self.assertEqual(by["read_depth"].provenance, "standard")

    def test_brand_new_domain_gets_gates_from_data_only(self):
        # metric names the hardcoded chains never heard of — still evaluated.
        declared = [{"metric": "glycan_occupancy_pct", "op": ">=", "threshold": 80, "severity": "halt"}]
        self.assertTrue(evaluate_gates(declared, {"glycan_occupancy_pct": 92}).results[0].passed)
        self.assertTrue(evaluate_gates(declared, {"glycan_occupancy_pct": 50}).blocked)

    def test_missing_metric_is_not_evaluated_not_crash(self):
        rep = evaluate_gates([{"metric": "spotless", "op": ">=", "threshold": 1}], {})
        self.assertEqual(rep.results[0].action, "not_evaluated")
        self.assertIsNone(rep.results[0].passed)
        self.assertFalse(rep.blocked)                         # absent != failed
        self.assertEqual(rep.n_not_evaluated, 1)

    def test_all_operators(self):
        for op, thr, val, ok in [("<", 5, 4, True), ("<", 5, 6, False), ("==", 3, 3, True),
                                 ("!=", 3, 3, False), (">", 0, 1, True), ("<=", 2, 2, True)]:
            rep = evaluate_gates([{"metric": "m", "op": op, "threshold": thr}], {"m": val})
            self.assertEqual(rep.results[0].passed, ok, f"{val} {op} {thr}")

    def test_parse_accepts_aliases_and_dict_form(self):
        # dict-of-name form + alias keys (operator/limit/action/citation/source)
        specs = parse_gate_specs({
            "fsc_resolution": {"operator": "<=", "limit": 4.0, "action": "block",
                               "citation": "Henderson 2012", "source": "literature"},
        })
        self.assertEqual(len(specs), 1)
        s = specs[0]
        self.assertEqual((s.metric, s.op, s.threshold, s.severity), ("fsc_resolution", "<=", 4.0, HALT))
        self.assertEqual(s.evidence, "Henderson 2012")

    def test_zh_severity_aliases(self):
        specs = parse_gate_specs([{"metric": "x", "op": ">=", "threshold": 1, "severity": "提醒"}])
        self.assertEqual(specs[0].severity, ADVISORY)

    def test_bad_spec_raises(self):
        with self.assertRaises(GateSpecError):
            parse_gate_specs([{"metric": "x", "op": "≈", "threshold": 1}])      # unknown op
        with self.assertRaises(GateSpecError):
            parse_gate_specs([{"metric": "x", "op": ">=", "severity": "halt"}])  # no threshold


if __name__ == "__main__":
    unittest.main()
