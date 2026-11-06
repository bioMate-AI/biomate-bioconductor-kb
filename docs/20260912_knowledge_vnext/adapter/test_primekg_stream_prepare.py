import io,gzip,unittest
from primekg_stream_prepare import typed_chunks
class Test(unittest.TestCase):
 def test_all_chunks_typed_reverse_group(self):
  s='relation,x_id,x_type,x_name,x_source,y_id,y_type,y_name,y_source\nr,1,drug,A,DB,2,gene/protein,B,NCBI\nr,2,gene/protein,B,NCBI,1,drug,A,DB\n'
  c=list(typed_chunks(io.BytesIO(gzip.compress(s.encode())),1));self.assertEqual(len(c),2);self.assertEqual(c[0].iloc[0].split_group,c[1].iloc[0].split_group);self.assertNotEqual(c[0].iloc[0].record_id,c[1].iloc[0].record_id)
if __name__=='__main__':unittest.main()
