#!/usr/bin/env python3
"""Publish completed synthetic acceptance outputs; no application secrets or databases."""
import json,sys
from pathlib import Path
import boto3
from checkpoint_store import seal,publish

root=Path('/opt/biomate-trial')
receipts={}
for name in ('fastqc-evaluation','galaxy-fastqc-evaluation'):
    source=root/name
    result=json.loads((source/'result.json').read_text())
    if result.get('passed') is not True:raise RuntimeError(name+' is not a completed passing run')
    seal(source,{'kind':'artifact_bundle','scope':'BioMate synthetic acceptance evidence; no patient data','evaluation':name})
    receipts[name]=publish(source,'biomate-models-399683337364','biomate-core-local-trial/20260912/acceptance/'+name,boto3.client('s3'))
(root/'acceptance-backup-receipts.json').write_text(json.dumps(receipts,indent=2))
print(json.dumps(receipts,indent=2))
