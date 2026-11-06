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
class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,hdrs,newurl):
        new=super().redirect_request(req,fp,code,msg,hdrs,newurl)
        if new is not None:
            new.remove_header('Authorization')
            new.remove_header('X-e2e-test-token')
        return new
opener=urllib.request.build_opener(SafeRedirect())
files=json.loads((ROOT/'raw/WF01_run_output_files.json').read_text())['body']['output_files']
out=ROOT/'raw/admet_outputs';out.mkdir(exist_ok=True)
checks=[]
for item in files:
    req=urllib.request.Request(BASE+item['download_endpoint'],headers=headers)
    try:
        with opener.open(req,timeout=60) as response: data=response.read()
        (out/Path(item['name']).name).write_bytes(data)
        checks.append({'name':item['name'],'status':'readable','bytes':len(data)})
    except urllib.error.HTTPError as exc:
        import xml.etree.ElementTree as ET
        body=exc.read()
        try:
            root=ET.fromstring(body)
            error={k:root.findtext(k) for k in ['Code','Message']}
        except ET.ParseError:error={'message':'Non-XML error body; omitted'}
        checks.append({'name':item['name'],'status':'unreadable','http_status':exc.code,'error':error})
(ROOT/'raw/WF01_output_access_checks.json').write_text(json.dumps(checks,indent=2))
print(json.dumps(checks,indent=2))
