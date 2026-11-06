import h5py,s3fs,numpy as np,json,hashlib
from pathlib import Path
out=Path('/Users/kky/biomate-review/docs/20260912_s3_continuation/pair_effect_data');out.mkdir(exist_ok=True)
with np.load('/Users/kky/biomate-audit-fix/out/20260911_h1_perturbation_pilot/prepared.npz',allow_pickle=False) as z:targets=set(z['targets']);readouts=z['readouts'].tolist()
fs=s3fs.S3FileSystem(anon=False,default_block_size=262144);source='knowledge-datasets-1759951976/immunology_sc_corpus_broad/perturbation/czi_tcell_genomewide/GWCD4i.DE_stats.by_donors.h5mu'
def col(g,key):
 v=g[key]
 if isinstance(v,h5py.Group):
  cats=v['categories'].asstr()[:];c=v['codes'][:];return np.where(c<0,'MISSING',cats[np.maximum(c,0)])
 return v.asstr()[:] if v.dtype.kind in 'OS' else v[:]
rows=[];ys=[];names=[];conditions=[];pairs=[]
with fs.open(source,'rb') as f,h5py.File(f,'r') as h:
 for pair,g in h['mod'].items():
  genes=col(g['var'],'gene_name');lookup={x:i for i,x in enumerate(genes)}
  if len(lookup)!=len(genes):raise ValueError('Duplicate readout symbols')
  available=[r for r in readouts if r in lookup];ixgenes=[lookup[r] for r in available]
  ko=col(g['obs'],'target_contrast_gene_name');cond=col(g['obs'],'culture_condition');qc=col(g['obs'],'ontarget_significant').astype(bool)&~col(g['obs'],'low_target_gex').astype(bool);ix=np.where(np.isin(ko,list(targets))&qc)[0]
  print(pair,'selected',len(ix),'readouts',len(available),'chunks',g['layers/log_fc'].chunks,flush=True)
  for i in ix:
   v=g['layers/log_fc'][int(i),:];y=np.full(len(readouts),np.nan,dtype='float32')
   for r,j in zip(available,ixgenes):y[readouts.index(r)]=v[j]
   if np.isinf(y).any():raise ValueError('Infinite effect')
   ys.append(y);names.append(str(ko[i]));conditions.append(str(cond[i]));pairs.append(pair);rows.append(int(i))
Y=np.stack(ys);np.savez_compressed(out/'effects.npz',Y=Y,observed=np.isfinite(Y),targets=np.array(names),conditions=np.array(conditions),donor_pairs=np.array(pairs),source_rows=np.array(rows),readouts=np.array(readouts))
manifest={'source':'s3://'+source,'source_metadata':{k:str(v) for k,v in fs.info(source).items() if k in ['size','ETag','LastModified']},'rows':len(Y),'readouts':readouts,'pair_counts':{p:pairs.count(p) for p in sorted(set(pairs))},'target_count':len(set(names)),'missing_entries':int((~np.isfinite(Y)).sum()),'selection':'Frozen earlier 117-target metadata panel; on-target significant and not low target expression within each donor-pair deposit','limitations':['Donor pairs overlap; never randomly split pair IDs','QC-conditioned successful-perturbation effects','DE contrasts may share control counts with pseudobulk; do not treat extracted baseline input as independent without control provenance'],'prepared_sha256':hashlib.sha256((out/'effects.npz').read_bytes()).hexdigest()};(out/'manifest.json').write_text(json.dumps(manifest,indent=2));print('saved',len(Y),'contrasts',len(set(names)),'targets',flush=True)
