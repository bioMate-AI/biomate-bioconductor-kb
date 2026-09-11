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
if (ROOT/'raw/WF01_execution_response.json').exists():
    raise SystemExit('Execution already recorded; use check_admet_run.py. Do not duplicate the QA run.')
wf=json.loads((ROOT/'raw/WF01.json').read_text())['final'][0]['workflow']['workflow_ga']
payload={'workflowDefinition':wf,'inputs':[],'params':wf.get('parameters',{}),'executionConfig':{'mode':'sandbox'}}
(ROOT/'raw/WF01_execution_request.json').write_text(json.dumps(payload,indent=2))
request=urllib.request.Request(BASE+'/api/workflows/execute',data=json.dumps(payload).encode(),headers=headers)
try:
    with urllib.request.urlopen(request,timeout=120) as response:
        result={'http_status':response.status,'body':json.load(response)}
except urllib.error.HTTPError as exc:
    result={'http_status':exc.code,'body':json.loads(exc.read())}
(ROOT/'raw/WF01_execution_response.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result,indent=2))
