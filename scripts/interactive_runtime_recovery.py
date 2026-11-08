#!/usr/bin/env python3
"""Review-first dev-only Galaxy Docker capability recovery.

Default: inspect and write a private plan; never stop/create/install anything.
--apply requires the exact plan digest plus BIOMATE_IT_SOCKET_APPROVED=1.
Run through sync_to_dev.sh's IT-only path under its deployment lease.
"""
import argparse
import fcntl
import hashlib
import http.client
import json
import os
from pathlib import Path
import shutil
import socket
import stat
import subprocess
import sys
import time
import urllib.parse
import urllib.request

from interactive_recreate_plan import build_payload
from interactive_state_migration import append_only_copy, manifest, verify, file_hash

# Kept in one process for consistent preflight/source fingerprints.
PROBE = r'''
import os,stat,json,sqlite3,subprocess,hashlib,sysconfig
active=[]
for line in subprocess.check_output(['ps','-eo','stat=,comm='],text=True).splitlines():
 p=line.split()
 if len(p)>1 and p[1] in ('java','nextflow') and not p[0].startswith('Z'):active.append(p[1])
c=sqlite3.connect('file:/app/database/universe.sqlite?mode=ro',uri=True)
jobs=list(c.execute("select state,count(*) from job where state in ('new','queued','running','resubmitted','waiting','upload','paused') group by state"))
def sha(p):
 h=hashlib.sha256()
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
state={}
root='/tmp/nextflow_runs'
if not os.path.isdir(root):raise RuntimeError('Expected run-state root is absent')
for parent,dirs,names in os.walk(root,followlinks=False):
 for n in ['.']+dirs+names:
  p=parent if n=='.' else os.path.join(parent,n);s=os.lstat(p);relative=os.path.relpath(p,root)
  if not stat.S_ISREG(s.st_mode) and not stat.S_ISDIR(s.st_mode):raise RuntimeError('Unsupported run-state file type')
  e={'type':'dir' if stat.S_ISDIR(s.st_mode) else 'file','mode':stat.S_IMODE(s.st_mode),'uid':s.st_uid,'gid':s.st_gid}
  if e['type']=='file':e.update(size=s.st_size,sha256=sha(p))
  state[relative]=e
code={}
for root in ['/app/lib/galaxy','/app/config','/app/tools/interactive']:
 for parent,dirs,names in os.walk(root,followlinks=False):
  for n in names:
   p=os.path.join(parent,n)
   if not os.path.islink(p) and os.path.isfile(p) and n.endswith(('.py','.md','.yml','.yaml','.xml')):code[p]=sha(p)
print(json.dumps({'activeHeads':active,'activeJobs':jobs,'runManifest':state,'codeManifest':code,'SOABI':sysconfig.get_config_var('SOABI')}))
'''


def private_json(path, body):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as output:
        json.dump(body, output, indent=2, sort_keys=True); output.write('\n')


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


class EngineConnection(http.client.HTTPConnection):
    def __init__(self):
        super().__init__('localhost', timeout=120)
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect('/var/run/docker.sock')


class Runtime:
    def docker(self, *args, timeout=120):
        process = subprocess.run(['docker', *args], capture_output=True, timeout=timeout)
        if process.returncode:
            # Never surface raw inspect/env/command output, which may carry secrets.
            raise RuntimeError('Docker operation failed: ' + args[0])
        return process.stdout.decode().strip()
    def inspect(self, name):
        return json.loads(self.docker('inspect', name))[0]
    def probe(self, name):
        return json.loads(self.docker('exec', name, 'python3', '-c', PROBE))
    def create(self, name, payload):
        connection = EngineConnection()
        try:
            connection.request('POST', '/containers/create?name=' + urllib.parse.quote(name, safe=''), json.dumps(payload), {'Content-Type': 'application/json'})
            response = connection.getresponse(); body = json.loads(response.read())
            if response.status != 201:
                raise RuntimeError('Docker create failed (HTTP ' + str(response.status) + '); original retained')
            return body['Id']
        finally:
            connection.close()
    def network(self, network, action, container, endpoint=None):
        connection = EngineConnection()
        try:
            body = {'Container': container}
            if endpoint is not None:
                body['EndpointConfig'] = endpoint
            connection.request('POST', '/networks/' + urllib.parse.quote(network, safe='') + '/' + action, json.dumps(body), {'Content-Type': 'application/json'})
            response = connection.getresponse(); response.read()
            if response.status != 200:
                raise RuntimeError('Network ' + action + ' failed; retained original requires recovery')
        finally:
            connection.close()
    def health(self, url, attempts=40):
        for _ in range(attempts):
            try:
                with urllib.request.urlopen(url, timeout=5) as response:
                    data = json.load(response)
                    if response.status == 200 and data.get('version_major'):
                        return True
            except Exception:
                pass
            time.sleep(3)
        return False


def require_quiescent(probe):
    if probe['activeHeads'] or probe['activeJobs']:
        raise RuntimeError('Active Nextflow heads/Galaxy jobs block recreation; nothing stopped')


def source_matches(before, after):
    if before['codeManifest'] != after['codeManifest'] or before['SOABI'] != after['SOABI']:
        raise RuntimeError('Copied backend/tool source or Python ABI changed')
    for name, entry in before['runManifest'].items():
        if after['runManifest'].get(name) != entry:
            raise RuntimeError('Preserved run-state manifest changed')


def reviewed_identity(inspection, probe, cli_sha, socket_gid, socket_mode, state_root):
    return fingerprint({'containerId': inspection['Id'], 'config': inspection['Config'], 'hostConfig': inspection['HostConfig'], 'networks': inspection['NetworkSettings'].get('Networks', {}), 'image': inspection['Image'], 'code': probe['codeManifest'], 'state': probe['runManifest'], 'cliSha256': cli_sha, 'socketGid': socket_gid, 'socketMode': socket_mode, 'stateRoot': str(state_root)})


def rollback(runtime, name, old_name, old_id, replacement_id, before_probe, health_url, disconnected=None):
    # Remove only the exact replacement we created; never another container.
    try:
        replacement = runtime.inspect(name)
        if replacement['Id'] != replacement_id:
            raise RuntimeError('Replacement identity changed; manual recovery required')
        runtime.docker('stop', '--time', '30', name)
        runtime.docker('rm', name)
    except Exception:
        if replacement_id:
            raise
    old = runtime.inspect(old_name)
    if old['Id'] != old_id:
        raise RuntimeError('Original identity changed; manual recovery required')
    for network, endpoint in (disconnected or {}).items():
        runtime.network(network, 'connect', old_id, endpoint)
    runtime.docker('rename', old_name, name)
    runtime.docker('start', name)
    if not runtime.health(health_url):
        raise RuntimeError('Rollback health failed; original retained')
    source_matches(before_probe, runtime.probe(name))


def apply_recovery(runtime, inspection, probe, state_root, journal, cli_path, cli_sha, socket_gid, socket_mode, health_url):
    name = inspection['Name'].lstrip('/')
    old_id = inspection['Id']
    old_name = name + '-it-rollback-' + journal.name
    snapshot_tag = 'biomate-galaxy-it-before:' + journal.name
    stage = journal / 'staged-runs'
    # Non-destructive initial migration while the original is still present.
    runtime.docker('cp', '-a', name + ':/tmp/nextflow_runs', str(stage))
    verify(stage, probe['runManifest'])
    migration = append_only_copy(stage, state_root)
    private_json(journal / 'run-state-manifest.json', migration['manifest'])
    immediate = runtime.probe(name)
    require_quiescent(immediate)
    source_matches(probe, immediate)
    if runtime.inspect(name)['Id'] != old_id:
        raise RuntimeError('Container changed during review; nothing stopped')
    stopped = False; renamed = False; replacement_id = None; disconnected = {}
    try:
        runtime.docker('stop', '--time', '60', name); stopped = True
        # Snapshot AFTER stopping: captures all docker-copied runtime source.
        snapshot = runtime.docker('commit', name, snapshot_tag, timeout=300)
        if not snapshot.startswith('sha256:'):
            raise RuntimeError('Snapshot did not return an immutable image ID')
        private_json(journal / 'snapshot.json', {'imageId': snapshot, 'tag': snapshot_tag})
        final_stage = journal / 'stopped-runs'
        runtime.docker('cp', '-a', name + ':/tmp/nextflow_runs', str(final_stage))
        verify(final_stage, probe['runManifest'])
        final_manifest = manifest(final_stage)
        append_only_copy(final_stage, state_root)
        probe = {**probe, 'runManifest': final_manifest}
        private_json(journal / 'stopped-run-state-manifest.json', final_manifest)
        payload = build_payload(inspection, snapshot, socket_gid, str(state_root))
        private_json(journal / 'create-payload.json', payload)
        runtime.docker('rename', name, old_name); renamed = True
        # Release original endpoints only after retaining its exact configuration.
        # This prevents static IP/alias collisions; rollback reconnects them.
        for network, endpoint in payload['NetworkingConfig']['EndpointsConfig'].items():
            runtime.network(network, 'disconnect', old_id)
            disconnected[network] = endpoint
        replacement_id = runtime.create(name, payload)
        # No package daemon/repo changes. Refuse unexpected existing targets.
        # The preflight required this path to be absent before snapshot creation.
        runtime.docker('cp', str(cli_path), name + ':/usr/bin/docker')
        runtime.docker('start', name)
        binary = json.loads(runtime.docker('exec', name, 'python3', '-c', "import os,stat,hashlib,json;p='/usr/bin/docker';s=os.lstat(p);print(json.dumps({'regular':stat.S_ISREG(s.st_mode),'uid':s.st_uid,'mode':stat.S_IMODE(s.st_mode),'sha':hashlib.sha256(open(p,'rb').read()).hexdigest()}))"))
        if binary != {'regular': True, 'uid': 0, 'mode': 0o755, 'sha': cli_sha}:
            raise RuntimeError('Trusted CLI bytes/owner/mode validation failed')
        libraries = runtime.docker('exec', name, 'ldd', '/usr/bin/docker')
        if 'not found' in libraries:
            raise RuntimeError('Trusted CLI has unresolved shared libraries')
        runtime.docker('exec', name, '/usr/bin/docker', '--version')
        # Runs as unchanged normal Galaxy user, with only reviewed group added.
        runtime.docker('exec', name, '/usr/bin/docker', 'info', '--format', '{{.ServerVersion}}')
        if (stat.S_IMODE(os.stat('/var/run/docker.sock').st_mode), os.stat('/var/run/docker.sock').st_uid, os.stat('/var/run/docker.sock').st_gid) != (socket_mode, 0, socket_gid):
            raise RuntimeError('Host socket permissions changed unexpectedly')
        if not runtime.health(health_url):
            raise RuntimeError('Replacement health failed')
        source_matches(probe, runtime.probe(name))
        private_json(journal / 'success.json', {'replacementId': replacement_id, 'rollbackContainer': old_name, 'originalId': old_id, 'cliSha256': cli_sha, 'runFiles': sum(x['type'] == 'file' for x in probe['runManifest'].values())})
        return {'success': True, 'rollbackRetained': True, 'journal': str(journal)}
    except Exception:
        if renamed:
            rollback(runtime, name, old_name, old_id, replacement_id, probe, health_url, disconnected)
        elif stopped:
            runtime.docker('start', name)
            if not runtime.health(health_url):
                raise RuntimeError('Original restart health failed')
            source_matches(probe, runtime.probe(name))
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--container', default='biomate-galaxy-dev')
    parser.add_argument('--state-root', default='/opt/biomate/dev-state/nextflow-runs')
    parser.add_argument('--journal-root', default='/opt/biomate/private-it-recovery')
    parser.add_argument('--cli', default='/usr/bin/docker')
    parser.add_argument('--cli-sha256', required=True)
    parser.add_argument('--health-url', default='http://127.0.0.1:8081/api/version')
    parser.add_argument('--approved-plan-sha')
    parser.add_argument('--deploy-lease', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise RuntimeError('Run as root only through the reviewed sync entry point')
    # The same remote lease is held by normal sync and IT-only sync.
    owner = Path('/opt/biomate/.dev-deploy.lock/owner')
    if not owner.is_file() or owner.read_text().strip() != args.deploy_lease:
        raise RuntimeError('Missing matching deployment lease')
    lock = open('/run/lock/biomate-it-recovery.lock', 'a')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    cli = Path(args.cli)
    if cli.is_symlink() or not cli.is_file() or file_hash(cli) != args.cli_sha256:
        raise RuntimeError('Trusted host CLI checksum/type mismatch')
    info = cli.stat()
    if info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o755:
        raise RuntimeError('Trusted CLI must be root-owned mode 0755')
    package = subprocess.check_output(['dpkg-query', '-S', str(cli)], text=True)
    if not package.startswith('docker-ce-cli:'):
        raise RuntimeError('Expected existing official docker-ce-cli package')
    socket_info = os.stat('/var/run/docker.sock')
    if not stat.S_ISSOCK(socket_info.st_mode) or stat.S_IMODE(socket_info.st_mode) != 0o660:
        raise RuntimeError('Socket must retain reviewed mode 0660')
    runtime = Runtime(); inspection = runtime.inspect(args.container)
    if not inspection.get('State', {}).get('Running'):
        raise RuntimeError('Original Galaxy must be running for preflight')
    # Do not overwrite an existing container binary, even if PATH was wrong.
    runtime.docker('exec', args.container, 'python3', '-c', "import os;assert not os.path.lexists('/usr/bin/docker'), 'Docker target already exists'")
    probe = runtime.probe(args.container); require_quiescent(probe)
    state_root = Path(args.state_root)
    if not state_root.is_absolute() or any(parent.is_symlink() for parent in [state_root, *state_root.parents]):
        raise RuntimeError('Persistent state path must be absolute without symlink parents')
    # Validate mount/port/network preservation before even issuing a review SHA.
    build_payload(inspection, inspection['Image'], socket_info.st_gid, str(state_root))
    digest = reviewed_identity(inspection, probe, args.cli_sha256, socket_info.st_gid, 0o660, state_root)
    journal_root = Path(args.journal_root)
    journal_root.mkdir(mode=0o700, exist_ok=True)
    if journal_root.is_symlink() or journal_root.stat().st_uid != 0 or stat.S_IMODE(journal_root.stat().st_mode) != 0o700:
        raise RuntimeError('Journal root must be private root-owned directory mode 0700')
    journal = journal_root / (time.strftime('%Y%m%dT%H%M%SZ', time.gmtime()) + '-' + os.urandom(4).hex())
    journal.mkdir(mode=0o700)
    private_json(journal / 'before-inspect.json', inspection)
    private_json(journal / 'before-probe.json', probe)
    private_json(journal / 'review.json', {'planSha256': digest, 'cliSha256': args.cli_sha256, 'stateRoot': str(state_root), 'socketGid': socket_info.st_gid, 'socketMode': '0660'})
    if not args.apply:
        print(json.dumps({'dryRun': True, 'planSha256': digest, 'journal': str(journal), 'codeFiles': len(probe['codeManifest']), 'runFiles': sum(x['type'] == 'file' for x in probe['runManifest'].values()), 'newSocketGroup': socket_info.st_gid}))
        return
    if os.environ.get('BIOMATE_IT_SOCKET_APPROVED') != '1' or args.approved_plan_sha != digest:
        raise RuntimeError('Apply requires explicit socket approval and exact reviewed plan SHA')
    # Dedicated private parent; destination itself is created with source ownership.
    state_root.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if state_root.parent.stat().st_uid != 0 or stat.S_IMODE(state_root.parent.stat().st_mode) != 0o700:
        raise RuntimeError('Persistent state parent must be root-owned mode 0700')
    print(json.dumps(apply_recovery(runtime, inspection, probe, state_root, journal, cli, args.cli_sha256, socket_info.st_gid, 0o660, args.health_url)))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Errors name the failed phase, never dump environment or signed URLs.
        print(json.dumps({'success': False, 'error': str(error)}), file=sys.stderr)
        sys.exit(1)
