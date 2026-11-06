"""Development sensitivity: readouts selected using only the training donor."""
import json,hashlib,importlib.util
from pathlib import Path
import numpy as np
P=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('metric_functions',P.parent/'guide_reliability/evaluate.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def build(d):
 genes=d['gene_symbols'];targets=sorted(t for t in set(d['target']) if t!='NonTarget' and t in genes);donors=sorted(set(d['donor_id']));conditions=sorted(set(d['culture_condition']));effects={};cpms={}
 for donor in donors:
  for condition in conditions:
   group=(d['donor_id']==donor)&(d['culture_condition']==condition);c=group&(d['target']=='NonTarget');assert c.sum()==8
   cpms[donor,condition]=1e6*d['counts'][c].sum(0)/d['library_counts'][c].sum()
   baseline=m.norm(d['counts'][c].sum(0),d['library_counts'][c].sum())
   for t in targets:
    ix=group&(d['target']==t);assert ix.sum()==2
    effects[donor,condition,t]=m.norm(d['counts'][ix].sum(0),d['library_counts'][ix].sum())-baseline
 return genes,targets,donors,conditions,effects,cpms

def select(genes,targets,effects,cpms,train,condition,k):
 y=np.array([effects[train,condition,t] for t in targets]);valid=np.array([genes!=t for t in targets]);n=valid.sum(0);mean=np.where(valid,y,0).sum(0)/n
 variance=np.where(valid,(y-mean)**2,0).sum(0)/n
 eligible=(cpms[train,condition]>=1)&np.isfinite(variance)
 # Stable gene-name tie break; no test donor values used.
 ix=np.flatnonzero(eligible);order=np.lexsort((genes[ix],-variance[ix]));chosen=ix[order[:k]]
 return chosen,mean

def main():
 with np.load(P/'pseudobulk.npz',allow_pickle=False) as z:d={k:z[k] for k in z.files}
 genes,targets,donors,conditions,effects,cpms=build(d);assert len(donors)==2
 rows=[];selections=[];checks=0
 for test in donors:
  train=next(x for x in donors if x!=test)
  for condition in conditions:
   for k in [128,512]:
    chosen,mean=select(genes,targets,effects,cpms,train,condition,k)
    # Adversarial test: corrupt every held-out effect. Selection/means must be unchanged.
    altered={key:(v+1e9 if key[0]==test else v) for key,v in effects.items()}
    other,othermean=select(genes,targets,altered,cpms,train,condition,k)
    np.testing.assert_array_equal(chosen,other);np.testing.assert_array_equal(mean,othermean);checks+=1
    selections.append({'test_donor':str(test),'train_donor':str(train),'condition':str(condition),'k':k,'genes':genes[chosen].tolist()})
    for i,target in enumerate(targets):
     mismatch=targets[(i+1)%len(targets)];keep=chosen[(genes[chosen]!=target)&(genes[chosen]!=mismatch)];truth=effects[test,condition,target][keep]
     preds={'no_change':np.zeros(len(keep)),'condition_mean':mean[keep],'matched_observed_target':effects[train,condition,target][keep],'cyclic_mismatched_target':effects[train,condition,mismatch][keep]}
     rows.append({'test_donor':str(test),'train_donor':str(train),'condition':str(condition),'target':str(target),'mismatched_target':str(mismatch),'k':k,'readouts':len(keep),'metrics':{name:m.metrics(v,truth) for name,v in preds.items()}})
 def summarize(rr):
  result={}
  for name in rows[0]['metrics']:
   result[name]={}
   for metric in ['mse','pearson','spearman']:
    values=[r['metrics'][name][metric] for r in rr if r['metrics'][name][metric] is not None];result[name][metric]=float(np.mean(values)) if values else None
  return result
 result={'protocol':'Reused external dataset development sensitivity. Per train-donor/condition, control CPM>=1, rank variance of target effects excluding own-target labels per output; fixed top128/top512, gene-name tie break. Every scoring arm excludes true and mismatch target genes. No test-outcome selection. Report both settings without selecting a winner; not untouched confirmation or fitted model.','selections':selections,'by_k':{str(k):summarize([r for r in rows if r['k']==k]) for k in [128,512]},'by_k_test_donor':{str(k):{str(d):summarize([r for r in rows if r['k']==k and r['test_donor']==d]) for d in donors} for k in [128,512]},'rows':rows,'held_out_corruption_checks':checks,'input_sha256':hashlib.sha256((P/'pseudobulk.npz').read_bytes()).hexdigest()}
 (P/'train_selected_transfer.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n');print(json.dumps(result['by_k'],indent=2))
if __name__=='__main__':main()
