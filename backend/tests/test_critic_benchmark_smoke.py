"""
Smoke test for the critic_benchmark harness (python3.9, stdlib unittest).

Asserts the harness runs end-to-end on the synthetic labeled set and emits a results
table with the four shipping metrics, that a known true-positive injector IS caught,
and that a known hard-negative is NOT flagged.

Run:
    python3.9 -m pytest backend/tests/test_critic_benchmark_smoke.py
    python3.9 backend/tests/test_critic_benchmark_smoke.py          # direct
"""
import os
import sys
import unittest

# Make both the critics import root (backend/lib) and the evaluation package root
# (backend) importable regardless of where the test is invoked from.
_BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _p in (_BACKEND, os.path.join(_BACKEND, "lib")):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from evaluation.critic_benchmark.injectors import generate_items
from evaluation.critic_benchmark.stub_critics import build_registry
from evaluation.critic_benchmark.harness import harness_predictions
from evaluation.critic_benchmark import score as score_mod


class CriticBenchmarkSmoke(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.items = generate_items(n_per_class=5)
        cls.registry = build_registry()
        cls.preds = harness_predictions(cls.items, registry=cls.registry)
        cls.result = score_mod.score(cls.items, cls.preds)
        cls.pred_by_id = {p["id"]: p for p in cls.preds}

    # ── the set is well-formed ────────────────────────────────────────────────
    def test_registry_has_real_and_stub_critics(self):
        ids = {c.critic_id for c in self.registry.all()}
        self.assertIn("survival.confounding", ids)        # real
        self.assertIn("power.epv", ids)                   # WS2 real (swapped in)
        self.assertIn("output.presence", ids)             # WS2 real (swapped in)
        self.assertIn("qc.metric_floor", ids)             # stub (no real critic yet)

    def test_five_archetypes_scored(self):
        self.assertEqual(self.result["n_archetypes"], 5)
        self.assertEqual(len(self.result["per_archetype"]), 5)

    # ── results table carries the four shipping metrics, per archetype ────────
    def test_four_metrics_present(self):
        for arch, a in self.result["per_archetype"].items():
            for metric in ("precision", "recall",
                           "false_alarm_rate", "harmful_remediation_rate"):
                self.assertIn(metric, a, f"{arch} missing {metric}")
            self.assertIn("gate", a)
            self.assertIn("qualified_tier", a["gate"])

    # ── a known true-positive injector is CAUGHT ──────────────────────────────
    def test_true_positive_caught(self):
        pid = "design.confounding|positive|000"
        self.assertTrue(self.pred_by_id[pid]["fired_target"],
                        "survival.confounding must fire on an injected real confounder")
        conf = self.result["per_archetype"]["design.confounding"]
        self.assertEqual(conf["recall"], 1.0)  # every injected confounder detected

    def test_batch_positive_caught(self):
        pid = "design.batch_imbalance|positive|000"
        self.assertTrue(self.pred_by_id[pid]["fired_target"],
                        "rnaseq.imbalanced_confounding must fire on injected batch imbalance")

    # ── a known hard-negative is NOT flagged ──────────────────────────────────
    def test_hard_negative_not_flagged(self):
        pid = "design.batch_imbalance|hard_negative|000"
        self.assertFalse(self.pred_by_id[pid]["fired_target"],
                         "a BALANCED covariate (not a confounder) must NOT fire")
        batch = self.result["per_archetype"]["design.batch_imbalance"]
        self.assertEqual(batch["false_alarm_rate"], 0.0)
        self.assertEqual(batch["harmful_remediation_rate"], 0.0)

    def test_epv_hard_negative_not_flagged(self):
        pid = "power.epv|hard_negative|000"
        self.assertFalse(self.pred_by_id[pid]["fired_target"],
                         "EPV just above the floor must NOT fire (no boundary over-flagging)")

    # ── the harmful-remediation hard gate is wired and measures the known weak
    #    survival-confounding critic on the mediator hard-negative (honest finding) ─
    def test_mediator_is_a_measured_harmful_remediation(self):
        pid = "design.confounding|hard_negative|000"
        pred = self.pred_by_id[pid]
        self.assertTrue(pred["fired_target"],
                        "the p<0.05-only critic DOES fire on a mediator (Table-2 fallacy)")
        self.assertEqual(pred["target_remediation_kind"], "add_covariate")
        conf = self.result["per_archetype"]["design.confounding"]
        self.assertGreater(conf["harmful_remediation_rate"], 0.0)
        self.assertFalse(conf["gate"]["hard_gate_pass"],
                         "harmful-remediation hard gate must BLOCK this critic")

    # ── the correctly-designed critics pass all gates ─────────────────────────
    def test_well_designed_critics_ship(self):
        for arch in ("design.batch_imbalance", "power.epv", "qc.threshold", "output.presence"):
            g = self.result["per_archetype"][arch]["gate"]
            self.assertTrue(g["ships"], f"{arch} should ship: {g['reasons']}")

    def test_print_table_runs(self):
        # The runner's results table renders without error (4 metrics + ships column).
        score_mod.print_table(self.result)


if __name__ == "__main__":
    unittest.main(verbosity=2)
