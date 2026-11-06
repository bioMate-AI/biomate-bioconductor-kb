"""Frozen exploratory four-donor attenuation replication; local inputs only."""
from pathlib import Path
import hashlib,json,copy
import numpy as np
from scipy.stats import spearmanr
P=Path(__file__).resolve().parent; ROOT=P.parent.parent

def load(path):
 with np.load(path,allow_pickle=False) as z:return {k:z[k] for k in z.files}
def norm(counts,lib):
 return np.log1p(1e4*np.asarray(counts,dtype=np.float64)/np.asarray(lib,dtype=np.float64)[...,None])
def metric(a,b):
 a=np.asarray(a,dtype=np.float64);b=np.asarray(b,dtype=np.float64)
 assert a.shape==b.shape and np.isfinite(a).all() and np.isfinite(b).all()
 valid=len(a)>1 and np.ptp(a)>0 and np.ptp(b)>0
 return {'mse':float(np.mean((a-b)**2)),'pearson':float(np.corrcoef(a,b)[0,1]) if valid else None,'spearman':float(spearmanr(a,b).statistic) if valid else None}
def build(t,c):
 np.testing.assert_array_equal(t['gene_symbols'],c['gene_symbols'])
 genes=t['gene_symbols']; targets=sorted(set(t['perturbed_gene_name']));donors=sorted(set(t['donor_id']));conditions=sorted(set(t['culture_condition']))
 assert len(targets)==16 and len(donors)==4 and len(conditions)==3
 assert set(c['guide_id'][c['pool']=='feature']).isdisjoint(set(c['guide_id'][c['pool']=='reference']))
 x=norm(t['counts'],t['library_counts']);effects={};guides={};refs={};cpms={}
 for d in donors:
  for condition in conditions:
   ci=(c['donor_id']==d)&(c['culture_condition']==condition)
   cpms[d,condition]=1e6*c['counts'][ci].sum(0)/c['library_counts'][ci].sum()
   baseline=norm(c['counts'][ci].sum(0),c['library_counts'][ci].sum())
   for pool in ['feature','reference']:
    ix=ci&(c['pool']==pool);assert ix.any()
    refs[d,condition,pool]=norm(c['counts'][ix].sum(0),c['library_counts'][ix].sum())
   for target in targets:
    ix=np.flatnonzero((t['donor_id']==d)&(t['culture_condition']==condition)&(t['perturbed_gene_name']==target));assert len(ix)==2 and len(set(t['guide_id'][ix]))==2
    ix=sorted(ix,key=lambda i:t['guide_id'][i]);guides[d,condition,target]=x[ix]
    effects[d,condition,target]=norm(t['counts'][ix].sum(0),t['library_counts'][ix].sum())-baseline
 return {'genes':genes,'targets':targets,'donors':donors,'conditions':conditions,'effects':effects,'guides':guides,'refs':refs,'cpms':cpms}
def fit(data,test,condition,k,excluded):
 train=[d for d in data['donors'] if d!=test];genes=data['genes'];targets=data['targets']
 means=np.array([np.mean([data['effects'][d,condition,t] for d in train],axis=0) for t in targets])
 allowed=~np.isin(genes,list(excluded))
 if k is None:chosen=np.flatnonzero(allowed)
 else:
  # Equal-donor control CPM; fixed >=1 threshold, training donors only.
  expressed=np.mean([data['cpms'][d,condition] for d in train],axis=0)>=1
  variance=np.var(means,axis=0);eligible=np.flatnonzero(allowed&expressed&np.isfinite(variance))
  chosen=eligible[np.lexsort((genes[eligible],-variance[eligible]))[:k]]
 assert len(chosen)>1 and not set(genes[chosen])&excluded
 numerator=0.;denominator=0.
 for d in train:
  f=data['refs'][d,condition,'feature'][chosen];r=data['refs'][d,condition,'reference'][chosen]
  for target in targets:
   a,b=data['guides'][d,condition,target][:,chosen]
   # Both guide orders and both disjoint-reference assignments.
   for u,v in [(a-f,b-r),(b-r,a-f),(a-r,b-f),(b-f,a-r)]:
    numerator+=float(u@v);denominator+=float(u@u)
 alpha=float(np.clip(numerator/denominator,0,1)) if denominator else 0.
 return chosen,alpha,numerator,denominator,means[:,chosen]
def summarize(rows):
 out={}
 for arm in rows[0]['metrics']:
  out[arm]={}
  for m in ['mse','pearson','spearman']:
   values=[r['metrics'][arm][m] for r in rows if r['metrics'][arm][m] is not None]
   out[arm][m]={'mean':float(np.mean(values)) if values else None,'valid_count':len(values),'total_count':len(rows)}
 return out

def run(data,excluded):
 rows=[];fits=[];checks=0
 for test in data['donors']:
  altered=dict(data)
  # Corrupt ALL held-out guide values, aggregate effects and control-derived features.
  for key in ['effects','guides','refs','cpms']:
   altered[key]={a:(v*0+1e9 if a[0]==test else v) for a,v in data[key].items()}
  for condition in data['conditions']:
   for label,k in [('all',None),('128',128),('512',512)]:
    chosen,alpha,num,den,means=fit(data,test,condition,k,excluded)
    other=fit(altered,test,condition,k,excluded)
    for a,b in zip((chosen,alpha,num,den,means),other):np.testing.assert_array_equal(a,b)
    checks+=1
    fits.append({'test_donor':str(test),'train_donors':[str(d) for d in data['donors'] if d!=test],'condition':str(condition),'panel':label,'alpha':alpha,'numerator':num,'denominator':den,'readouts':len(chosen),'genes':data['genes'][chosen].tolist()})
    for i,target in enumerate(data['targets']):
     wrong=(i+1)%len(data['targets']);truth=data['effects'][test,condition,target][chosen]
     arms={'no_change':np.zeros(len(chosen)),'condition_mean':means.mean(0),'matched_observed_target':means[i],'shrunk_matched':alpha*means[i],'shrunk_mismatched':alpha*means[wrong]}
     rows.append({'test_donor':str(test),'condition':str(condition),'panel':label,'target':str(target),'mismatched_target':str(data['targets'][wrong]),'alpha':alpha,'readouts':len(chosen),'metrics':{a:metric(v,truth) for a,v in arms.items()}})
 return {'fits':fits,'rows':rows,'heldout_mutation_checks':checks,'by_panel':{p:summarize([r for r in rows if r['panel']==p]) for p in ['all','128','512']},'by_panel_test_donor':{p:{str(d):summarize([r for r in rows if r['panel']==p and r['test_donor']==d]) for d in data['donors']} for p in ['all','128','512']}}
def main():
 paths={'selected':ROOT/'full_readout_reliability/targets.npz','basic_qc':ROOT/'basic_qc_panel/targets.npz'};control=ROOT/'full_readout_reliability/controls.npz';c=load(control)
 ds={name:build(load(p),c) for name,p in paths.items()};excluded=set().union(*(set(d['targets']) for d in ds.values()))
 out={'protocol':'Exploratory development replication, no threshold optimization or promotion. Two separate16-target panels, shared controls; four outer heldout donors. Per condition training-only attenuation pooled across3 donor guide pairs and both disjoint reference orientations, zero intercept slope clipped[0,1]. Aggregate effects use all available NT controls within each donor/condition; disjoint feature/reference pools are used only for attenuation fitting. This differs from reference-only labels in the earlier donor-state model and is not a direct score comparison. Known-target predictions average aggregate effects across3 training donors. All perturbed genes from BOTH panels excluded in every arm/fit. Fixed all/top128/top512; top panels require equal-donor mean training-control CPM>=1 and rank variance across training target means with gene-name ties. No test-donor fit inputs. Correlation means conditional on validity; alpha0 arms undefined and conditional averages cannot be compared without their counts.','excluded_target_genes':sorted(excluded),'datasets':{name:run(d,excluded) for name,d in ds.items()},'input_sha256':{name:hashlib.sha256(p.read_bytes()).hexdigest() for name,p in {**paths,'controls':control}.items()},'code_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
 (P/'results.json').write_text(json.dumps(out,indent=2,allow_nan=False)+'\n')
 print(json.dumps({name:{p:{arm:stat['mse']['mean'] for arm,stat in result.items()} for p,result in data['by_panel'].items()} for name,data in out['datasets'].items()},indent=2))
 print('mutation checks',sum(d['heldout_mutation_checks'] for d in out['datasets'].values()))
if __name__=='__main__':main()
