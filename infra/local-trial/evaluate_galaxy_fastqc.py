#!/usr/bin/env python3
"""Execute an imported Galaxy workflow on synthetic reads and verify downloaded artifacts."""
import json,secrets,time,urllib.request,urllib.error
from pathlib import Path
from verify_fastqc import verify

ROOT=Path('/opt/biomate-trial')
BASE='http://127.0.0.1:8082/api'

def request(path,key,body=None):
    req=urllib.request.Request(BASE+path,data=None if body is None else json.dumps(body).encode(),
        headers={'x-api-key':key,'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req,timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        try:message=json.loads(exc.read()).get('err_msg','No structured error message')
        except Exception:message='No structured error message'
        raise RuntimeError(f'Galaxy {path}: HTTP {exc.code}: {str(message)[:2000]}') from None

def main():
    report={'passed':False,'scope':'Actual Galaxy workflow and artifacts on synthetic reads; no LLM orchestration'}
    start=time.monotonic()
    output=ROOT/'galaxy-fastqc-evaluation';output.mkdir(exist_ok=True)
    def save():
        report['seconds']=round(time.monotonic()-start,3)
        temporary=output/'result.tmp';temporary.write_text(json.dumps(report,indent=2));temporary.replace(output/'result.json')
    try:
        bootstrap=(ROOT/'galaxy-state/bootstrap-admin.key').read_text().strip()
        suffix=secrets.token_hex(5)
        user=request('/users',bootstrap,{'email':f'trial-{suffix}@example.org','username':f'trial-{suffix}','password':secrets.token_urlsafe(24)})
        user_id=user['id']
        key=request(f'/users/{user_id}/api_key',bootstrap,{})
        history=request('/histories',key,{'name':f'BioMate synthetic FastQC acceptance {suffix}'})
        report['history_id']=history['id'];save()
        reads=''.join(f'@trial_{i}\n'+'ACGT'*25+'\n+\n'+'I'*100+'\n' for i in range(100))
        upload=request('/tools',key,{'history_id':history['id'],'tool_id':'upload1','inputs':{'files_0|url_paste':reads,'files_0|NAME':'synthetic.fastq','file_type':'fastqsanger','dbkey':'?'}})
        dataset=upload['outputs'][0]['id'];report['input_dataset_id']=dataset;save()
        def wait_dataset(identifier):
            for _ in range(180):
                item=request(f'/histories/{history["id"]}/contents/{identifier}',key)
                if item['state']=='ok':return item
                if item['state'] in ('error','discarded','failed_metadata'):raise RuntimeError(f'Dataset {identifier}: {item["state"]}')
                time.sleep(2)
            raise TimeoutError('Dataset readiness timeout')
        wait_dataset(dataset)
        workflow={'a_galaxy_workflow':'true','format-version':'0.1','annotation':'Synthetic functional acceptance; not biological validation','tags':[],'name':'BioMate synthetic FastQC acceptance','steps':{
            '0':{'id':0,'type':'data_input','name':'Reads','label':'Reads','tool_state':json.dumps({'name':'Reads'}),'inputs':[{'name':'Reads','description':''}],'input_connections':{},'position':{'left':0,'top':0}},
            '1':{'id':1,'type':'tool','tool_id':'biomate_trial_fastqc','tool_version':'0.12.1','name':'BioMate trial FastQC','tool_state':json.dumps({'reads':{'__class__':'ConnectedValue'},'threads':1}),'input_connections':{'reads':{'id':0,'output_name':'output'}},'position':{'left':200,'top':0},'workflow_outputs':[{'output_name':'html','label':'html'},{'output_name':'archive','label':'archive'}]}}}
        imported=request('/workflows',key,{'workflow':workflow})
        report['workflow_id']=imported['id'];save()
        invocation=request(f'/workflows/{imported["id"]}/invocations',key,{'history':'hist_id='+history['id'],'inputs':{'0':{'src':'hda','id':dataset}},'inputs_by':'step_index'})
        if isinstance(invocation,list):invocation=invocation[0]
        report['invocation_id']=invocation['id'];save()
        for _ in range(180):
            invocation=request(f'/invocations/{invocation["id"]}',key)
            if invocation['state']=='scheduled':break
            if invocation['state'] in ('failed','cancelled'):raise RuntimeError('Invocation '+invocation['state'])
            time.sleep(2)
        else:raise TimeoutError('Workflow scheduling timeout')
        report['invocation_state']=invocation['state']
        outputs=invocation.get('outputs',{})
        # Galaxy maps labeled workflow outputs to history dataset references.
        for name,extension in [('html','html'),('archive','zip')]:
            identifier=outputs[name]['id']
            wait_dataset(identifier)
            req=urllib.request.Request(BASE+f'/histories/{history["id"]}/contents/{identifier}/display',headers={'x-api-key':key})
            with urllib.request.urlopen(req,timeout=60) as response:(output/f'report.{extension}').write_bytes(response.read())
        report['outputs']=outputs
        report['artifacts']=verify(output/'report.html',output/'report.zip')
        report['passed']=True
    except Exception as exc:
        report['error']=str(exc)
    save();print(json.dumps(report,indent=2))
    return 0 if report['passed'] else 1

if __name__=='__main__':raise SystemExit(main())
