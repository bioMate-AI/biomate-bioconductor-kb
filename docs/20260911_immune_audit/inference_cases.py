import json,subprocess,sys,tempfile
from pathlib import Path
import numpy as np
import anndata as ad
root=Path('/Users/kky/biomate-audit-fix/out/20260911_mosaic_rna_protein_atac_kg');m=json.loads((root/'manifest.json').read_text());cli='/Users/kky/biomate-audit-fix/research/immune_llm_baseline/immune_mosaic_inference.py';bundle=root/'training/experimental_bundle_v2.pt';cases=[]
with np.load(root/'prepared.npz',allow_pickle=False) as d:
 ix=np.where(d['split']=='test')[0][:3];a=ad.AnnData(X=d['cite_C'][ix].copy());a.var_names=m['genes'];a.obs_names=d['cell_ids'][ix];a.layers['counts']=a.X.copy()
with tempfile.TemporaryDirectory() as td:
 td=Path(td)
 def run(name,obj,error=None):
  inp=td/(name+'.h5ad');obj.write_h5ad(inp);out=td/name
  p=subprocess.run([sys.executable,cli,'predict','--input',str(inp),'--bundle',str(bundle),'--output-prefix',str(out)],text=True,capture_output=True)
  if error:assert p.returncode!=0 and error in p.stderr,(name,p.stderr)
  else:assert p.returncode==0,(name,p.stderr)
  cases.append({'case':name,'expected':'reject' if error else 'accept','status':'pass'})
  if not error:
   with np.load(str(out)+'.npz',allow_pickle=False) as z:return z['predicted_centered_log1p_protein'].copy()
 p=run('valid_raw_counts',a);q=run('reordered_genes',a[:,::-1].copy());np.testing.assert_allclose(p,q,atol=1e-6)
 with np.load(root/'training/ATAC_paired_seed0_predictions.npz',allow_pickle=False) as z:np.testing.assert_allclose(p,z['protein_prediction'][:3],atol=1e-5,rtol=1e-5)
 run('missing_gene',a[:,1:].copy(),'Missing required RNA genes')
 b=a.copy();b.layers['counts'][0,0]=.25;run('fractional_counts',b,'integer counts')
 b=a.copy();b.layers['counts'][0,0]=np.nan;run('nonfinite_counts',b,'integer counts')
 b=a.copy();del b.layers['counts'];run('missing_raw_layer',b,'Raw RNA')
 b=a.copy();b.obs_names=['same']*3;run('duplicate_cell_ids',b,'unique cell identifiers')
 b=a.copy();b.var_names=[m['genes'][0]]*len(m['genes']);run('duplicate_gene_ids',b,'Ambiguous feature identifier')
Path(__file__).with_name('inference_results.json').write_text(json.dumps({'passed':len(cases),'cases':cases,'saved_training_prediction_matches':True},indent=2));print(len(cases),'CLI cases passed')
