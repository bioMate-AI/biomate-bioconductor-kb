#!/usr/bin/env python3
"""Run the actual BioMate frontend with an isolated local database and model."""
import os,secrets
from pathlib import Path
root=Path('/opt/biomate-trial');home=root/'app-home';home.mkdir(exist_ok=True)
env={'PATH':str(root/'runtimes/node-v22.18.0-linux-x64/bin')+':/usr/local/bin:/usr/bin:/bin','HOME':str(home),
'NODE_ENV':'development','HOST':'127.0.0.1','PORT':'5501','DOTENV_CONFIG_PATH':'/dev/null',
'DATABASE_URL':'postgresql:///biomate_trial?host=/var/run/postgresql&user=ubuntu',
'GALAXY_URL':'http://127.0.0.1:8082','BIOMATE_LOCAL_ONLY':'1',
'BIOMATE_LOCAL_LLM_URL':'http://127.0.0.1:8000/v1','BIOMATE_LOCAL_LLM_ORIGIN':'http://127.0.0.1:8000',
'BIOMATE_LOCAL_LLM_MODEL':'Qwen/Qwen3.8-27B','BIOMATE_LOCAL_LLM_TIMEOUT_MS':'600000',
'SESSION_SECRET':secrets.token_urlsafe(32),'JWT_SECRET':secrets.token_urlsafe(32),
'BILLING_DEV_MODE':'true','JAVA_BILLING_ENABLED':'false','NEXTFLOW_USE_AWS':'false',
'AWS_EC2_METADATA_DISABLED':'true','AWS_SHARED_CREDENTIALS_FILE':'/dev/null','AWS_CONFIG_FILE':'/dev/null'}
os.chdir(root/'app/frontend');os.execvpe('node',['node','--import','tsx','server/index.ts'],env)
