"""Archive pinned official dataset files with Git-blob and S3 SHA256 checks."""
import boto3
import concurrent.futures
import hashlib
import json
import subprocess
import tarfile
import time
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
BUCKET = 'knowledge-datasets-1759951976'


def collect(repo, name, select):
    tree = json.loads((ROOT / 'data/source_metadata' / (repo.replace('/', '_') + '_tree.json')).read_text())
    revision = tree['source_commit']
    files = [x for x in tree['tree'] if x['type'] == 'blob' and (select(x['path']) or x['path'] in ['LICENSE', 'README.md'])]
    destination = ROOT / 'data/raw' / name / revision
    destination.mkdir(parents=True, exist_ok=True)

    def fetch(entry):
        url = 'https://raw.githubusercontent.com/' + repo + '/' + revision + '/' + entry['path']
        target = destination / entry['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        blob = None
        if target.exists():
            blob = target.read_bytes()
        if blob is None:
            for attempt in range(3):
                try:
                    with urlopen(Request(url, headers={'User-Agent': 'peptide-data-audit'}), timeout=30) as response:
                        blob = response.read()
                    break
                except Exception:
                    if attempt == 2:
                        raise
                    time.sleep(2)
        digest = hashlib.sha1(b'blob ' + str(len(blob)).encode() + b'\0' + blob).hexdigest()
        if digest != entry['sha'] or len(blob) != entry['size']:
            raise ValueError('Pinned Git blob mismatch: ' + entry['path'])
        target.write_bytes(blob)
        return {'path': entry['path'], 'bytes': len(blob), 'git_blob_sha1': digest,
                'sha256': hashlib.sha256(blob).hexdigest(), 'source_url': url}

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        records = list(pool.map(fetch, files))
    archive = destination / 'dataset.tar.gz'
    with tarfile.open(archive, 'w:gz') as tf:
        for record in records:
            tf.add(destination / record['path'], arcname=record['path'])
    sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    key = 'cyclic_peptide/datasets/' + name + '/' + revision + '/dataset.tar.gz'
    aws = ['aws', 's3api', '--region', 'us-west-2']
    head = subprocess.run(aws + ['head-object', '--bucket', BUCKET, '--key', key], capture_output=True, text=True)
    if head.returncode == 0:
        stored = json.loads(head.stdout).get('Metadata', {}).get('sha256')
        if not stored:
            raise RuntimeError('Existing object lacks expected integrity metadata')
        sha = stored
    else:
        if '404' not in head.stderr and 'Not Found' not in head.stderr:
            raise RuntimeError(head.stderr)
        with archive.open('rb') as body:
            boto3.client('s3', region_name='us-west-2').put_object(
                Bucket=BUCKET, Key=key, Body=body, IfNoneMatch='*',
                Metadata={'sha256': sha, 'source-revision': revision})
    readback = destination / 'readback.tar.gz'
    subprocess.run(aws + ['get-object', '--bucket', BUCKET, '--key', key, str(readback)], check=True, stdout=subprocess.DEVNULL)
    if hashlib.sha256(readback.read_bytes()).hexdigest() != sha:
        raise RuntimeError('S3 archive readback hash mismatch')
    manifest = {'dataset': name, 'repository': repo, 'source_revision': revision,
                'source_revision_kind': 'git commit SHA',
                'file_count': len(records), 'uncompressed_bytes': sum(r['bytes'] for r in records),
                's3_uri': 's3://' + BUCKET + '/' + key, 'sha256': sha, 's3_readback_verified': True,
                'qualification': 'Collected for evaluation; original assay semantics and individual source rights require provenance review before downstream release.',
                'files': records}
    (ROOT / 'results' / (name + '_acquisition.json')).write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({k: v for k, v in manifest.items() if k != 'files'}), flush=True)


if __name__ == '__main__':
    collect('bigginlab/Macroconf', 'macroconf', lambda p: p.startswith('data/'))
    collect('AaronFeller/PeptideCLM-2', 'peptideclm2_pepmsnd', lambda p: p.startswith('data/PepMSND'))
