import tempfile,unittest,json
from pathlib import Path
import numpy as np,h5py
from prepare_czi_h1 import prepare
class CZI(unittest.TestCase):
 def fixture(self,path):
  # Two donors, each with 2 NT guides and 1 targeting guide.
  x=np.array([[5,5,0],[4,6,0],[1,7,2],[10,0,0],[8,2,0],[2,6,2]],np.int64)
  with h5py.File(path,'w') as h:
   g=h.create_group('X');g.attrs['encoding-type']='csr_matrix';g.attrs['shape']=x.shape
   data=[];indices=[];ptr=[0]
   for row in x:
    ix=np.flatnonzero(row);data.extend(row[ix]);indices.extend(ix);ptr.append(len(data))
   g['data']=data;g['indices']=indices;g['indptr']=ptr;o=h.create_group('obs');v=h.create_group('var');string=h5py.string_dtype()
   cols={'donor_id':['D1']*3+['D2']*3,'culture_condition':['Rest']*6,'guide_type':['non-targeting','non-targeting','targeting']*2,'guide_id':['NT1','NT2','A1']*2,'perturbed_gene_name':['NT','NT','A']*2}
   for k,a in cols.items():o.create_dataset(k,data=np.array(a,dtype=object),dtype=string)
   for k in ['keep_min_cells','keep_total_counts']:o[k]=np.ones(6,bool)
   o['n_cells']=np.ones(6,np.int64)*100;o['total_counts']=x.sum(1)
   v.create_dataset('_index',data=np.array(['ENSG1','ENSG2','ENSG3'],object),dtype=string);v.create_dataset('gene_name',data=np.array(['A','B','C'],object),dtype=string)
  return x
 def test_allgenes_control_delta_and_donor_isolation(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td);x=self.fixture(p/'source.h5ad');m=prepare(str(p/'source.h5ad'),p/'out',{'D1':'train','D2':'test'})
   self.assertEqual(len(m['measured_sources']),2);self.assertEqual(len(m['vocab']),3);self.assertEqual(m['unsupported'],[])
   pools=m['metadata']['control_pools'];ref=0 if pools['NT1']=='reference' else 1
   for i,entry in enumerate(m['measured_sources']):
    with np.load(p/'out'/entry['path']) as z:
     expected=np.log1p(x[i*3+2]/10*1e4)-np.log1p(x[i*3+ref]/10*1e4);np.testing.assert_allclose(z['h1_delta'][0],expected,rtol=1e-6);self.assertFalse(z['h1_observed'][0,0]);self.assertTrue(z['h1_observed'][0,1:].all())
   with h5py.File(p/'source.h5ad','r+') as h:h['X/data'][-1]=99
   with self.assertRaisesRegex(ValueError,'total disagrees'):prepare(str(p/'source.h5ad'),p/'bad',{'D1':'train','D2':'test'})
 def test_metadata_only_never_reads_count_data(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td);self.fixture(p/'source.h5ad')
   with h5py.File(p/'source.h5ad','r+') as h:del h['X/data'];del h['X/indices']
   result=prepare(str(p/'source.h5ad'),p/'meta',{'D1':'train','D2':'test'},metadata_only=True);self.assertEqual(result['genes'],3);self.assertFalse((p/'meta/manifest.json').exists())
if __name__=='__main__':unittest.main()
