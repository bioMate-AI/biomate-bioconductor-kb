import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('legacy',Path(__file__).parents[1]/'training_data_extractor.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Tests(unittest.TestCase):
    def test_session_run_cannot_label_episode(self):
        row=m.build_full_example({'user_query':'question','assistant_response':'answer','outcome_success':True},
          {'id':'other-run','status':'completed','metrics':{'quality':1},'parameters':{'wrong':'value'}},None,.7)
        self.assertEqual(row['metadata']['outcome'],'unverified')
        self.assertIsNone(row['metadata']['quality_score'])
        self.assertIsNone(row['metadata']['parameters'])
        self.assertFalse(row['metadata']['training_eligible'])
    def test_no_fabricated_response(self):
        self.assertIsNone(m.build_full_example({'user_query':'question'}, {'status':'completed'},None,.7))
if __name__=='__main__':unittest.main()
