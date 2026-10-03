import unittest
from backend_bakeoff import TASKS, prompt_for, resolved_for


class GroundedBakeoffTests(unittest.TestCase):
    def test_missing_evidence_cannot_fall_back_to_model_memory(self):
        with self.assertRaisesRegex(ValueError, "Missing resolved"):
            prompt_for(TASKS[0], {})

    def test_both_backends_get_identical_verbatim_resolver_facts(self):
        # Synthetic strings test propagation, not chemical validity.
        facts = {name: {"smiles": f"fixture_{i}", "source_url": f"https://example.test/{i}"}
                 for i, name in enumerate(TASKS[0]["compound_names"])}
        prompt = prompt_for(TASKS[0], facts)
        for row in resolved_for(TASKS[0], facts):
            self.assertIn(row["smiles"], prompt)
            self.assertIn(row["source_url"], prompt)
        self.assertNotIn("your chemical knowledge", prompt)
        self.assertEqual(prompt, prompt_for(TASKS[0], facts))
