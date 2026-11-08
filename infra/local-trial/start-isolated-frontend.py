#!/usr/bin/env python3
"""Start BioMate against a disposable local database without shared credentials."""
import os
import secrets
from pathlib import Path

root = Path(__file__).resolve().parents[2]
trial_home = Path('/private/tmp/biomate-local-trial-home')
trial_home.mkdir(exist_ok=True)
env = {
    'PATH': os.environ['PATH'], 'HOME': str(trial_home),
    'NODE_ENV': 'development', 'HOST': '127.0.0.1', 'PORT': '5501',
    'DOTENV_CONFIG_PATH': '/dev/null',
    'DATABASE_URL': 'postgresql://kky@127.0.0.1:55439/biomate_trial',
    'GALAXY_URL': 'http://127.0.0.1:8082',
    'BIOMATE_LOCAL_ONLY': '1',
    'BIOMATE_LOCAL_LLM_URL': 'http://127.0.0.1:18080/v1',
    'BIOMATE_LOCAL_LLM_ORIGIN': 'http://127.0.0.1:18080',
    'BIOMATE_LOCAL_LLM_MODEL': 'Qwen/Qwen3.8-27B',
    'BIOMATE_LOCAL_LLM_TIMEOUT_MS': '600000',
    'SESSION_SECRET': secrets.token_urlsafe(32), 'JWT_SECRET': secrets.token_urlsafe(32),
    'BILLING_DEV_MODE': 'true', 'JAVA_BILLING_ENABLED': 'false',
    'AWS_EC2_METADATA_DISABLED': 'true',
    'AWS_SHARED_CREDENTIALS_FILE': '/dev/null', 'AWS_CONFIG_FILE': '/dev/null',
    'NEXTFLOW_USE_AWS': 'false',
}
os.chdir(root / 'frontend')
os.execvpe('/usr/bin/arch', ['arch', '-arm64', 'node', '--import', 'tsx', 'server/index.ts'], env)
