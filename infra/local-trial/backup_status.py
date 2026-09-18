#!/usr/bin/env python3
"""Snapshot worker progress periodically. These are status artifacts, not model checkpoints."""
import json,subprocess,tempfile
from pathlib import Path
import boto3
from checkpoint_store import seal,publish
root=Path('/opt/biomate-trial')
with tempfile.TemporaryDirectory(prefix='biomate-progress-') as temporary:
    out=Path(temporary)
    log=subprocess.run(['journalctl','-u','biomate-cpu-prepare','-u','biomate-local-llm','-n','300','--no-pager'],capture_output=True,text=True)
    (out/'worker.log').write_text(log.stdout)
    for name in ['model-pin.json','knowledge-restore-check.json','quantized-backup-receipt.json','quantized-restore-result.json','base-model-manifest.json','model-size-check.json','llama-source-revision.txt','python-environment.txt','live-smoke.json','live-smoke-diagnosis.json','biomate-core-live.json','biomate-json-live.json','core-evaluation.json','evaluation-exit-status.json','MODEL_READY','application-evaluation.json','app-python-environment.txt','APP_DEPENDENCIES_READY','recovery-verification.json','acceptance-backup-receipts.json','acceptance-restore-verification.json','network-control.json','network-biomate-trial-frontend.service.json','network-biomate-trial-backend.service.json','network-biomate-local-llm.service.json','application-before-offline-routing.json']:
        p=root/name
        if p.is_file():(out/name).write_bytes(p.read_bytes())
    fastqc=root/'fastqc-evaluation/result.json'
    if fastqc.is_file():(out/'fastqc-evaluation.json').write_bytes(fastqc.read_bytes())
    galaxy=root/'galaxy-fastqc-evaluation/result.json'
    if galaxy.is_file():(out/'galaxy-fastqc-evaluation.json').write_bytes(galaxy.read_bytes())
    state=subprocess.run(['systemctl','show','biomate-cpu-prepare','--property=ActiveState,SubState,Result'],capture_output=True,text=True)
    (out/'worker-state.txt').write_text(state.stdout)
    seal(out,{'kind':'artifact_bundle','scope':'BioMate CPU worker progress; not a training checkpoint'})
    receipt=publish(out,'biomate-models-399683337364','biomate-core-local-trial/20260912/progress',boto3.client('s3'))
    (root/'last-progress-backup.json').write_text(json.dumps(receipt,indent=2))
    print(json.dumps(receipt))
