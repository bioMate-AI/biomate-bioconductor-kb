#!/usr/bin/env python3
"""Pin an official checkpoint revision and back up each completed file with bounded parallel transfers.

Restore verified S3 files on replacement Spot workers. A commit manifest is written
only once all files match local hashes. Partial S3 files never become a complete model.
"""
import argparse,base64,hashlib,json,os,shutil
from concurrent.futures import ThreadPoolExecutor
from threading import Lock
from pathlib import Path
import boto3
from botocore.exceptions import ClientError
from huggingface_hub import HfApi,hf_hub_download
from checkpoint_store import sha,put,LIMIT

def main():
    p=argparse.ArgumentParser();p.add_argument('--model',default='Qwen/Qwen3.8-27B');p.add_argument('--revision');p.add_argument('--workers',type=int,default=3);p.add_argument('--directory',type=Path,required=True);p.add_argument('--bucket',required=True);p.add_argument('--prefix',required=True);a=p.parse_args()
    client=boto3.client('s3')
    pin_key=a.prefix.strip('/')+'/pins/'+a.model.replace('/','--')+'.json'
    pinned=None
    try:pinned=json.loads(client.get_object(Bucket=a.bucket,Key=pin_key)['Body'].read())
    except ClientError as e:
        if e.response['Error']['Code'] not in ('404','NoSuchKey','NotFound'):raise
    if pinned and a.revision and a.revision!=pinned['revision']:raise ValueError('Requested revision differs from the frozen run pin; use a new run prefix')
    info=HfApi().model_info(a.model,revision=pinned['revision'] if pinned else a.revision,files_metadata=True)
    revision=info.sha
    if not pinned:
        pin=json.dumps({'model':a.model,'revision':revision},sort_keys=True).encode()
        put(client,a.bucket,pin_key,pin,hashlib.sha256(pin).hexdigest())
    if not revision:raise ValueError('Could not pin model revision')
    if info.safetensors and info.safetensors.total>32_000_000_000:raise ValueError('Checkpoint exceeds 32B parameter cap')
    a.directory.mkdir(parents=True,exist_ok=True)
    prefix=a.prefix.strip('/')+'/models/'+a.model.replace('/','--')+'/'+revision
    selected=[s for s in info.siblings if (s.rfilename.endswith(('.safetensors','.json','.jinja','.txt','.model','.md')) or s.rfilename == 'LICENSE') and '/' not in s.rfilename]
    if not any(s.rfilename.endswith('.safetensors') for s in selected):raise ValueError('No model weights')
    if not 1<=a.workers<=4:raise ValueError('workers must be between 1 and 4')
    completed=[];lock=Lock()
    def transfer(sibling):
        name=sibling.rfilename;target=a.directory/name;key=prefix+'/files/'+name
        if sibling.size and sibling.size>LIMIT:raise ValueError('Model shard exceeds single-object backup limit')
        expected=getattr(sibling.lfs,'sha256',None) if sibling.lfs else None
        remote=None
        try:remote=client.head_object(Bucket=a.bucket,Key=key,ChecksumMode='ENABLED')
        except ClientError as e:
            if e.response['Error']['Code'] not in ('404','NoSuchKey','NotFound'):raise
        if remote:
            remote_hash=remote.get('ChecksumSHA256')
            if not remote_hash:raise ValueError('Cached file lacks checksum')
            digest=base64.b64decode(remote_hash).hex()
            if expected and digest!=expected:raise ValueError('S3 cache differs from upstream LFS checksum')
            if not target.exists() or sha(target)!=digest:
                tmp=target.with_suffix(target.suffix+'.restoring')
                client.download_file(a.bucket,key,str(tmp))
                if sha(tmp)!=digest:raise ValueError('S3 restore checksum mismatch')
                os.replace(tmp,target)
            status='restored/verified'
        else:
            hf_hub_download(a.model,name,revision=revision,local_dir=a.directory)
            digest=sha(target)
            if expected and digest!=expected:raise ValueError('HF download checksum mismatch')
            with target.open('rb') as f:put(client,a.bucket,key,f,digest)
            status='downloaded/backed-up'
        row={'path':name,'size':target.stat().st_size,'sha256':digest,'key':key}
        with lock:
            completed.append(name)
            print(json.dumps({'file':name,'status':status,'completed_files':len(completed),'total_files':len(selected)}),flush=True)
        return row
    with ThreadPoolExecutor(max_workers=a.workers) as pool:
        rows=list(pool.map(transfer,selected))
    manifest={'model':a.model,'revision':revision,'files':rows,'parameter_count':info.safetensors.total if info.safetensors else None,'complete':True}
    data=json.dumps(manifest,sort_keys=True).encode();key=prefix+'/complete.json'
    try:put(client,a.bucket,key,data,hashlib.sha256(data).hexdigest())
    except ClientError as e:
        if e.response['Error']['Code'] not in ('PreconditionFailed','412'):raise
        if client.get_object(Bucket=a.bucket,Key=key)['Body'].read()!=data:raise ValueError('Model manifest conflict')
    (a.directory.parent/'base-model-manifest.json').write_bytes(data)
    print(json.dumps({'complete':True,'manifest_key':key,'revision':revision}),flush=True)
if __name__=='__main__':main()
