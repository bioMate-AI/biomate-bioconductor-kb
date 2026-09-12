#!/usr/bin/env python3
"""Publish consistent, immutable S3 snapshots; commit manifest last; verify on restore.

Call seal only after the producer finishes writing (Trainer.on_save or a quiescent
artifact bundle). Files must be <=5 GiB; shard larger training state first.
"""
import argparse
import base64
import hashlib
import json
import os
import shutil
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

READY = '.biomate-ready.json'
LIMIT = 5 * 1024**3

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(8*1024*1024), b''): h.update(chunk)
    return h.hexdigest()

def safe_path(name):
    p = PurePosixPath(name)
    if not name or p.is_absolute() or '..' in p.parts or '\\' in name: raise ValueError('Unsafe snapshot path')
    return p

def inventory(source):
    files = []
    for path in sorted(source.rglob('*')):
        if path.is_symlink(): raise ValueError('Snapshot may not contain symlinks')
        if not path.is_file() or path.name == READY: continue
        size = path.stat().st_size
        if size > LIMIT: raise ValueError('Shard checkpoint files to <=5 GiB before backup')
        files.append({'path':path.relative_to(source).as_posix(),'size':size,'sha256':sha(path)})
    if not files: raise ValueError('Empty snapshot')
    return files

def seal(source, metadata):
    source = Path(source).resolve()
    files = inventory(source)
    if metadata.get('kind') == 'training':
        names = [f['path'] for f in files]
        if not metadata.get('base_model_revision') or not metadata.get('dataset_manifest_sha256'):
            raise ValueError('Training checkpoint requires model revision and dataset manifest hash')
        for required in ('trainer_state.json', 'optimizer.pt', 'scheduler.pt'):
            if required not in names: raise ValueError('Full Trainer checkpoint missing '+required)
        if not any(Path(n).name.startswith('rng_state') for n in names): raise ValueError('Missing RNG state')
        if not any(n.endswith('.safetensors') or n.endswith('pytorch_model.bin') for n in names): raise ValueError('Missing model/adapter weights')
    elif metadata.get('kind') != 'artifact_bundle': raise ValueError('Unknown snapshot kind')
    manifest = {'format':'biomate-snapshot-v1','created_at':datetime.now(timezone.utc).isoformat(), 'metadata':metadata,'files':files}
    tmp = source/(READY+'.tmp')
    tmp.write_text(json.dumps(manifest,indent=2));os.replace(tmp,source/READY)
    return manifest

def verify(source, manifest):
    for row in manifest['files']:
        path = source / str(safe_path(row['path']))
        if path.is_symlink() or not path.is_file() or path.stat().st_size != row['size'] or sha(path) != row['sha256']:
            raise ValueError('Snapshot file changed or corrupt: '+row['path'])

def put(client, bucket, key, body, checksum):
    response = client.put_object(Bucket=bucket,Key=key,Body=body,ServerSideEncryption='AES256',
        ChecksumSHA256=base64.b64encode(bytes.fromhex(checksum)).decode(),IfNoneMatch='*')
    if response.get('ChecksumSHA256') != base64.b64encode(bytes.fromhex(checksum)).decode():
        raise ValueError('S3 did not acknowledge matching checksum')

def publish(source, bucket, prefix, client):
    source=Path(source).resolve()
    manifest=json.loads((source/READY).read_text())
    verify(source,manifest)
    # Unique immutable generation: older committed snapshots remain restorable.
    key=prefix.strip('/')+'/snapshots/'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex
    for row in manifest['files']:
        with (source/row['path']).open('rb') as f: put(client,bucket,key+'/files/'+row['path'],f,row['sha256'])
    verify(source,manifest)  # producer mutation prevents publication
    manifest['snapshot_key']=key
    payload=json.dumps(manifest,sort_keys=True).encode()
    put(client,bucket,key+'/manifest.json',payload,hashlib.sha256(payload).hexdigest())
    return {'bucket':bucket,'manifest_key':key+'/manifest.json','manifest_sha256':hashlib.sha256(payload).hexdigest(),'file_count':len(manifest['files'])}

def restore(bucket,key,destination,client,expected_sha=None):
    destination=Path(destination)
    if destination.exists(): raise ValueError('Restore destination must not exist')
    data=client.get_object(Bucket=bucket,Key=key)['Body'].read()
    if expected_sha and hashlib.sha256(data).hexdigest()!=expected_sha:raise ValueError('Manifest checksum mismatch')
    manifest=json.loads(data)
    if manifest.get('format')!='biomate-snapshot-v1' or key!=manifest.get('snapshot_key','')+'/manifest.json':raise ValueError('Invalid committed snapshot')
    destination.parent.mkdir(parents=True,exist_ok=True)
    stage=Path(tempfile.mkdtemp(prefix='.biomate-restore-',dir=destination.parent))
    try:
        for row in manifest['files']:
            relative=str(safe_path(row['path']));target=stage/relative;target.parent.mkdir(parents=True,exist_ok=True)
            body=client.get_object(Bucket=bucket,Key=manifest['snapshot_key']+'/files/'+relative)['Body']
            with target.open('wb') as f:
                for chunk in iter(lambda:body.read(8*1024*1024),b''):f.write(chunk)
        verify(stage,manifest)
        (stage/READY).write_text(json.dumps(manifest,indent=2))
        os.rename(stage,destination)
    finally:
        if stage.exists():shutil.rmtree(stage)
    return manifest

def main():
    ap=argparse.ArgumentParser();sub=ap.add_subparsers(dest='command',required=True)
    s=sub.add_parser('seal');s.add_argument('source',type=Path);s.add_argument('--metadata',type=Path,required=True)
    p=sub.add_parser('push');p.add_argument('source',type=Path);p.add_argument('--bucket',required=True);p.add_argument('--prefix',required=True)
    r=sub.add_parser('restore');r.add_argument('destination',type=Path);r.add_argument('--bucket',required=True);r.add_argument('--manifest-key',required=True);r.add_argument('--manifest-sha256')
    args=ap.parse_args()
    if args.command=='seal':result=seal(args.source,json.loads(args.metadata.read_text()))
    else:
        import boto3
        client=boto3.client('s3')
        if args.command=='push':result=publish(args.source,args.bucket,args.prefix,client)
        else:result=restore(args.bucket,args.manifest_key,args.destination,client,args.manifest_sha256)
    print(json.dumps(result,indent=2))
if __name__=='__main__':main()
