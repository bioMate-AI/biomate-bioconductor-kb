"""Reload every deposited pilot checkpoint without rewriting historical artifacts."""
import json,sys
from pathlib import Path
import numpy as np
import torch
from torch import nn
sys.path.insert(0,'/Users/kky/biomate-audit-fix/research/immune_llm_baseline')
from xverse_model import build_xverse
from train_h1_pilot import H1Head
from train_shared_omic_pilot import protein_key
from h1_pilot_inference import predict_named
torch.set_num_threads(2);base=Path('/Users/kky/biomate-audit-fix/out');checks=[]
def predict(model,x,head):
 model.eval()
 with torch.no_grad():return np.concatenate([model.omic_decoders[head](model.encode_biology(t)[1]).numpy() for t in torch.from_numpy(x).split(256)])
for name in ['shared_omic_training_pilot','donor_normalization_pilot','mosaic_rna_protein_atac_kg','h1_perturbation_pilot']:
 root=base/('20260911_'+name);out=root if name.startswith('shared') else root/'training';m=json.loads((root/'manifest.json').read_text())
 with np.load(root/'prepared.npz',allow_pickle=False) as z:d={k:z[k].copy() for k in z.files}
 for r in json.loads((out/'results.json').read_text())['runs']:
  stem=f"{r['arm']}_seed{r['seed']}";stem=r['target_task']+'_'+stem if name.startswith('donor') else stem;b=torch.load(out/(stem+'.pt'),weights_only=True,map_location='cpu')
  if name.startswith('h1'):
   with np.load(out/(stem+'_evaluation.npz'),allow_pickle=False) as z:
    pred=predict_named(out/(stem+'.pt'),z['targets'][z['test']].tolist(),z['conditions'][z['test']].tolist())['predicted_log_fold_change'];np.testing.assert_allclose(pred,z['prediction'],atol=1e-5,rtol=1e-5)
  else:
   model=build_xverse(b['cfg'],torch,nn);model.load_state_dict(b['state_dict'])
   if name.startswith('shared'):
    keys=list(map(protein_key,m['protein_names']));idx=[keys.index(k) for k in m['external_marker_keys']];p=predict(model,d['external_X'],'protein')[:,idx];f=out/(stem+'_external.npz');key='prediction'
   elif name.startswith('donor'):
    p=predict(model,d['X'][d['split']=='test'],'protein')*np.array(b['target_scale'],dtype='float32')+np.array(b['target_location'],dtype='float32');f=out/(stem+'_test.npz');key='prediction'
   else:
    p=predict(model,d['cite_X'][d['split']=='test'],'protein')*np.array(b['protein_scale'],dtype='float32')+np.array(b['protein_location'],dtype='float32');f=out/(stem+'_predictions.npz');key='protein_prediction'
    logits=predict(model,d['atac_X'][d['atac_test']],'atac');ap=torch.from_numpy(logits).sigmoid().numpy()
    with np.load(f,allow_pickle=False) as z:np.testing.assert_allclose(ap,z['atac_prediction'],atol=1e-5,rtol=1e-5)
   with np.load(f,allow_pickle=False) as z:np.testing.assert_allclose(p,z[key],atol=1e-5,rtol=1e-5)
  checks.append({'pilot':name,'checkpoint':stem,'all_saved_test_predictions':'pass'})
result={'verified':len(checks),'checks':checks};Path(__file__).with_name('checkpoint_results.json').write_text(json.dumps(result,indent=2));print('Verified all test predictions from',len(checks),'checkpoints')
