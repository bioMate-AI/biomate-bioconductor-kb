import unittest
import pandas as pd
import torch
from knowledge_tasks import KnowledgeTasks,load_knowledge
class TestKnowledge(unittest.TestCase):
 def facts(self):
  return pd.DataFrame([['a','relation','gene/protein','A','gene/protein','B','regulates',None,True,1.,'g1'],['a','sign','gene/protein','A','gene/protein','B','regulates',-1.,False,1.,'g1'],['p','membership','gene/protein','A','pathway','P','member_of',None,True,1.,'g2'],['g','prior','gene/protein','B','disease','D','prior',.4,True,1.,'g3']],columns=['source','task','left_type','left','right_type','right','relation','value','value_observed','confidence','split_group'])
 def test_shared_gradient_and_exposure(self):
  f=self.facts();e=torch.nn.Embedding(5,8);m=KnowledgeTasks(f,e,gene_to_index={'A':1,'B':3});loss,parts,c=m(f,heldout_groups=[]);loss.backward();self.assertGreater(e.weight.grad.abs().sum().item(),0);self.assertEqual(c['inferred_sign_rows_skipped'],1);self.assertNotIn('sign',parts);self.assertEqual(m.exposure,{});self.assertEqual(m.record_optimizer_step(c)['a'],1)
 def test_holdout_rejected(self):
  f=self.facts();m=KnowledgeTasks(f,torch.nn.Embedding(2,4),['A','B'])
  with self.assertRaisesRegex(ValueError,'Held-out'):m(f,heldout_groups=['g1'])
 def test_inferred_sign_mutation(self):
  f=self.facts();m=KnowledgeTasks(f,torch.nn.Embedding(2,4),['A','B']);a=m(f,heldout_groups=[])[0];f.loc[1,'value']=float('nan');b=m(f,heldout_groups=[])[0];torch.testing.assert_close(a,b)
 def test_current_artifact_catalogs_uncapped(self):
  p='/Users/kky/biomate-review/docs/20260912_knowledge_vnext/current_prepared';f=load_knowledge(p)
  self.assertEqual(int(f.source.eq('reactome').sum()),142657);self.assertEqual(int(f.source.eq('go_bp').sum()),627225)
  self.assertEqual(int((f.task.eq('prior')).sum()),1842);self.assertEqual(f[f.task.eq('prior')].right.nunique(),9)
  self.assertEqual(int((f.task.eq('sign')&f.value_observed).sum()),19396)
if __name__=='__main__':unittest.main()
