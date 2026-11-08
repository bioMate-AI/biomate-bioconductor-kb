import json,subprocess,sys,tempfile,unittest
from pathlib import Path
import numpy as np
import torch
class MeasuredCLI(unittest.TestCase):
 def test_h1_h4_schedule_and_resume(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);rng=np.random.default_rng(1)
   arrays={'ids':np.array([[0,1,2],[1,2,3]],np.int64),'values':rng.random((2,3)).astype('float32'),'valid':np.ones((2,3),bool),'modality':np.zeros((2,3),np.int64),'perturbation':rng.random((2,2)).astype('float32'),'h1':rng.random((2,3)).astype('float32'),'h1_mask':np.ones((2,3),bool),'h4':rng.random((2,2)).astype('float32'),'h4_mask':np.ones((2,2),bool),'baseline':rng.random((2,2)).astype('float32'),'peptide':rng.random((2,2,4)).astype('float32'),'hla':rng.random((2,2,2)).astype('float32'),'mapping':np.array([[0,1],[1,0]],np.int64)}
   np.savez(p/'batch.npz',**arrays)
   entry={'path':'batch.npz','source_id':'measured','study_id':'s1','split':'train','objectives':{'h1_transcription_delta':1.,'h4_presentation_delta':1.},'labels':{'h1_transcription_delta':{'value':'h1','observed':'h1_mask'},'h4_presentation_delta':{'value':'h4','observed':'h4_mask'}},'context':{'baseline_protein_log_abundance':'baseline','peptide_features':'peptide','hla_features':'hla','source_protein_index':'mapping'}}
   m={'vocab':['RNA:A','RNA:B','RNA:C','RNA:D'],'source_ledger':[{'source_id':'measured','status':'integrated'}],'measured_sources':[entry,entry.copy()],'head_config':{'cell_dim':16,'perturbation_dim':2,'machinery_dim':8,'n_transcripts':3,'protein_to_transcript':[0,1],'peptide_dim':4,'hla_dim':2}}
   (p/'manifest.json').write_text(json.dumps(m));args=[sys.executable,str(Path(__file__).with_name('train_joint_stream.py')),'--manifest',str(p/'manifest.json'),'--out',str(p/'full'),'--epochs','1','--dim','16','--layers','1','--heads','4']
   r=subprocess.run(args,capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
   log=[json.loads(l) for l in (p/'full/training.jsonl').read_text().splitlines()];self.assertEqual(set(log[0]['assays']),{'h1_transcription_delta','h4_presentation_delta'})
   part=args.copy();part[part.index(str(p/'full'))]=str(p/'part');r=subprocess.run(part+['--debug-steps','1'],capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
   first=torch.load(p/'part/checkpoint.pt',weights_only=False);r=subprocess.run(part+['--resume'],capture_output=True,text=True);self.assertEqual(r.returncode,0,r.stderr)
   full=torch.load(p/'full/checkpoint.pt',weights_only=False);last=torch.load(p/'part/checkpoint.pt',weights_only=False)
   for key,value in full['model'].items():torch.testing.assert_close(value,last['model'][key],rtol=0,atol=0)
   for prefix in ['encoder.genes','canonical_heads.h1','canonical_heads.h2','canonical_heads.h3','canonical_heads.h4_delta']:
    self.assertTrue(any(not torch.equal(v,first['model'][k]) for k,v in full['model'].items() if k.startswith(prefix)),prefix)
if __name__=='__main__':unittest.main()
