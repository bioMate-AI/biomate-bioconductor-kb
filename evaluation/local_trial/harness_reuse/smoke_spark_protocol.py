import json,time,urllib.request
from pathlib import Path
base='http://127.0.0.1:18001'
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
body={'model':'qwen3.5:27b','messages':[{'role':'user','content':'Call lookup_workflow with query="cyclic peptide permeability". Do not answer in prose.'}],'tools':[{'type':'function','function':{'name':'lookup_workflow','description':'Find a workflow in the local BioMate catalog.','parameters':{'type':'object','properties':{'query':{'type':'string'}},'required':['query']}}}],'stream':False,'max_tokens':256,'temperature':0,'reasoning_effort':'none'}
start=time.monotonic()
try:
    req=urllib.request.Request(base+'/v1/chat/completions',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
    with opener.open(req,timeout=120) as r: result=json.load(r)
    m=result['choices'][0]['message']; calls=m.get('tool_calls',[])
    passed=bool(calls) and calls[0]['function']['name']=='lookup_workflow' and json.loads(calls[0]['function']['arguments']).get('query')=='cyclic peptide permeability'
    output={'passed':passed,'elapsed_seconds':round(time.monotonic()-start,2),'model':result.get('model'),'finish_reason':result['choices'][0].get('finish_reason'),'tool_calls':calls,'content':m.get('content'),'usage':result.get('usage')}
except Exception as exc:
    output={'passed':False,'error':str(exc),'elapsed_seconds':round(time.monotonic()-start,2)}
Path('evaluation/local_trial/harness_reuse/results/spark_qwen35_27b/protocol_smoke.json').write_text(json.dumps(output,indent=2)+'\n')
print(json.dumps(output))
