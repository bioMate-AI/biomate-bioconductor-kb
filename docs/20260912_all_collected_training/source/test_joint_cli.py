import json,os,subprocess,sys,tempfile,unittest
from pathlib import Path
import numpy as np
class CLI(unittest.TestCase):
 def test_real_mode_enumerates_every_feature_window(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td);np.savez(p/'dense.npz',values=np.arange(21,dtype=np.float32).reshape(3,7),observed=np.ones((3,7),bool));(p/'schema.json').write_text(json.dumps({'features':['ribo:'+str(i) for i in range(7)],'study_ids':['train','train','validation'],'scale':'log normalized'}))
   m={'vocab':['ribo:'+str(i) for i in range(7)],'source_ledger':[{'source_id':'ribo','status':'integrated'},{'source_id':'remaining','status':'pending'}],'dense_sources':[{'path':'dense.npz','schema_path':'schema.json','source_id':'ribo','modality':3,'split_by_study':{'train':'train','validation':'validation'}}]};(p/'manifest.json').write_text(json.dumps(m))
   args=[sys.executable,str(Path(__file__).with_name('train_joint_stream.py')),'--manifest',str(p/'manifest.json'),'--out',str(p/'run'),'--epochs','1','--dim','16','--layers','1','--heads','4','--window','3','--batch-rows','1']
   r=subprocess.run(args,capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
   logs=[json.loads(x) for x in (p/'run/training.jsonl').read_text().splitlines()];self.assertEqual(len(logs),6)
   status=json.loads((p/'run/status.json').read_text());self.assertEqual(status['pending_sources'],['remaining']);self.assertFalse(status['debug_only'])
   val=json.loads((p/'run/validation.json').read_text());self.assertEqual(len(val['rows']),3)
   partial=args.copy();partial[partial.index(str(p/'run'))]=str(p/'partial')
   r=subprocess.run(partial+['--debug-steps','1'],capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
   import torch
   saved=torch.load(p/'partial/checkpoint.pt',weights_only=False);self.assertEqual(saved['epoch'],0);self.assertEqual(saved['next_batch'],1)
   r=subprocess.run(partial+['--resume'],capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
   resumed=torch.load(p/'partial/checkpoint.pt',weights_only=False);full=torch.load(p/'run/checkpoint.pt',weights_only=False)
   for k,v in full['model'].items():torch.testing.assert_close(v,resumed['model'][k],rtol=0,atol=0)
   self.assertEqual(full['sampler_state'],resumed['sampler_state'])
if __name__=='__main__':unittest.main()
