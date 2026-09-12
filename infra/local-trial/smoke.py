#!/usr/bin/env python3
"""Small live-server diagnostic. Synthetic cases only; not the release benchmark."""
import argparse
import json
import time
import urllib.request
from pathlib import Path

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs): return None

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', default='http://127.0.0.1:8000/v1')
    parser.add_argument('--model', default='Qwen/Qwen3.8-27B')
    parser.add_argument('--output', default='trial-smoke-results.json')
    parser.add_argument('--timeout', type=float, default=180, help='Per-request seconds; allow longer for CPU or queued diagnostics')
    args = parser.parse_args()
    opener = urllib.request.build_opener(NoRedirect())
    results = []
    def call(messages, **kwargs):
        body = {'model': args.model, 'messages': messages, 'max_tokens': 1024, 'temperature': 0,
                'chat_template_kwargs': {'enable_thinking': False}, **kwargs}
        request = urllib.request.Request(args.url.rstrip('/')+'/chat/completions',
            data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
        started = time.monotonic()
        with opener.open(request, timeout=args.timeout) as response: value = json.load(response)
        return value, round(time.monotonic()-started, 3)
    def run(name, fn):
        try: results.append({'case': name, **fn()})
        except Exception as exc: results.append({'case': name, 'passed': False, 'error': str(exc)})
    def exact_json():
        r,t = call([{'role':'user','content':'Return a JSON object with exactly accession="GSE12345" and platform="GPL96". Preserve these identifiers exactly.'}], response_format={'type':'json_object'})
        c=r['choices'][0]
        record = {'passed': False, 'seconds': t, 'response': r}
        try:
            record['passed'] = c['finish_reason']=='stop' and json.loads(c['message']['content'])=={'accession':'GSE12345','platform':'GPL96'}
        except (ValueError, TypeError) as exc:
            record['error'] = str(exc)
        return record
    def tool_loop():
        tools=[{'type':'function','function':{'name':'list_history','description':'Look up recent workflow runs.','parameters':{'type':'object','properties':{},'additionalProperties':False}}}]
        messages=[{'role':'system','content':'Use list_history to answer run-history questions. Never invent a run. After receiving the result, report its run ID and status.'}, {'role':'user','content':'What was my latest run?'}]
        r,t=call(messages, tools=tools, tool_choice='auto'); c=r['choices'][0]; calls=c['message'].get('tool_calls',[])
        if c['finish_reason']!='tool_calls' or len(calls)!=1 or calls[0]['function']['name']!='list_history' or json.loads(calls[0]['function']['arguments'])!={}: return {'passed':False,'seconds':t,'response':r}
        messages += [c['message'],{'role':'tool','tool_call_id':calls[0]['id'],'content':'{"run_id":"fixture-run-729","status":"failed","outputs":[]}'}]
        final,t2=call(messages,tools=tools,tool_choice='auto'); answer=final['choices'][0]
        text=answer['message'].get('content') or ''
        return {'passed':answer['finish_reason']=='stop' and 'fixture-run-729' in text and 'failed' in text.lower(),'seconds':t+t2,'response':final,'first_response':r}
    run('identifier_json',exact_json);run('tool_round_trip',tool_loop)
    Path(args.output).write_text(json.dumps({'scope':'synthetic live transport smoke, not scientific acceptance','model':args.model,'results':results},indent=2))
    print(json.dumps([{k:v for k,v in r.items() if k not in ('response','first_response')} for r in results],indent=2))
    return 0 if all(r['passed'] for r in results) else 1

if __name__=='__main__':raise SystemExit(main())
