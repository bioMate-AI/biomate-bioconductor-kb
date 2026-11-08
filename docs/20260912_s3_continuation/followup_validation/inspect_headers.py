"""Inspect sample-column schemas only; never parse expression outcomes."""
import urllib.request,gzip,json,re,csv,io
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
P=Path(__file__).resolve().parent
html=(P/'geo_directory.html').read_text();names=sorted(set(re.findall(r'href="(GSE314342_IL10IL21_validation_[^"]+csv.gz)"',html)))
def read(name):
 url='https://ftp.ncbi.nlm.nih.gov/geo/series/GSE314nnn/GSE314342/suppl/'+name
 with urllib.request.urlopen(url,timeout=30) as response:
  with gzip.GzipFile(fileobj=response) as f:header=f.readline().decode('utf-8-sig').strip()
 return name,{'url':url,'columns':next(csv.reader([header])),'inspection':'Header only; no numeric rows parsed'}
with ThreadPoolExecutor(max_workers=4) as pool:result=dict(pool.map(read,names))
(P/'count_headers.json').write_text(json.dumps(result,indent=2)+'\n')
for name,v in result.items():print(name,v['columns'])
