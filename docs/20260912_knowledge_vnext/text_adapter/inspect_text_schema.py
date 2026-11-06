import boto3,gzip,json,hashlib
from pathlib import Path
p=Path('/Users/kky/biomate-review/docs/20260912_knowledge_vnext');inv=json.loads((p.parent/'20260912_fullscale_training/s3_metadata_inventory.json').read_text())
items=[x for v in inv.values() for x in v.get('items',[]) if '/text_knowledge/fulltext/shard_' in x['key'] and x['key'].endswith('.jsonl.gz')];x=sorted(items,key=lambda x:x['key'])[0]
c=boto3.client('s3');r=c.get_object(Bucket='knowledge-datasets-1759951976',Key=x['key']);assert r['ETag']==x['etag']
with gzip.GzipFile(fileobj=r['Body']) as z:line=z.readline()
r['Body'].close();d=json.loads(line);out={'source':x,'inspected_records':1,'record_sha256':hashlib.sha256(line).hexdigest(),'schema':{k:{'type':type(v).__name__,'length':len(v) if hasattr(v,'__len__') else None,'preview':str(v)[:150]} for k,v in d.items()},'catalog_shards':len(items),'catalog_bytes':sum(x['bytes'] for x in items),'not_full_download':True}
(p/'text_schema_inspection.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
