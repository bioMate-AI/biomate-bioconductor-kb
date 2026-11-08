"""Fetch verified checkpoint data on EC2 Spot only; never import model code.

Usage: python3 fetch_pinned_checkpoints.py MANIFEST MANIFEST_SHA256 DEST MODEL
MODEL is chemfm1b, pclm2/base or pclm2/small. Manifest lives in project S3.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import urllib.request


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def main():
    manifest, expected, destination, model = sys.argv[1:]
    if model not in ('chemfm1b', 'pclm2/base', 'pclm2/small'):
        raise ValueError('unknown model')
    # Reject laptop execution before creating directories or downloading files.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    req = urllib.request.Request('http://169.254.169.254/latest/api/token',
        method='PUT', headers={'X-aws-ec2-metadata-token-ttl-seconds': '60'})
    with opener.open(req, timeout=3) as response:
        token = response.read().decode()
    req = urllib.request.Request('http://169.254.169.254/latest/meta-data/instance-life-cycle',
        headers={'X-aws-ec2-metadata-token': token})
    with opener.open(req, timeout=3) as response:
        if response.read().decode() != 'spot':
            raise RuntimeError('EC2 Spot required')
    manifest = Path(manifest)
    if digest(manifest) != expected:
        raise ValueError('manifest hash mismatch')
    records = json.loads(manifest.read_text())['files']
    chosen = [r for r in records if r['relative_path'].startswith(model + '/')]
    if not chosen:
        raise ValueError('empty model manifest')
    for row in chosen:
        relative = Path(row['relative_path'])
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('invalid checkpoint path')
        path = Path(destination) / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and path.stat().st_size == row['bytes'] and digest(path) == row['sha256']:
            continue
        temp = path.with_name(path.name + '.partial')
        if row['source'].startswith('s3://biomate-nextflow-work/'):
            subprocess.run(['aws', 's3', 'cp', row['source'], str(temp), '--only-show-errors'], check=True)
        elif row['source'].startswith('https://huggingface.co/'):
            urllib.request.urlretrieve(row['source'], temp)
        else:
            raise ValueError('unsupported checkpoint source')
        if temp.stat().st_size != row['bytes'] or digest(temp) != row['sha256']:
            temp.unlink()
            raise ValueError('checkpoint hash or length mismatch: ' + str(relative))
        temp.replace(path)
        print('verified ' + str(relative), flush=True)


if __name__ == '__main__':
    main()
