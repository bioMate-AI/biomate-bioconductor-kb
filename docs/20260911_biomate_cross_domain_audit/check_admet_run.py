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

import urllib.error
run=json.loads((ROOT/'raw/WF01_execution_response.json').read_text())['body']['runId']
for suffix in ['', '/status', '/output_files', '/findings']:
    path='/api/workflows/runs/'+run+suffix
    req=urllib.request.Request(BASE+path,headers=headers)
    try:
        with urllib.request.urlopen(req,timeout=60) as response: result={'http_status':response.status,'body':json.load(response)}
    except urllib.error.HTTPError as exc:
        result={'http_status':exc.code,'body':exc.read().decode()[:2000]}
    (ROOT/('raw/WF01_run'+(suffix.replace('/','_') or '_detail')+'.json')).write_text(json.dumps(result,indent=2))
    print(suffix or 'detail',json.dumps(result)[:5000],flush=True)
