import boto3,gzip,csv,io,json
from pathlib import Path
c=boto3.client('s3');key='biomni_data_lake/kg.csv.gz';r=c.get_object(Bucket='knowledge-datasets-1759951976',Key=key)
with gzip.GzipFile(fileobj=r['Body']) as gz:
 reader=csv.DictReader(io.TextIOWrapper(gz));rows=[next(reader) for _ in range(3)];columns=reader.fieldnames
r['Body'].close();p=Path('/Users/kky/biomate-review/docs/20260912_knowledge_vnext');out={'source_key':key,'etag':r['ETag'],'bytes':r['ContentLength'],'columns':columns,'sample_rows':rows,'inspected_rows':3,'scope':'schema preview only; complete graph not downloaded or optimized'};(p/'primekg_full_schema.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
