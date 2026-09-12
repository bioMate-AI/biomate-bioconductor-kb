import unittest
from prepare_episodes import prepare

def record(i, group, text, split=None):
    return {'task_id':'T12','record_id':i,'source_groups':[group],'training_rights':'approved','review_status':'accepted',
      'verifier_evidence':[{'passed':True,'evidence_ref':'fixture://checked'}],'prompt_sha256':'fixture-hash',
      'application_commit':'fixture-commit','context_complete':True,
      'messages':[{'role':'user','content':'question'},{'role':'assistant','content':text}],**({'split':split} if split else {})}
class Tests(unittest.TestCase):
    def test_prevents_duplicate_content_leakage(self):
        with self.assertRaisesRegex(ValueError,'leakage'):
            prepare([record('1','a','same','train'),record('2','b','same','test')])
    def test_transitive_lineage(self):
        a=record('1','a','one','train');b=record('2','b','two');b['source_groups']=['a','b'];c=record('3','b','three','test')
        with self.assertRaisesRegex(ValueError,'leakage'):prepare([a,b,c])
    def test_requires_evidence_and_context(self):
        a=record('1','a','one');a['context_complete']=False
        pools,rejected=prepare([a]);self.assertEqual(sum(map(len,pools.values())),0);self.assertEqual(len(rejected),1)
    def test_excludes_ind_training(self):
        for task in ['T22','T23',None]:
            row=record('1','a','one');row['task_id']=task
            pools,rejected=prepare([row])
            self.assertEqual(sum(map(len,pools.values())),0)
            self.assertIn('IND excluded',rejected[0]['reason'])
    def test_deduplicates(self):
        pools,rejected=prepare([record('1','a','same'),record('2','b','same')]);self.assertEqual(sum(map(len,pools.values())),1)
if __name__=='__main__':unittest.main()
