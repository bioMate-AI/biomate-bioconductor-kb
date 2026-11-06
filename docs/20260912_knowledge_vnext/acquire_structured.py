"""Version bounded existing-source catalogs without cloud writes."""
from pathlib import Path
import json,hashlib,concurrent.futures
import boto3
P=Path(__file__).resolve().parent;B='knowledge-datasets-1759951976'
INV=P.parent/'20260912_fullscale_training/s3_metadata_inventory.json'
j=json.loads(INV.read_text());wanted=['/pathways/go_bp.gmt','/pathways/kegg.gmt','/pathways/reactome.gmt','/tracks/structured_knowledge/tf/collectri_human.tsv','/genetics/genetics_priors_long.parquet','/rebakeoff_stage/primekg_immune_subgraph.parquet']
items=[x for v in j.values() for x in v.get('items',[]) if any(x['key'].endswith(s) for s in wanted)]
assert len(items)==6
client=boto3.client('s3')
def one(x):
 key=x['key'];before=client.head_object(Bucket=B,Key=key);assert before['ContentLength']==x['bytes'] and before['ETag']==x['etag']
 p=P/'raw'/Path(key).name;client.download_file(B,key,str(p));after=client.head_object(Bucket=B,Key=key);assert before['ETag']==after['ETag'] and before['ContentLength']==after['ContentLength'];assert p.stat().st_size==x['bytes']
 return {'source_uri':'s3://'+B+'/'+key,'local_path':str(p),'bytes':p.stat().st_size,'etag':before['ETag'],'source_last_modified':before['LastModified'].isoformat(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'status':'downloaded_raw','release_date':'not established from object timestamp','license_status':'not established by S3 storage; source-specific training/redistribution terms require verification','training_status':'not optimized; next-version staging only'}
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:out=list(ex.map(one,items))
(P/'acquisition_manifest.json').write_text(json.dumps({'inventory_sha256':hashlib.sha256(INV.read_bytes()).hexdigest(),'downloaded_artifacts':out,'total_downloaded_bytes':sum(x['bytes'] for x in out),'cloud_writes':False},indent=2)+'\n');print('downloaded',len(out),'bytes',sum(x['bytes'] for x in out))
