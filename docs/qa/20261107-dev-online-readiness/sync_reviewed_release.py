"""One-shot dev-only sync audit script. Run on the dev host, not a generic installer.

The supplied stage is an export of a reviewed local Git commit. Databases, IAM,
queues and unrelated containers are never changed. Previous files/container are
retained for rollback. Credentials are never logged or included in the archive.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.request

FRONTEND = 'biomate-dev-frontend'
GALAXY = 'biomate-galaxy-dev'
RUNTIME_FILES = {
    'backend/lib/galaxy/ai/ai_assistant.py': '/app/lib/galaxy/ai/ai_assistant.py',
    'backend/lib/galaxy/ai/target_id/data_channels.py': '/app/lib/galaxy/ai/target_id/data_channels.py',
    'backend/lib/galaxy/webapps/galaxy/api/target_id_api.py': '/app/lib/galaxy/webapps/galaxy/api/target_id_api.py',
    'backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/calculate_physicochemical_properties/main.nf':
        '/app/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/calculate_physicochemical_properties/main.nf',
}


def run(args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def ready(commit, attempts=30):
    for _ in range(attempts):
        try:
            with urllib.request.urlopen('http://127.0.0.1:3000/api/health', timeout=8) as response:
                health = json.load(response)
            with urllib.request.urlopen('http://127.0.0.1:3000/build-info.json', timeout=8) as response:
                build = json.load(response)
            if health.get('status') == 'ok' and health.get('services', {}).get('galaxy', {}).get('connected') is True and build.get('commit') == commit:
                return True
        except Exception:
            pass
        time.sleep(3)
    return False


def main():
    commit = sys.argv[1]
    if not re.fullmatch(r'[a-f0-9]{40}', commit):
        raise ValueError('Expected exact reviewed commit')
    stage = Path('/opt/biomate/dev-scientific-releases') / commit
    manifest = json.loads((stage / 'release-manifest.json').read_text())
    if manifest['commit'] != commit or set(manifest['runtime_files']) != set(RUNTIME_FILES):
        raise ValueError('Release manifest scope mismatch')
    for file, expected in manifest['files'].items():
        relative = Path(file)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Invalid release path')
        if hashlib.sha256((stage / relative).read_bytes()).hexdigest() != expected:
            raise ValueError('Release content hash mismatch: ' + file)
    original = json.loads(run(['docker', 'inspect', FRONTEND]))[0]
    if not original['State']['Running']:
        raise RuntimeError('Existing dev frontend is not running')
    if not ready(manifest['base'], attempts=1):
        raise RuntimeError('Dev baseline changed or is unhealthy')
    networks = original['NetworkSettings']['Networks']
    if set(networks) != {'biomate-dev-net'}:
        raise RuntimeError('Unexpected frontend network configuration')
    host = original['HostConfig']
    if any(host.get(key) for key in ('Mounts', 'Privileged', 'ReadonlyRootfs', 'Memory', 'NanoCpus', 'CpusetCpus', 'CapAdd', 'CapDrop', 'SecurityOpt')):
        raise RuntimeError('Nondefault runtime constraints require explicit preservation before sync')
    old_name = FRONTEND + '-rollback-' + commit[:12]
    if subprocess.run(['docker', 'inspect', old_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        raise RuntimeError('Rollback container already exists; do not overwrite it')
    for file, destination in RUNTIME_FILES.items():
        actual = run(['docker', 'exec', GALAXY, 'sha256sum', destination]).split()[0]
        if actual != manifest['original_runtime_hashes'][file]:
            raise RuntimeError('Dev runtime source changed: ' + destination)

    # Build first; the existing frontend and backend remain untouched if it fails.
    image = 'biomate-dev-frontend:scientific-' + commit[:12]
    print('BUILD ' + image, flush=True)
    with (stage / 'frontend-build.log').open('w') as log:
        subprocess.run(['docker', 'build', '-t', image, '--build-arg', 'BUILD_COMMIT=' + commit,
                        '-f', str(stage / 'frontend/Dockerfile'), str(stage / 'frontend')],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    if not ready(manifest['base'], attempts=1):
        raise RuntimeError('Dev baseline changed while building; refusing swap')

    backup = stage / 'rollback'
    backup.mkdir(mode=0o700)
    for file, destination in RUNTIME_FILES.items():
        saved = backup / file
        saved.parent.mkdir(parents=True, exist_ok=True)
        run(['docker', 'cp', GALAXY + ':' + destination, str(saved)])

    # Preserve all current container environment values without logging them or
    # exposing them as command-line arguments. Reject newline-bearing entries.
    environment = original['Config']['Env']
    if any('\n' in entry or '\r' in entry for entry in environment):
        raise RuntimeError('Cannot preserve multiline environment in env-file')
    env_path = stage / 'frontend-runtime.env'
    descriptor = os.open(str(env_path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as handle:
        handle.write('\n'.join(environment) + '\n')
    backend_changed = False
    frontend_renamed = False
    new_frontend_started = False
    try:
        backend_changed = True
        for file, destination in RUNTIME_FILES.items():
            run(['docker', 'cp', str(stage / file), GALAXY + ':' + destination])
            actual = run(['docker', 'exec', GALAXY, 'sha256sum', destination]).split()[0]
            if actual != manifest['runtime_files'][file]:
                raise RuntimeError('Copied source hash mismatch: ' + file)
        # Import the exact synchronized modules before recycling the preloaded master.
        run(['docker', 'exec', '-e', 'PYTHONPATH=/app/lib', '-w', '/app', GALAXY, 'python3', '-c',
             'import galaxy.ai.ai_assistant; import galaxy.ai.target_id.data_channels; '
             'import galaxy.webapps.galaxy.api.target_id_api; print("candidate imports PASS")'])
        print('RELOAD Galaxy master', flush=True)
        run(['docker', 'exec', GALAXY, 'galaxyctl', 'restart', 'gunicorn'])
        if not ready(manifest['base']):
            raise RuntimeError('Galaxy did not recover after reviewed file sync')

        create = ['docker', 'create', '--name', FRONTEND, '--network', 'biomate-dev-net',
                  '--env-file', str(env_path)]
        policy = original['HostConfig']['RestartPolicy']
        if policy['Name']:
            restart = policy['Name']
            if restart == 'on-failure' and policy.get('MaximumRetryCount'):
                restart += ':' + str(policy['MaximumRetryCount'])
            create += ['--restart', restart]
        for port, bindings in (original['HostConfig'].get('PortBindings') or {}).items():
            for binding in bindings:
                address = binding.get('HostIp')
                host = (address + ':' if address else '') + binding['HostPort']
                create += ['-p', host + ':' + port]
        for bind in original['HostConfig'].get('Binds') or []:
            create += ['-v', bind]
        for label, value in (original['Config'].get('Labels') or {}).items():
            create += ['--label', label + '=' + value]
        if original['Config'].get('User'):
            create += ['--user', original['Config']['User']]
        create.append(image)
        print('SWAP frontend; previous container retained for rollback', flush=True)
        run(['docker', 'stop', '--time', '20', FRONTEND])
        run(['docker', 'rename', FRONTEND, old_name])
        frontend_renamed = True
        run(create)
        run(['docker', 'start', FRONTEND])
        new_frontend_started = True
        if not ready(commit):
            raise RuntimeError('New frontend failed health/build identity gate')
        # Preserve the separately uploaded branding asset used by the current dev.
        if Path('/tmp/logo_sync.png').is_file():
            run(['docker', 'cp', '/tmp/logo_sync.png', FRONTEND + ':/app/dist/public/logo.png'])
        print(json.dumps({'result': 'healthy', 'commit': commit, 'rollback_container': old_name,
                          'runtime_files': manifest['runtime_files'], 'databases_replaced': False}), flush=True)
    except Exception:
        print('ROLLBACK reviewed file/container changes', flush=True)
        if frontend_renamed:
            subprocess.run(['docker', 'rm', '-f', FRONTEND], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            run(['docker', 'rename', old_name, FRONTEND])
            run(['docker', 'start', FRONTEND])
        elif not new_frontend_started:
            subprocess.run(['docker', 'start', FRONTEND], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if backend_changed:
            for file, destination in RUNTIME_FILES.items():
                run(['docker', 'cp', str(backup / file), GALAXY + ':' + destination])
            run(['docker', 'exec', GALAXY, 'galaxyctl', 'restart', 'gunicorn'])
        print('ROLLBACK healthy=' + str(ready(manifest['base'])), flush=True)
        raise
    finally:
        env_path.unlink(missing_ok=True)


if __name__ == '__main__':
    # Share the supported manual sync script's lock rather than racing it.
    lock = Path('/tmp/biomate_sync_to_dev.lock')
    descriptor = os.open(str(lock), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as handle:
        handle.write(str(os.getpid()))
    try:
        main()
    finally:
        if lock.read_text() == str(os.getpid()):
            lock.unlink()
