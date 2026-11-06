import unittest,tempfile,json
from pathlib import Path
import numpy as np,pandas as pd,anndata as ad,scipy.sparse as sp,h5py
from preflight_all_source_headers import inspect_handle,execute,fingerprint
from bridge_rna_joint_tokens import bridge
from ingest_rna_queue import sha
class HeaderBridgeTests(unittest.TestCase):
 def setUp(self):self.t=tempfile.TemporaryDirectory();self.p=Path(self.t.name)
 def tearDown(self):self.t.cleanup()
 def fixture(self):
  a=ad.AnnData(X=np.ones((2,2)),obs=pd.DataFrame({'is_primary_data':[True,False],'donor_id':['d','d']},index=['c1','c2']),var=pd.DataFrame(index=['A','B']));a.raw=a.copy();a.var['feature_is_filtered']=[True,False];a.uns.update(schema_version='7.1.0',citation='Publication: https://doi.org/test/study')
  p=self.p/'a.h5ad';a.write_h5ad(p);r={'uri':'s3://b/a.h5ad','key':'a.h5ad','role':'rna','status':'candidate'};policy={'schema_policies':{'7.1.0':{'count_layer':'raw.X','provenance_reference':'official schema','feature_filter_semantics':'normalized_X_only'}}};return p,r,policy
 def test_header_complete_accounting_and_raw_filter_semantics(self):
  p,r,policy=self.fixture();m=execute({'objects':[r]},policy,self.p/'headers',local_paths={r['uri']:str(p)},paired_schema={'vocab':['protein:P']})
  self.assertEqual(m['sources'][0]['status'],'header_eligible_counts_unvalidated');self.assertEqual(m['sources'][0]['primary_cells'],1);self.assertEqual(m['vocab'],['RNA:A','RNA:B','protein:P']);self.assertFalse(m['training_ready'])
 def test_header_only_reads_required_metadata_columns(self):
  from unittest.mock import patch
  import preflight_all_source_headers as module
  p,r,policy=self.fixture()
  with h5py.File(p,'a') as h:
   # A large irrelevant column must never be materialized by the inspector.
   h['obs'].create_dataset('irrelevant_large',data=np.ones((2,100)))
  original=module.read_elem;seen=[]
  def spy(elem,*args,**kwargs):
   seen.append(elem.name);return original(elem,*args,**kwargs)
  with h5py.File(p) as h,patch.object(module,'read_elem',spy):x=inspect_handle(h,r,policy)
  self.assertEqual(x['source_cells'],2);self.assertNotIn('/obs',seen);self.assertNotIn('/var',seen);self.assertNotIn('/obs/irrelevant_large',seen);self.assertNotIn('/obs/_index',seen)
 def test_unknown_schema_blocked_with_features_retained(self):
  p,r,_=self.fixture()
  with h5py.File(p) as h:x=inspect_handle(h,r,{})
  self.assertEqual(x['status'],'blocked');self.assertEqual(x['feature_ids'],['A','B'])
 def test_bridge_all_zeros_and_features_and_hash(self):
  p=self.p/'counts.npz';sp.save_npz(p,sp.csr_matrix([[0,2,0],[3,0,4]]));s={'path':str(p),'sha256':sha(p),'gene_ids':['A','B','C'],'rows':2,'source_uri':'source','study_id':'study','split':'train'};v=['RNA:A','RNA:B','RNA:C','protein:P'];root={'vocab':v,'vocab_sha256':fingerprint(v)}
  m=bridge({'shards':[s]},root,self.p/'bridge',2,1);self.assertEqual(sum(x['written_tokens'] for x in m['coverage']),6)
  total=zero=0
  for b in m['streams']:
   with np.load(b['path']) as z:total+=z['valid'].sum();zero+=((z['values']==0)&z['valid']).sum();self.assertTrue((z['modality']==0).all())
  self.assertEqual(total,6);self.assertEqual(zero,3)
  s['sha256']='bad'
  with self.assertRaisesRegex(ValueError,'hash mismatch'):bridge({'shards':[s]},root,self.p/'bad')
if __name__=='__main__':unittest.main()
