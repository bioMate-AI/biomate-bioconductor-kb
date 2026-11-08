import unittest
from collections import Counter
import numpy as np,torch
from text_knowledge_tasks import windows,FrozenTextAlignment
class Tok:
 def encode(self,s,**kwargs):return s.split()
 def decode(self,t,**kwargs):return ' '.join(t)
class Tests(unittest.TestCase):
 def item(self):return {'record':{'pmcid':'PMC1','title':'A title','abstract':'A abstract','body':'B body A ending','license_href':'test-license'},'raw_sha256':'x','source_key':'s','source_etag':'e','row':0}
 def test_full_body_and_no_per_gene_cap(self):
  x=self.item();x['record']['body']=' '.join(['A body']*20);l=Counter();w=list(windows(x,Tok(),{'A':0,'B':1},2,l));self.assertEqual(sum(z['provenance']['token_count'] for z in w),44);self.assertGreater(len(w),6);self.assertEqual(w[-1]['text'],'A body');self.assertEqual(w[0]['provenance']['license_href'],'test-license')
 def test_holdout_and_nohit_ledger(self):
  l=Counter();self.assertEqual(list(windows(self.item(),Tok(),{'A':0},2,l,{'PMC1'})),[]);self.assertEqual(l['heldout_articles'],1)
  w=list(windows(self.item(),Tok(),{},2,l));self.assertEqual(l['windows_without_mapped_gene'],len(w))
 def test_shared_gradient_and_explicit_exposure(self):
  w=list(windows(self.item(),Tok(),{'A':0,'B':1},4,Counter()));m=FrozenTextAlignment(torch.nn.Embedding(2,4),3);loss,c=m(w,lambda text:np.ones((len(text),3)),heldout_article_ids=set());loss.backward();self.assertGreater(m.gene_embedding.weight.grad.abs().sum().item(),0);self.assertEqual(m.exposure,{});self.assertEqual(m.record_optimizer_step(c)['s'],len(w))
if __name__=='__main__':unittest.main()
