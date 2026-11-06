#!/usr/bin/env python3
"""Measure socket reachability; compare sandbox results with an unrestricted control."""
import argparse,errno,json,socket
from pathlib import Path

parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);parser.add_argument('--expect',choices=['denied','reachable'],default='denied');args=parser.parse_args()
checks=[]
for address in ('1.1.1.1','8.8.8.8'):
    row={'address':address,'port':443,'connected':False,'policy_denial_observed':False}
    try:
        with socket.create_connection((address,443),timeout=3):row['connected']=True
    except OSError as exc:
        row['errno']=exc.errno
        row['error_type']=type(exc).__name__
        row['policy_denial_observed']=exc.errno in (errno.EPERM,errno.EACCES)
    checks.append(row)
report={'passed':all(r['connected']==(args.expect=='reachable') for r in checks),'expected':args.expect,'checks':checks,
    'scope':'IPv4 connectivity observation only; require successful unrestricted control and recorded sandbox configuration before attributing denial to policy'}
args.output.write_text(json.dumps(report,indent=2));print(json.dumps(report))
raise SystemExit(0 if report['passed'] else 1)
