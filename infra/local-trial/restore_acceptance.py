#!/usr/bin/env python3
"""Restore committed synthetic evidence and independently recheck FastQC artifacts."""
import json
from pathlib import Path
import boto3
from checkpoint_store import restore,verify,READY
from verify_fastqc import verify as verify_fastqc

root=Path('/opt/biomate-trial');results={}
receipts=json.loads((root/'acceptance-backup-receipts.json').read_text())
for name,receipt in receipts.items():
    target=root/'acceptance-restored'/name/receipt['manifest_sha256']
    if target.exists():
        manifest=json.loads((target/READY).read_text())
        if manifest['snapshot_key']+'/manifest.json'!=receipt['manifest_key']:raise ValueError('Restored snapshot differs from requested receipt')
        verify(target,manifest)
    else:restore(receipt['bucket'],receipt['manifest_key'],target,boto3.client('s3'),receipt['manifest_sha256'])
    html=list(target.rglob('*.html'));archive=list(target.rglob('*.zip'))
    if len(html)!=1 or len(archive)!=1:raise ValueError('Ambiguous restored artifacts')
    results[name]=verify_fastqc(html[0],archive[0])
(root/'acceptance-restore-verification.json').write_text(json.dumps(results,indent=2))
print(json.dumps({'restored_and_reverified':list(results)}))
