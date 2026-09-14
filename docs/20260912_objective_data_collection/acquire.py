"""Acquire public objective evidence. Metadata/aggregate outcomes are not patient labels."""
import datetime,hashlib,json,time,urllib.request,urllib.parse
from pathlib import Path
ROOT=Path(__file__).resolve().parent
manifest=[]
def fetch(name,url):
 try:
  req=urllib.request.Request(url,headers={'User-Agent':'BioMate-research-data-audit/1.0'})
  with urllib.request.urlopen(req,timeout=90) as r: data=r.read()
  (ROOT/'raw'/name).write_bytes(data)
  manifest.append(dict(file=name,url=url,bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),retrieved_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),status='downloaded',training_eligible=False))
  print(name,len(data),flush=True)
  return data
 except Exception as e:
  manifest.append(dict(file=name,url=url,status='failed',error=str(e)));print(name,str(e),flush=True)
 finally:
  (ROOT/'acquisition_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for acc in ['GSE15316','GSE113156','GSE35455']:
 fetch(acc+'.soft.txt','https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?'+urllib.parse.urlencode({'acc':acc,'targ':'all','view':'full','form':'text'}));time.sleep(1)
for condition in ['rheumatoid arthritis','asthma','lupus']:
 token=None;page=0
 while True:
  params={'query.cond':condition,'query.term':'withdrawal OR discontinuation OR relapse OR sustained remission','filter.overallStatus':'COMPLETED','pageSize':100,'format':'json'}
  if token:params['pageToken']=token
  data=fetch(condition.replace(' ','_')+f'_trials_{page}.json','https://clinicaltrials.gov/api/v2/studies?'+urllib.parse.urlencode(params))
  if data is None:break
  token=json.loads(data).get('nextPageToken');page+=1
  if not token:break
  time.sleep(1)
