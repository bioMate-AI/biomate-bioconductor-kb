import json
import unittest
from backend_bakeoff import ADMET_PATH, TASKS
from eval_grounded_workflows import check_decision

class DecisionContractTests(unittest.TestCase):
    def setUp(self):
        self.task = TASKS[0]
        self.facts = {name: {'smiles': str(i), 'source_url': 'https://example.test'}
                      for i, name in enumerate(self.task['compound_names'])}
        self.decision = {'nextflow_path': ADMET_PATH, 'params': {'smiles_list': '["0", "1", "2"]'}}

    def test_valid_grounded_decision(self):
        self.assertEqual(check_decision(json.dumps(self.decision), self.task, self.facts)[1], [])

    def test_duplicate_cannot_replace_missing_compound(self):
        self.decision['params']['smiles_list'] = '["0", "0", "2"]'
        self.assertIn('compound evidence mismatch', check_decision(json.dumps(self.decision), self.task, self.facts)[1])

    def test_wrong_workflow_or_extra_prose_fails(self):
        self.decision['nextflow_path'] = 'invented.nf'
        self.assertIn('wrong workflow', check_decision(json.dumps(self.decision), self.task, self.facts)[1])
        self.assertTrue(check_decision('Here: ' + json.dumps(self.decision), self.task, self.facts)[1])
