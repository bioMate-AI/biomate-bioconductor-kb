#!/usr/bin/env python3
"""Run transparent synthetic BioMate development diagnostics against a local server."""
import argparse,json,time,urllib.request
from pathlib import Path
from smoke import NoRedirect
p=argparse.ArgumentParser();p.add_argument('--url',default='http://127.0.0.1:8000/v1');p.add_argument('--model',default='Qwen/Qwen3.8-27B');p.add_argument('--cases',type=Path,default=Path(__file__).with_name('core_cases.json'));p.add_argument('--output',type=Path,required=True);a=p.parse_args()
data=json.loads(a.cases.read_text());opener=urllib.request.build_opener(NoRedirect());results=[]
for case in data['cases']:
    start=time.monotonic();record={'id':case['id'],'task_id':case['task_id'],'passed':False}
    try:
        body={'model':a.model,'messages':[{'role':'system','content':'You are BioMate. Use the supplied evidence, preserve explicit constraints, and return exactly the requested JSON keys.'},{'role':'user','content':case['prompt']}], 'max_tokens':256,'temperature':0,'chat_template_kwargs':{'enable_thinking':False},'response_format':{'type':'json_object'}}
        req=urllib.request.Request(a.url.rstrip('/')+'/chat/completions',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
        with opener.open(req,timeout=600) as response:r=json.load(response)
        choice=r['choices'][0];answer=json.loads(choice['message']['content']);record.update({'passed':choice['finish_reason']=='stop' and answer==case['expected'],'answer':answer,'expected':case['expected'],'usage':r.get('usage')})
    except Exception as e:record['error']=str(e)
    record['seconds']=round(time.monotonic()-start,3);results.append(record)
    report={'scope':data['scope'],'model':a.model,'results':results,'passed':sum(r['passed'] for r in results),'completed':len(results),'total':len(data['cases'])}
    tmp=a.output.with_suffix('.tmp');tmp.write_text(json.dumps(report,indent=2));tmp.replace(a.output)
    print(json.dumps(record),flush=True)
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
