"""Scoped dev voice release. Preserve current configuration; retain rollback container."""
import base64, hashlib, json, os, shutil, subprocess, sys, time, urllib.request, zlib
from pathlib import Path

def run(args):
    return subprocess.check_output(args, text=True).strip()

def healthy(identity):
    try:
        with urllib.request.urlopen('http://127.0.0.1:3000/api/health', timeout=8) as r: health=json.load(r)
        with urllib.request.urlopen('http://127.0.0.1:3000/build-info.json', timeout=8) as r: build=json.load(r)
        return health.get('status')=='ok' and health.get('services',{}).get('galaxy',{}).get('connected') is True and build.get('commit')==identity
    except Exception: return False

def wait_ready(identity):
    for _ in range(30):
        if healthy(identity): return True
        time.sleep(3)
    return False

def main(payload):
    base=payload['base']; identity=payload['identity']; name='biomate-dev-frontend'
    assert base=='e06ade54e1bc8cae058fcd52c8895cc946e1b45c'
    assert healthy(base), 'Deployed baseline changed or unhealthy'
    original=json.loads(run(['docker','inspect',name]))[0]
    assert set(original['NetworkSettings']['Networks'])=={'biomate-dev-net'}
    host=original['HostConfig']
    assert not any(host.get(k) for k in ('Mounts','Privileged','ReadonlyRootfs','Memory','NanoCpus','CpusetCpus','CapAdd','CapDrop','SecurityOpt'))
    assert original['Config']['Cmd']==['npm','start']
    assert original['Config']['WorkingDir']=='/app'
    source=Path('/opt/biomate/dev-scientific-releases')/base
    manifest=json.loads((source/'release-manifest.json').read_text())
    for file,sha in manifest['files'].items():
        if file.startswith('frontend/'):
            assert hashlib.sha256((source/file).read_bytes()).hexdigest()==sha, file
    stage=Path('/opt/biomate/dev-voice-releases')/identity
    stage.mkdir(parents=True,exist_ok=False)
    shutil.copytree(source/'frontend',stage/'frontend')
    for file,item in payload['files'].items():
        assert file in ('client/src/components/voice-controls.tsx','client/src/components/live-voice-panel.tsx')
        target=stage/'frontend'/file
        assert hashlib.sha256(target.read_bytes()).hexdigest()==item['baseSha']
        content=zlib.decompress(base64.b64decode(item['content']))
        assert hashlib.sha256(content).hexdigest()==item['sha']
        target.write_bytes(content)
    (stage/'release-manifest.json').write_text(json.dumps(payload,indent=2))
    image='biomate-dev-frontend:'+identity
    with (stage/'build.log').open('w') as log:
        subprocess.run(['docker','build','-t',image,'--build-arg','BUILD_COMMIT='+identity,'-f',str(stage/'frontend/Dockerfile'),str(stage/'frontend')],stdout=log,stderr=subprocess.STDOUT,check=True)
    assert healthy(base), 'Baseline changed during build'
    environment=dict(entry.split('=',1) for entry in original['Config']['Env'])
    assert environment.get('ELEVENLABS_API_KEY'), 'Missing provider key'
    environment.update(BIOMATE_VOICE_ENABLED='true',BIOMATE_LIVE_VOICE_ENABLED='true',ELEVENLABS_VOICE_ID='21m00Tcm4TlvDq8ikWAM')
    assert not any('\n' in v or '\r' in v for v in environment.values())
    envfile=stage/'runtime.env'
    fd=os.open(str(envfile),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f:f.write('\n'.join(k+'='+v for k,v in environment.items())+'\n')
    old=name+'-rollback-'+identity
    assert subprocess.run(['docker','inspect',old],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
    create=['docker','create','--name',name,'--network','biomate-dev-net','--env-file',str(envfile)]
    policy=host['RestartPolicy']
    if policy['Name']:
        restart=policy['Name']
        if restart=='on-failure' and policy.get('MaximumRetryCount'):restart+=':'+str(policy['MaximumRetryCount'])
        create+=['--restart',restart]
    for port,bindings in (host.get('PortBindings') or {}).items():
        for binding in bindings:
            address=binding.get('HostIp'); create+=['-p',(address+':' if address else '')+binding['HostPort']+':'+port]
    for bind in host.get('Binds') or []:create+=['-v',bind]
    for k,v in (original['Config'].get('Labels') or {}).items():create+=['--label',k+'='+v]
    if original['Config'].get('User'):create+=['--user',original['Config']['User']]
    create.append(image)
    renamed=False
    try:
        run(['docker','stop','--time','20',name]);run(['docker','rename',name,old]);renamed=True
        run(create);run(['docker','start',name])
        assert wait_ready(identity), 'New voice frontend not healthy'
        if Path('/tmp/logo_sync.png').is_file():run(['docker','cp','/tmp/logo_sync.png',name+':/app/dist/public/logo.png'])
        print(json.dumps({'result':'healthy','identity':identity,'rollback':old,'backendChanged':False}),flush=True)
    except Exception:
        if renamed:
            subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
            run(['docker','rename',old,name])
        run(['docker','start',name])
        print('Rollback healthy='+str(wait_ready(base)),flush=True)
        raise
    finally:envfile.unlink(missing_ok=True)

if __name__=='__main__':
    payload=json.loads(Path(sys.argv[1]).read_text())
    lock=Path('/tmp/biomate_sync_to_dev.lock')
    fd=os.open(str(lock),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f:f.write(str(os.getpid()))
    try:main(payload)
    finally:
        if lock.read_text()==str(os.getpid()):lock.unlink()
