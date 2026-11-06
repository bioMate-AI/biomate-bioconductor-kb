#!/usr/bin/env python3
"""Fetch only named synthetic trial reports; never copy worker secrets or databases."""
import argparse,json,shlex,subprocess
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('--host',required=True);p.add_argument('--identity',required=True);p.add_argument('--known-hosts',required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
names=['recovery-verification.json','acceptance-backup-receipts.json','application-evaluation.json','last-progress-backup.json','fastqc-evaluation/result.json','galaxy-fastqc-evaluation/result.json','network-control.json','network-biomate-trial-frontend.service.json','network-biomate-trial-backend.service.json','network-biomate-local-llm.service.json']
code="import json,datetime;from pathlib import Path;r=Path('/opt/biomate-trial');names="+repr(names)+";print(json.dumps({'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'reports':{n:json.loads((r/n).read_text()) for n in names if (r/n).is_file()}}))"
result=subprocess.run(['ssh','-i',args.identity,'-o','UserKnownHostsFile='+args.known_hosts,'-o','ConnectTimeout=10',args.host,'python3 -c '+shlex.quote(code)],capture_output=True,text=True,timeout=60,check=True)
evidence=json.loads(result.stdout)
args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(evidence,indent=2))
print(json.dumps({'output':str(args.output),'reports':list(evidence['reports'])}))
