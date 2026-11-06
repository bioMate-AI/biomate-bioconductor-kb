import json,subprocess,sys,tempfile,unittest
from pathlib import Path
import numpy as np
import scipy.sparse as sp
import torch
from train_streaming_rna import read_manifest,batches,RNAEncoder,masked_loss
class Streaming(unittest.TestCase):
 def setUp(self):
  self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup);self.p=Path(self.t.name);torch.set_num_threads(1)
  sp.save_npz(self.p/'one.npz',sp.csr_matrix(np.array([[0,3,1],[2,0,5],[0,0,0]],dtype=np.int64)))
  self.manifest={'training_ready':True,'vocab':['A','B','C'],'shards':[{'path':'one.npz','study_id':'study1','split':'train','gene_ids':['B','A','C']}]};self.path=self.p/'manifest.json';self.path.write_text(json.dumps(self.manifest))
 def test_stream_mapping_and_loss(self):
  m=read_manifest(self.path);bs=list(batches(m,'train',1,3,0,0));self.assertEqual(len(bs),2)
  for ids,val,mask in bs:
   self.assertTrue((mask.sum(1)==2).all());self.assertTrue(torch.isfinite(val).all())
  model=RNAEncoder(3,16,1,4);loss,n=masked_loss(model,bs[0]);loss.backward();self.assertTrue(torch.isfinite(loss));self.assertGreater(n,0)
 def test_study_leakage_rejected(self):
  self.manifest['shards'].append(dict(self.manifest['shards'][0],split='test'));self.path.write_text(json.dumps(self.manifest))
  with self.assertRaisesRegex(ValueError,'Study leakage'):read_manifest(self.path)
 def test_cli_smoke(self):
  result=subprocess.run([sys.executable,str(Path(__file__).with_name('train_streaming_rna.py')),'--manifest',str(self.path),'--out',str(self.p/'run'),'--epochs','1','--batch','1','--max-tokens','3','--dim','16','--layers','1','--heads','4','--max-steps','1'],capture_output=True,text=True)
  self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(json.loads((self.p/'run/status.json').read_text())['status'],'integration_cap_reached');self.assertTrue((self.p/'run/checkpoint.pt').exists())
if __name__=='__main__':unittest.main()
