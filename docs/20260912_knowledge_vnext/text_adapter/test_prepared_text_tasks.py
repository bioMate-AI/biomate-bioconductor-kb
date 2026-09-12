import unittest,tempfile,json
from pathlib import Path
import numpy as np
from text_encode_prepare import write_chunk
from prepared_text_tasks import iter_prepared_text
class Tests(unittest.TestCase):
 def test_cursor_and_hash(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);items=[{'gene_indices':[i],'provenance':{'article_id':str(i),'source_key':'s','token_count':2}} for i in range(5)];c=write_chunk(p,0,items,np.ones((5,3)));m=p/'manifest.json';m.write_text(json.dumps({'complete':True,'chunks':[c]}))
   allrows=list(iter_prepared_text(m,batch_rows=2));resume=list(iter_prepared_text(m,start_row=2,batch_rows=2));self.assertEqual([x['gene_indices'] for b,_,_ in resume for x in b],[[2],[3],[4]])
   self.assertEqual(allrows[0][2]['next_row'],2)
   (p/c['path']).write_bytes(b'changed')
   with self.assertRaisesRegex(ValueError,'hash'):list(iter_prepared_text(m))
 def test_incomplete_rejected(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'m.json';p.write_text(json.dumps({'complete':False,'chunks':[]}))
   with self.assertRaisesRegex(ValueError,'incomplete'):list(iter_prepared_text(p))
if __name__=='__main__':unittest.main()
