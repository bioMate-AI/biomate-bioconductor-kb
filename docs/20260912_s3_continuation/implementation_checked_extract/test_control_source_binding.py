import tempfile,unittest
from pathlib import Path
import h5py,numpy as np
from extract_controls import validate_source_binding

class Metadata(dict):
 @property
 def files(self):return list(self)

def fixture(h):
 m=Metadata(source_uri=np.array('bucket/key'),source_etag=np.array('etag'),source_size=np.array(123),indptr=np.array([0,1,2]),source_rows=np.array([0,1]),source_gene_symbols=np.array(['A','B']))
 x=h.create_group('X');x.attrs['encoding-type']='csr_matrix';x.create_dataset('indptr',data=m['indptr'])
 var=h.create_group('var');var.create_dataset('gene_name',data=np.array(['A','B'],dtype=h5py.string_dtype()))
 obs=h.create_group('obs')
 for k,v in {'_index':['c1','c2'],'donor_id':['d1','d2'],'culture_condition':['rest','rest'],'guide_id':['g1','g2'],'guide_type':['non-targeting','non-targeting'],'keep_for_DE':[True,True],'n_cells':[10,20],'total_counts':[100,200]}.items():
  m[k]=np.array(v);obs.create_dataset(k,data=np.array(v,dtype=h5py.string_dtype()) if isinstance(v[0],str) else v)
 return m

class TestBinding(unittest.TestCase):
 def test_unbound_or_changed_object_rejected_before_reads(self):
  with self.assertRaisesRegex(ValueError,'Unbound'):validate_source_binding(Metadata(),'bucket/key',{},None,np.array([0]))
  m=Metadata(source_uri=np.array('bucket/key'),source_etag=np.array('old'),source_size=np.array(123))
  with self.assertRaisesRegex(ValueError,'Source differs'):validate_source_binding(m,'bucket/key',{'ETag':'new','size':123},None,np.array([0]))
 def test_matching_metadata_then_stale_offsets_genes_rows(self):
  with tempfile.TemporaryDirectory() as td,h5py.File(Path(td)/'test.h5','w') as h:
   m=fixture(h);args=('bucket/key',{'ETag':'etag','size':123},h,np.array([0,1]))
   validate_source_binding(m,*args)
   m['indptr']=np.array([0,0,2])
   with self.assertRaisesRegex(ValueError,'CSR offsets'):validate_source_binding(m,*args)
   m['indptr']=np.array([0,1,2]);m['source_gene_symbols']=np.array(['B','A'])
   with self.assertRaisesRegex(ValueError,'gene schema'):validate_source_binding(m,*args)
   m['source_gene_symbols']=np.array(['A','B']);m['guide_id']=np.array(['g1','wrong'])
   with self.assertRaisesRegex(ValueError,'row metadata'):validate_source_binding(m,*args)
if __name__=='__main__':unittest.main()
