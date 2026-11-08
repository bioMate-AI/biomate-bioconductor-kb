from pathlib import Path
import json,hashlib,collections
P=Path(__file__).resolve().parent;mp=P.parent/'20260912_fullscale_training/compiled_manifest_v2/manifest.json';m=json.loads(mp.read_text());ac=json.loads((P/'acquisition_manifest.json').read_text());download={r['source_uri'].split('/',3)[-1]:r for r in ac['downloaded_artifacts']}
rows=[]
for r in m['objects']:
 key=r['key'];include=('knowledge' in r['role'] or r['role'] in ['literature','genetic_association'] or key.endswith('kg.csv.gz') or key.endswith('primekg_immune_subgraph.parquet') or key in download or (r['role']=='derived_or_model' and Path(key).name in ['A_tf_edges.parquet','A_ppi_edges.parquet','A_mapkg_edges.parquet','collectri_human.tsv']))
 if not include:continue
 if key in download:status='downloaded_parsed_adapter_staged';reason='Current six-source typed adapter; optimizer exposure unverified'
 elif key.endswith('A_mapkg_full_edges.parquet'):status='downloaded_audited_adapter_staged';reason='Gene/protein projection only; duplicates/confidence audited'
 elif key.endswith('kg.csv.gz'):status='schema_stream_inspected_adapter_staged';reason='Full typed graph misclassified metadata_or_unsupported in compiled manifest; full parse/training pending'
 elif r['role']=='literature':status='stream_adapter_staged';reason='Frozen encoder prepare/iterator staged; no full corpus optimization'
 else:status='inventoried_adapter_pending';reason='Explicitly pending; not consumed merely because collected'
 rows.append({**r,'integration_status':status,'reason':reason,'optimizer_exposure_verified':False,'download_sha256':download.get(key,{}).get('sha256')})
raw=P.parent/'20260911_asthma_target_prioritization/raw';skills=[]
for f in sorted(raw.rglob('*')):
 if f.is_file():skills.append({'path':str(f),'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'status':'collected_targeted_skill_payload','optimizer_exposure_verified':False,'limitation':'Targeted asthma evidence, not whole catalogs; schema/source/license reconciliation needed'})
out={'compiled_manifest_sha256':hashlib.sha256(mp.read_bytes()).hexdigest(),'selection':'All knowledge roles, literature, genetic association, fullkg override and known prepared artifacts; retain original role to expose misclassifications','sources':rows,'raw_skill_payloads':skills,'source_count':len(rows),'raw_skill_payload_count':len(skills),'status_counts':dict(collections.Counter(r['integration_status'] for r in rows)),'all_collected_knowledge_optimized':False}
(P/'full_knowledge_source_ledger.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({k:v for k,v in out.items() if k not in ['sources','raw_skill_payloads']},indent=2))
