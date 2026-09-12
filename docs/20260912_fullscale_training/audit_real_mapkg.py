from pathlib import Path
import pandas as pd,json,hashlib,re
P=Path(__file__).resolve().parent;p=Path('/tmp/immune_fullscale_manifest/A_mapkg_full_edges.parquet');d=pd.read_parquet(p)
r=d.relation.str.replace(r'\(with confidence: [^)]+\)','(confidence)',regex=True).str.replace(r'\([0-9.eE+-]+\)','(confidence)',regex=True)
confidence=d.relation.str.extract(r'\((?:with confidence: )?([0-9.eE+-]+)\)',expand=False).astype(float)
inventory=json.loads((P/'s3_metadata_inventory.json').read_text());candidates=[]
for v in inventory.values():
 for item in v.get('items',[]):
  if re.search(r'map.?kg|primekg',item['key'],re.I) and '/code/' not in item['key']:candidates.append(item)
out={'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size,'rows':len(d),'columns':list(d.columns),'column_types':{k:str(v) for k,v in d.dtypes.items()},'null_counts':{k:int(v) for k,v in d.isna().sum().items()},'unique_endpoint_strings':len(set(d.i_symbol)|set(d.j_symbol)),'unique_raw_relations':int(d.relation.nunique()),'normalized_relation_counts':{str(k):int(v) for k,v in r.value_counts().items()},'confidence':{'parsed_rows':int(confidence.notna().sum()),'min':float(confidence.min()),'max':float(confidence.max()),'below_0_5':int((confidence<.5).sum())},'self_loops':int(d.i_symbol.eq(d.j_symbol).sum()),'duplicate_full_rows':int(d.duplicated().sum()),'explicit_node_type_columns':False,'explicit_drug_disease_relation_families':False,'original_complete_heterogeneous_graph_located_in_inventory':False,'related_s3_candidates':candidates,'inventory_sha256':hashlib.sha256((P/'s3_metadata_inventory.json').read_bytes()).hexdigest(),'limitation':'Endpoint strings lack node types; relation semantics support a gene/protein interaction projection, not a full heterogeneous graph. No evidence of drug/disease relations. Original graph absent from searched inventory is not proof absent from bucket or elsewhere.'}
(P/'real_mapkg_audit.json').write_text(json.dumps(out,indent=2,allow_nan=False)+'\n');print(json.dumps({k:v for k,v in out.items() if k!='related_s3_candidates'},indent=2))
