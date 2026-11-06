import hashlib,json,subprocess,sys,tempfile,unittest
from pathlib import Path
import numpy as np
import torch
class TextCLI(unittest.TestCase):
 def test_text_phase_resume_and_heldout(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td);np.savez(p/'assay.npz',values=np.array([[1.,2.]],np.float32),observed=np.ones((1,2),bool));(p/'schema.json').write_text(json.dumps({'features':['RNA:A','RNA:B'],'study_ids':['s1'],'scale':'test'}))
   provenance=[json.dumps({'article_id':str(i),'source_key':'text','token_count':7}) for i in range(3)];np.savez(p/'text.npz',vectors=np.ones((3,384),np.float32),gene_offsets=np.arange(4,dtype=np.int64),gene_indices=np.array([0,1,0],np.int64),provenance=np.array(provenance))
   prep={'identity':{'model':'sentence-transformers/all-MiniLM-L6-v2','revision':'a'*40,'mapping_sha256':'b'*64,'tokenizer_sha256':'c'*64},'complete':True,'chunks':[{'path':'text.npz','sha256':hashlib.sha256((p/'text.npz').read_bytes()).hexdigest(),'rows':3,'dimension':384}]};(p/'text_manifest.json').write_text(json.dumps(prep))
   manifest={'vocab':['RNA:A','RNA:B'],'source_ledger':[{'source_id':'rna','status':'integrated'},{'source_id':'text','status':'integrated'}],'dense_sources':[{'path':'assay.npz','schema_path':'schema.json','source_id':'rna','modality':0,'split_by_study':{'s1':'train'}}],'text_sources':[{'manifest_path':'text_manifest.json','source_id':'text','heldout_article_ids':['1'],'batch_rows':1}]};(p/'manifest.json').write_text(json.dumps(manifest))
   args=[sys.executable,str(Path(__file__).with_name('train_joint_stream.py')),'--manifest',str(p/'manifest.json'),'--out',str(p/'full'),'--epochs','1','--dim','16','--layers','1','--heads','4']
   r=subprocess.run(args,capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
   status=json.loads((p/'full/status.json').read_text());self.assertEqual(status['text_exposure'],{'text':2});self.assertEqual(status['steps'],3)
   part=args.copy();part[part.index(str(p/'full'))]=str(p/'part');r=subprocess.run(part+['--debug-steps','2'],capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
   saved=torch.load(p/'part/checkpoint.pt',weights_only=False);self.assertEqual(saved['sampler_state']['text_cursor']['next_row'],1)
   r=subprocess.run(part+['--resume'],capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
   full=torch.load(p/'full/checkpoint.pt',weights_only=False);last=torch.load(p/'part/checkpoint.pt',weights_only=False)
   for k,v in full['model'].items():torch.testing.assert_close(v,last['model'][k],rtol=0,atol=0)
   self.assertEqual(full['sampler_state'],last['sampler_state'])
if __name__=='__main__':unittest.main()
