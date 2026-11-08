import unittest,tempfile
from pathlib import Path
import anndata as ad,pandas as pd,numpy as np,scipy.sparse as sp
from tokenize_paired_sources import tokenize
class PairedTests(unittest.TestCase):
 def setUp(self):self.t=tempfile.TemporaryDirectory();self.p=Path(self.t.name)
 def tearDown(self):self.t.cleanup()
 def fixture(self,kind):
  a=ad.AnnData(X=sp.csr_matrix([[0,2,1],[3,0,1]]),obs=pd.DataFrame({'study':['study']*2},index=['c1','c2']),var=pd.DataFrame(index=['A','B','C']));a.layers['counts']=a.X.copy()
  other=np.array([[0,4],[2,0]])
  if kind=='protein':a.obsm['protein_expression']=other;a.uns['protein_names']=['P1','P2']
  else:a.obsm['atac_peaks']=sp.csr_matrix(other);a.uns.update(atac_peak_names=['chr1:1-2','chr1:3-4'],atac_repr='peak_counts',genome_build='GRCh38')
  p=self.p/(kind+'.h5ad');a.write_h5ad(p);return a,dict(path=str(p),source_id=kind,study_id='study',split='train',count_provenance='fixture',pairing_provenance='same-row fixture',donor_id='d',modality=kind)
 def test_all_cells_features_zeros_and_padding(self):
  _,c=self.fixture('protein');m=tokenize([c],self.p/'out',3,1)
  self.assertEqual(m['sources'][0]['observed_token_entries'],10);self.assertEqual(len(m['streams']),4)
  total=zeros=0
  for stream in m['streams']:
   with np.load(stream['path']) as z:total+=z['valid'].sum();zeros+=((z['values']==0)&z['valid']).sum();self.assertEqual(z['ids'].shape,(1,3))
  self.assertEqual(total,10);self.assertEqual(zeros,4)
 def test_atac_binary_and_namespaced_intervals(self):
  _,c=self.fixture('ATAC');m=tokenize([c],self.p/'out',8,2)
  self.assertIn('ATAC:GRCh38:chr1:1-2',m['vocab'])
  with np.load(m['streams'][0]['path']) as z:np.testing.assert_array_equal(np.unique(z['values'][(z['modality']==2)&z['valid']]),[0,1])
 def test_invalid_assay_and_split_leakage(self):
  a,c=self.fixture('protein');a.obsm['protein_expression'][0,0]=-1;a.write_h5ad(c['path'])
  with self.assertRaisesRegex(ValueError,'Invalid native'):tokenize([c],self.p/'out')
  self.assertFalse((self.p/'out').exists())
  _,c=self.fixture('protein');_,d=self.fixture('ATAC');d['split']='test'
  with self.assertRaisesRegex(ValueError,'across splits'):tokenize([c,d],self.p/'out')
if __name__=='__main__':unittest.main()
