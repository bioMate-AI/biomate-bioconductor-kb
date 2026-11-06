"""Reuse existing S3 PepBench objects, otherwise acquire checksum-pinned originals."""
import argparse
import hashlib
import json
from pathlib import Path

import boto3
import requests


def digest(path, algorithm):
    h = hashlib.new(algorithm)
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def collect(bucket, root, metadata):
    root.mkdir(parents=True, exist_ok=True)
    s3 = boto3.client('s3')
    files = metadata['files']
    wanted = {f['key'] for f in files}
    existing = {name: [] for name in wanted}
    pages = objects = 0
    for page in s3.get_paginator('list_objects_v2').paginate(Bucket=bucket):
        pages += 1
        for obj in page.get('Contents', []):
            objects += 1
            name = obj['Key'].rsplit('/', 1)[-1]
            if name in wanted and ('pepbench' in obj['Key'].lower() or name != 'README.md'):
                existing[name].append(obj)
    print(json.dumps({'inventory_pages': pages, 'inventory_objects': objects}), flush=True)
    records = []
    for source in files:
        name = source['key']
        path = root / name
        expected = source['checksum'].split(':', 1)[1]
        match = next((o for o in existing[name] if o['Size'] == source['size']), None)
        origin = source['links']['self']
        if match:
            s3.download_file(bucket, match['Key'], str(path))
            origin = 's3://' + bucket + '/' + match['Key']
            if digest(path, 'md5') != expected:
                raise RuntimeError('Existing same-name object fails upstream checksum: ' + origin)
        else:
            print('Downloading ' + name, flush=True)
            with requests.get(origin, stream=True, timeout=(30, 120)) as response:
                response.raise_for_status()
                with path.open('wb') as output:
                    for chunk in response.iter_content(8 * 1024 * 1024):
                        output.write(chunk)
        if path.stat().st_size != source['size'] or digest(path, 'md5') != expected:
            raise RuntimeError('Size or MD5 mismatch: ' + name)
        sha = digest(path, 'sha256')
        key = match['Key'] if match else 'cyclic_peptide/datasets/pepbench/v2/' + name
        if not match:
            with path.open('rb') as stream:
                s3.put_object(Bucket=bucket, Key=key, Body=stream, IfNoneMatch='*',
                              Metadata={'sha256': sha, 'source-md5': expected,
                                        'zenodo-record': '13373108', 'license': 'CC-BY-4.0'})
        head = s3.head_object(Bucket=bucket, Key=key)
        if head['ContentLength'] != source['size']:
            raise RuntimeError('S3 size verification failed')
        # Full streamed readback verifies bytes, independent of multipart ETag.
        remote_hash = hashlib.sha256()
        body = s3.get_object(Bucket=bucket, Key=key)['Body']
        try:
            for chunk in body.iter_chunks(8 * 1024 * 1024):
                remote_hash.update(chunk)
        finally:
            body.close()
        if remote_hash.hexdigest() != sha:
            raise RuntimeError('S3 readback checksum failed')
        records.append({'name': name, 'bytes': source['size'], 'sha256': sha,
                        'upstream_md5': expected, 'acquired_from': origin,
                        's3_uri': 's3://' + bucket + '/' + key,
                        'reused': bool(match), 'readback_verified': True,
                        'role': 'held_out_test' if name == 'LNR.tar.gz' else
                                'augmentation_reserved' if name == 'ProtFrag.tar.gz' else
                                'train_validation' if name == 'train_valid.tar.gz' else 'documentation'})
        (root / 'acquisition_manifest.json').write_text(json.dumps(records, indent=2) + '\n')
        print(json.dumps(records[-1]), flush=True)
    return records


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bucket', required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--metadata', type=Path, required=True)
    parser.add_argument('--include', nargs='+', help='Only these exact upstream filenames')
    args = parser.parse_args()
    metadata = json.loads(args.metadata.read_text())
    if args.include:
        names = {f['key'] for f in metadata['files']}
        if not set(args.include) <= names:
            raise ValueError('Unknown upstream filename')
        metadata['files'] = [f for f in metadata['files'] if f['key'] in args.include]
    collect(args.bucket, args.out, metadata)
