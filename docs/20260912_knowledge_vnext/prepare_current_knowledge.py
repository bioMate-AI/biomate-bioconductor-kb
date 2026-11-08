"""Prepare existing collected knowledge for CURRENT integration, without cutoff/filtering."""
from pathlib import Path
import json,hashlib
import pandas as pd
P=Path(__file__).resolve().parent;R=P/'raw';O=P/'current_prepared';O.mkdir(exist_ok=True)
coverage={};edges=[]
for name in ['reactome','kegg','go_bp']:
 memberships=[]
 for row,line in enumerate((R/(name+'.gmt')).read_text().splitlines()):
  v=line.split('\t');assert len(v)>=3
  for gene in v[2:]:
   if gene:memberships.append({'source_catalog':name,'source_row':row,'pathway':v[0],'description':v[1],'gene':gene})
 d=pd.DataFrame(memberships);d.to_parquet(O/(name+'_memberships.parquet'),index=False)
 coverage[name]={'pathways':int(d.pathway.nunique()),'memberships':len(d),'genes':int(d.gene.nunique()),'exact_duplicate_memberships':int(d.duplicated(['pathway','gene']).sum()),'filter':'none; source membership retained'}
d=pd.read_csv(R/'collectri_human.tsv',sep='\t');assert d.weight.isin([-1,1]).all();d.to_parquet(O/'collectri_signed.parquet',index=False)
coverage['collectri']={'rows':len(d),'regulators':int(d.source.nunique()),'targets':int(d.target.nunique()),'sign_counts':{str(k):int(v) for k,v in d.weight.value_counts().items()},'sign_decision_counts':{str(k):int(v) for k,v in d.sign_decision.value_counts().items()},'exact_duplicate_rows':int(d.duplicated().sum()),'caveat':'Some positive signs are default activation; preserve sign_decision, resources and references, do not label every edge experimentally signed.'}
d=pd.read_parquet(R/'genetics_priors_long.parquet');d.to_parquet(O/'genetics_disease_specific.parquet',index=False)
coverage['genetics']={'rows':len(d),'diseases':int(d.disease.nunique()),'genes':int(d.gene.nunique()),'exact_duplicate_rows':int(d.duplicated().sum()),'caveat':'Disease context and separate l2g/burden/raw/normalized priors retained; no maximum across diseases; limited original immune prior panel.'}
d=pd.read_parquet(R/'primekg_immune_subgraph.parquet');d.to_parquet(O/'primekg_typed.parquet',index=False)
coverage['primekg']={'rows':len(d),'relations':{str(k):int(v) for k,v in d.relation.value_counts().items()},'x_types':{str(k):int(v) for k,v in d.x_type.value_counts().items()},'y_types':{str(k):int(v) for k,v in d.y_type.value_counts().items()},'exact_duplicate_rows':int(d.duplicated().sum()),'caveat':'Collected immune subgraph, not full PrimeKG; name-based nodes require namespace mapping; no canonical node IDs in source.'}
manifest=json.loads((P/'acquisition_manifest.json').read_text());manifest['integration_target']='CURRENT model: existing collected artifacts, not newly sourced knowledge';manifest['new_external_sources_acquired']=0
for x in manifest['downloaded_artifacts']:x['training_status']='parsed for CURRENT integration; no optimizer exposure yet'
manifest['prepared_artifacts']=[{'path':str(q),'sha256':hashlib.sha256(q.read_bytes()).hexdigest(),'bytes':q.stat().st_size} for q in sorted(O.glob('*.parquet'))];manifest['coverage']=coverage
(P/'acquisition_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(coverage,indent=2))
