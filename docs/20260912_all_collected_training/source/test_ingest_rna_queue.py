import tempfile,unittest
from pathlib import Path
import numpy as np,pandas as pd,anndata as ad,scipy.sparse as sp
from ingest_rna_queue import run,split
class QueueTests(unittest.TestCase):
 def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.p=Path(self.tmp.name)
 def tearDown(self):self.tmp.cleanup()
 def fixture(self,name='a',primary=True):
  a=ad.AnnData(X=np.log1p([[1.,2.],[3.,4.]]),obs=pd.DataFrame({'donor_id':['d','d'],'is_primary_data':[primary]*2},index=['c1','c2']),var=pd.DataFrame(index=['ENSG1','ENSG2']))
  a.raw=ad.AnnData(X=sp.csr_matrix([[1.,2.],[3.,4.]]),obs=a.obs.copy(),var=a.var.copy());a.uns['citation']='Publication: https://doi.org/10.test/study Dataset Version: not-a-study'
  p=self.p/(name+'.h5ad');a.write_h5ad(p);uri='s3://bucket/base/'+name+'.h5ad';r={'uri':uri,'key':'base/'+name+'.h5ad','role':'rna','status':'candidate','etag':'fixture','bytes':p.stat().st_size};return a,p,r
 def test_full_rows_then_duplicate_source_excluded(self):
  _,p,r=self.fixture();_,q,s=self.fixture('b');m,rows=run({'objects':[r,s]},{'default':{'count_layer':'raw.X','count_provenance':'fixture native counts'}},self.p/'out',{r['uri']:str(p),s['uri']:str(q)},1)
  self.assertEqual(rows[0]['coverage']['written_cells'],2);self.assertEqual(rows[1]['coverage']['duplicate_excluded'],2);self.assertEqual(len(m['shards']),2);self.assertEqual(m['vocab'],['ENSG1','ENSG2']);self.assertEqual(m['shards'][0]['study_id'],'https://doi.org/10.test/study')
 def test_nonprimary_no_training(self):
  _,p,r=self.fixture(primary=False);m,rows=run({'objects':[r]},{'default':{'count_layer':'raw.X','count_provenance':'fixture'}},self.p/'out',{r['uri']:str(p)})
  self.assertFalse(m['training_ready']);self.assertEqual(rows[0]['coverage']['nonprimary_excluded'],2)
 def test_no_integer_guess_or_dataset_study_fallback(self):
  a,p,r=self.fixture();m,rows=run({'objects':[r]},{},self.p/'out',{r['uri']:str(p)})
  self.assertEqual(m['blocked_sources'],1);self.assertIn('provenance',rows[0]['error'])
  a.uns.clear();a.write_h5ad(p);m,rows=run({'objects':[r]},{'default':{'count_layer':'raw.X','count_provenance':'fixture'}},self.p/'out2',{r['uri']:str(p)})
  self.assertEqual(m['blocked_sources'],1);self.assertIn('dataset ID',rows[0]['error'])
 def test_invalid_source_rollback_preserves_later_valid_copy(self):
  a,p,r=self.fixture();a.X=np.array([[1.,2.],[.3,4.]]);a.write_h5ad(p);_,q,s=self.fixture('b')
  m,rows=run({'objects':[r,s]},{r['uri']:{'count_layer':'X','count_provenance':'invalid fixture'},s['uri']:{'count_layer':'raw.X','count_provenance':'valid fixture'}},self.p/'out',{r['uri']:str(p),s['uri']:str(q)},1)
  self.assertEqual(rows[0]['status'],'blocked_error');self.assertEqual(rows[1]['coverage']['written_cells'],2)
 def test_study_split_stable(self):self.assertEqual(split('study'),split('study'));self.assertIn(split('study'),['train','validation','test'])
if __name__=='__main__':unittest.main()
