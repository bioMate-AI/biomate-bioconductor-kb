#!/usr/bin/env python3
"""Exercise real BioMate HTTP chat, local inference and local knowledge retrieval."""
import json,time,urllib.request
from pathlib import Path
root=Path('/opt/biomate-trial');out=root/'application-evaluation.json'
report={'scope':'Real BioMate HTTP chat + Galaxy catalogue + local model; no scientific execution yet','passed':False}
start=time.monotonic()
def save():
    report['seconds']=round(time.monotonic()-start,3)
    tmp=out.with_suffix('.tmp');tmp.write_text(json.dumps(report,indent=2));tmp.replace(out)
def post(url,body,timeout=900):
    return urllib.request.urlopen(urllib.request.Request(url,data=json.dumps(body).encode(),headers={'Content-Type':'application/json'}),timeout=timeout)
try:
    for attempt in range(60):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8082/api/version',timeout=3) as r: report['galaxy_version']=json.load(r)
            with urllib.request.urlopen('http://127.0.0.1:5501/',timeout=5) as r: assert r.status == 200
            with urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=5) as r: assert r.status == 200
            break
        except Exception:
            if attempt==59:raise
            time.sleep(5)
    with post('http://127.0.0.1:8082/api/knowledge/query',{'query':'FastQC','limit':3}) as r:catalogue=json.load(r)
    assert any(t['name'].lower() == 'fastqc' for t in catalogue['tools']), 'FastQC query did not return the actual FastQC tool record'
    report['catalogue']=catalogue;save()
    events=[];event='message';data=[]
    prompt='Use query_knowledge to look up FastQC in the local BioMate catalogue. Summarize what inputs it requires and cite the returned tool IDs. I have not uploaded reads. Do not execute a workflow or run code.'
    with post('http://127.0.0.1:5501/api/chat/stream',{'message':prompt,'context':{}}) as response, (root/'application-events.jsonl').open('w') as stream:
        for raw in response:
            line=raw.decode().rstrip('\r\n')
            if line.startswith('event:'):event=line[6:].strip()
            elif line.startswith('data:'):data.append(line[5:].strip())
            elif not line and data:
                value=json.loads('\n'.join(data));row={'event':event,'data':value};events.append(row)
                stream.write(json.dumps(row)+'\n');stream.flush();data=[];event='message'
    report['events']=events
    calls=[e['data'] for e in events if e['event']=='tool_event' and e['data'].get('type')=='tool_call']
    observations=[e['data'] for e in events if e['event']=='tool_event' and e['data'].get('type')=='tool_result']
    finals=[e['data'] for e in events if e['event']=='final']
    report['checks']={
        'knowledge_tool_called':any(c.get('name')=='query_knowledge' for c in calls),
        'real_catalogue_observation':any('local_knowledge_database' in json.dumps(v) for v in observations),
        'no_code_execution':not any(c.get('name')=='run_code' for c in calls),
        'final_mentions_fastqc':bool(finals) and 'fastqc' in json.dumps(finals).lower(),
        'completed_without_error':any(e['event']=='done' and e['data'].get('ok') is True for e in events) and not any(e['event']=='error' for e in events),
    }
    report['passed']=all(report['checks'].values());save()
except Exception as exc:
    report['error']=str(exc);save()
print(json.dumps({k:v for k,v in report.items() if k not in ('events','catalogue')},indent=2))
raise SystemExit(0 if report['passed'] else 1)
