#!/usr/bin/env python3
"""Run the actual BioMate frontend with an isolated local database and model."""
import os,secrets,json
from pathlib import Path
root=Path('/opt/biomate-trial');home=root/'app-home';home.mkdir(exist_ok=True)
secret_path=root/'app-secrets.json'
if not secret_path.exists():
    fd=os.open(secret_path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f:
        json.dump({name:secrets.token_urlsafe(32) for name in ('SESSION_SECRET','JWT_SECRET','FIELD_ENCRYPTION_SECRET')},f)
saved_secrets=json.loads(secret_path.read_text())
if any(not saved_secrets.get(name) for name in ('SESSION_SECRET','JWT_SECRET','FIELD_ENCRYPTION_SECRET')):
    raise ValueError('Incomplete trial secret file')
env={'PATH':str(root/'runtimes/node-v22.18.0-linux-x64/bin')+':/usr/local/bin:/usr/bin:/bin','HOME':str(home),
'NODE_ENV':'development','HOST':'127.0.0.1','PORT':'5501','DOTENV_CONFIG_PATH':'/dev/null',
'DATABASE_URL':'postgresql:///biomate_trial?host=/var/run/postgresql&user=ubuntu',
'GALAXY_URL':'http://127.0.0.1:8082','BIOMATE_LOCAL_ONLY':'1','BIOMATE_OFFLINE':'1',
'BIOMATE_LOCAL_LLM_URL':'http://127.0.0.1:8000/v1','BIOMATE_LOCAL_LLM_ORIGIN':'http://127.0.0.1:8000',
'BIOMATE_LOCAL_LLM_MODEL':'Qwen/Qwen3.8-27B','BIOMATE_LOCAL_LLM_TIMEOUT_MS':'600000',
**saved_secrets,
'BILLING_DEV_MODE':'true','JAVA_BILLING_ENABLED':'false','NEXTFLOW_USE_AWS':'false',
'AWS_EC2_METADATA_DISABLED':'true','AWS_SHARED_CREDENTIALS_FILE':'/dev/null','AWS_CONFIG_FILE':'/dev/null'}
os.chdir(root/'app/frontend');os.execvpe('node',['node','--import','tsx','server/index.ts'],env)
