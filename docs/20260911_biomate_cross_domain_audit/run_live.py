"""Live dev chat baseline. Credentials stay in memory and are never written to artifacts."""
import concurrent.futures
import json
import os
from pathlib import Path
import re
import time
import urllib.request
import uuid

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parent.parent
BASE=os.environ.get('BIOMATE_URL','https://dev-public.biomate.ai')
fixture=(REPO/'frontend/e2e/realrun-admet.e2e.ts').read_text()
def configured(name):
    value=os.environ.get(name)
    if value:return value
    match=re.search(r'process\.env\.'+name+r'\s*\|\|\s*"([^"]+)"',fixture)
    if not match:raise RuntimeError('Missing fixture configuration: '+name)
    return match.group(1)

headers={'Content-Type':'application/json','x-e2e-test-token':configured('E2E_TEST_TOKEN')}
req=urllib.request.Request(BASE+'/api/auth/login',data=json.dumps({'email':configured('E2E_FIXTURE_EMAIL'),'password':configured('E2E_FIXTURE_PASSWORD')}).encode(),headers=headers)
with urllib.request.urlopen(req,timeout=30) as response:login=json.load(response)
if not login.get('token'):raise RuntimeError('Fixture login returned no token')
headers['Authorization']='Bearer '+login['token']
print('Fixture login succeeded; token retained in memory only',flush=True)
cases=json.loads((ROOT/'cases.json').read_text())
selected=set(os.environ.get('AUDIT_CASE_IDS','').split(','))-{''}
if selected: cases=[c for c in cases if c['id'] in selected]
raw=ROOT/'raw';raw.mkdir(exist_ok=True)

def execute(case):
    start=time.monotonic();events=[];event_name='message';data_lines=[]
    session='reasoning-audit-'+case['id']+'-'+uuid.uuid4().hex
    payload={'message':case['prompt'],'context':{'sessionId':session,'conversationHistory':[]}}
    request=urllib.request.Request(BASE+'/api/chat/stream',data=json.dumps(payload).encode(),headers=headers)
    result={'id':case['id'],'base_url':BASE,'prompt':case['prompt'],'checks':case['checks'],'events':events}
    try:
        with urllib.request.urlopen(request,timeout=180) as response:
            result['http_status']=response.status
            for rawline in response:
                if time.monotonic()-start>240:raise TimeoutError('Total request budget exceeded')
                line=rawline.decode('utf-8',errors='replace').rstrip('\r\n')
                if line.startswith('event:'):event_name=line[6:].strip()
                elif line.startswith('data:'):data_lines.append(line[5:].lstrip())
                elif not line and data_lines:
                    value='\n'.join(data_lines)
                    try:value=json.loads(value)
                    except json.JSONDecodeError:pass
                    events.append({'event':event_name,'data':value});data_lines=[];event_name='message'
        result['transport']='complete' if any(e['event']=='done' for e in events) else 'incomplete'
    except Exception as exc:
        result['transport']='error';result['error']=type(exc).__name__+': '+str(exc)[:200]
    result['elapsed_seconds']=round(time.monotonic()-start,2)
    result['response_text']=''.join(e['data'].get('text','') for e in events if e['event']=='delta' and isinstance(e['data'],dict))
    result['final']=[e['data'] for e in events if e['event']=='final']
    (raw/(case['id']+'.json')).write_text(json.dumps(result,indent=2))
    print(case['id'],result['transport'],'events',len(events),'characters',len(result['response_text']),'seconds',result['elapsed_seconds'],flush=True)
    return {'id':case['id'],'transport':result['transport'],'elapsed_seconds':result['elapsed_seconds']}

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    rows=list(pool.map(execute,cases))
(ROOT/('transport_summary_'+('_'.join(sorted(selected)) if selected else 'initial')+'.json')).write_text(json.dumps(rows,indent=2))
