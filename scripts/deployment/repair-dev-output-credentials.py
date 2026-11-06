#!/usr/bin/env python3
"""Run ON the dev host. Remove confirmed invalid NF overrides; preserve rollback.
No credentials are printed. This does not deploy repository code.
"""
import argparse, http.client, json, os, pathlib, shutil, socket, subprocess, time

NAME = 'biomate-dev-frontend'
BAD = {'AWS_NF_ACCESS_KEY_ID', 'AWS_NF_SECRET_ACCESS_KEY'}


def docker(*args):
    return subprocess.check_output(['docker', *args], text=True).strip()


class DockerHTTP(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect('/var/run/docker.sock')


def healthy():
    try:
        c = http.client.HTTPConnection('localhost', 3000, timeout=5)
        c.request('GET', '/api/health')
        r = c.getresponse(); ok = r.status == 200; r.read(); c.close()
        return ok
    except (OSError, http.client.HTTPException):
        return False


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--apply', action='store_true'); args = ap.parse_args()
    c = json.loads(docker('inspect', NAME))[0]
    env = dict(x.split('=', 1) for x in c['Config']['Env'])
    assert all(env.get(k) for k in BAD), 'No NF overrides: stop and reassess'
    assert healthy(), 'Dev must be healthy before a configuration swap'
    assert list(c['NetworkSettings']['Networks']) == ['biomate-dev-net']
    source = pathlib.Path('/opt/biomate/.env')
    old = source.read_text()
    entries = dict(l.split('=', 1) for l in old.splitlines() if '=' in l and not l.startswith('#'))
    assert all(entries.get(k) == env.get(k) for k in BAD | {'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY'}), 'Configuration drift'
    # Verify default credentials still read the exact failed object before mutation.
    js = '''const {S3Client,HeadObjectCommand}=require('@aws-sdk/client-s3');
const c=new S3Client({region:'us-east-1',followRegionRedirects:true});
c.send(new HeadObjectCommand({Bucket:'biomate-nextflow-work',Key:'nextflow/outputs/fd5a73ac-87df-4850-b8ff-6d768c1b47fb/b56621a0/run/pk_summary.json'}),{abortSignal:AbortSignal.timeout(10000)}).then(r=>{if(r.ContentLength!==1656)process.exitCode=2;else console.log('default-read-ok');}).catch(e=>{console.error(e.name);process.exitCode=1;}).finally(()=>c.destroy());'''
    assert docker('exec', '-w', '/app', NAME, 'node', '-e', js) == 'default-read-ok'
    print('Preflight passed: healthy dev, exact config match, default S3 read succeeds')
    if not args.apply:
        return
    stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())
    backup_name = f'{NAME}-pre-output-repair-{stamp}'
    backup_dir = pathlib.Path('/opt/biomate/credential-repair-backups') / stamp
    backup_dir.mkdir(parents=True, mode=0o700)
    os.chmod(backup_dir, 0o700)
    shutil.copy2(source, backup_dir / 'environment'); os.chmod(backup_dir / 'environment', 0o600)
    # Preserve installed packages, static assets, and all other writable-layer changes.
    snapshot = docker('commit', NAME, f'biomate-dev-output-repair:{stamp.lower()}')
    cfg = dict(c['Config']); cfg['Image'] = snapshot
    cfg['Env'] = [x for x in cfg['Env'] if x.split('=', 1)[0] not in BAD] + [f'{k}=' for k in sorted(BAD)]
    cfg['Hostname'] = ''
    cfg['HostConfig'] = c['HostConfig']
    cfg['NetworkingConfig'] = {'EndpointsConfig': {'biomate-dev-net': {}}}
    # Record only safe metadata locally to the host.
    (backup_dir / 'receipt.json').write_text(json.dumps({'oldContainer': c['Id'], 'backupName': backup_name, 'snapshot': snapshot, 'removedKeys': sorted(BAD)}, indent=2))
    renamed = False; created = False
    try:
        cleaned = ''.join(l for l in old.splitlines(keepends=True) if l.split('=', 1)[0] not in BAD)
        source.write_text(cleaned)
        docker('stop', '-t', '20', NAME)
        docker('rename', NAME, backup_name); renamed = True
        conn = DockerHTTP('localhost', timeout=30)
        conn.request('POST', f'/containers/create?name={NAME}', json.dumps(cfg), {'Content-Type': 'application/json'})
        response = conn.getresponse(); body = json.loads(response.read()); conn.close()
        if response.status != 201:
            raise RuntimeError(f'Docker create failed ({response.status})')
        created = True
        docker('start', NAME)
        for _ in range(30):
            if healthy():
                print(json.dumps({'status': 'healthy', 'backupContainer': backup_name, 'backupDirectory': str(backup_dir), 'removedKeys': sorted(BAD)}))
                return
            time.sleep(2)
        raise RuntimeError('Health check failed after configuration swap')
    except BaseException:
        source.write_text(old)
        if created:
            docker('rm', '-f', NAME)
        if renamed:
            docker('rename', backup_name, NAME)
        docker('start', NAME)
        print('Configuration and original container restored')
        raise


if __name__ == '__main__':
    main()
