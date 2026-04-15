#!/usr/bin/env python3
"""
setup_eval_user.py — Create and configure the BioMate evaluation user account.

This script creates a dedicated evaluation user in BioMate with a known password,
verifies login works, and stores credentials in the evaluation config.

Usage:
    python scripts/setup_eval_user.py
    python scripts/setup_eval_user.py --host http://localhost:8080
    python scripts/setup_eval_user.py --email eval@biomate.test --password EvalPass123!
    python scripts/setup_eval_user.py --check   # verify existing account works

The script:
    1. Creates an account (or verifies existing one)
    2. Logs in and obtains a JWT token
    3. Verifies the /api/chat/stream endpoint responds
    4. Writes credentials to evaluation/config.yaml (biomate.eval_user section)
"""

import argparse
import json
import sys
import time
from pathlib import Path

import requests
import yaml


DEFAULT_HOST = "http://localhost:5000"
DEFAULT_EMAIL = "eval@biomate.test"
DEFAULT_PASSWORD = "EvalBenchmark2026!"
DEFAULT_NAME = "Evaluation Bot"

CONFIG_PATH = Path(__file__).parent.parent / "config.yaml"


def register_user(host: str, email: str, password: str, name: str) -> dict:
    """Register a new user. Returns response JSON."""
    url = f"{host}/api/auth/register"
    resp = requests.post(url, json={
        "name": name,
        "email": email,
        "password": password,
        "confirm_password": password,
        "termsAccepted": True,
    }, timeout=30)
    return resp


def login_user(host: str, email: str, password: str) -> str:
    """Log in and return JWT token."""
    url = f"{host}/api/auth/login"
    resp = requests.post(url, json={
        "email": email,
        "password": password,
    }, timeout=30)
    if resp.status_code != 200:
        raise RuntimeError(f"Login failed ({resp.status_code}): {resp.text[:200]}")
    data = resp.json()
    token = data.get("token") or data.get("access_token")
    if not token:
        raise RuntimeError(f"No token in login response: {list(data.keys())}")
    return token


def verify_chat_endpoint(host: str, token: str) -> bool:
    """Send a simple test message to /api/chat/stream and verify 200 response."""
    url = f"{host}/api/chat/stream"
    headers = {"Authorization": f"Bearer {token}", "Accept": "text/event-stream"}
    payload = {"message": "What is RNA-seq?", "stream": True}
    try:
        resp = requests.post(url, json=payload, headers=headers, stream=True, timeout=30)
        if resp.status_code != 200:
            return False
        # Read first chunk to confirm streaming works
        for chunk in resp.iter_content(chunk_size=512):
            if chunk:
                return True
        return False
    except Exception as e:
        print(f"  Chat endpoint error: {e}")
        return False


def update_config(config_path: Path, host: str, email: str, password: str):
    """Update evaluation/config.yaml with verified credentials."""
    with open(config_path) as f:
        config = yaml.safe_load(f)

    config.setdefault("biomate", {}).update({
        "host": host,
        "eval_user": {
            "email": email,
            "password": password,
        }
    })

    with open(config_path, "w") as f:
        yaml.dump(config, f, default_flow_style=False, sort_keys=False)

    print(f"  Updated: {config_path}")


def main():
    parser = argparse.ArgumentParser(description="Set up BioMate evaluation user")
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--email", default=DEFAULT_EMAIL)
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    parser.add_argument("--name", default=DEFAULT_NAME)
    parser.add_argument("--check", action="store_true",
                        help="Only verify existing credentials, don't create account")
    parser.add_argument("--no-config-update", action="store_true",
                        help="Don't write credentials to config.yaml")
    args = parser.parse_args()

    print(f"BioMate Eval User Setup")
    print(f"  Host:  {args.host}")
    print(f"  Email: {args.email}")
    print()

    # Step 1: Check if server is up
    print("1. Checking server availability...")
    try:
        resp = requests.get(f"{args.host}/api/health", timeout=10)
        print(f"   OK — {resp.status_code}")
    except requests.exceptions.ConnectionError:
        print(f"   ERROR: Cannot connect to {args.host}")
        print(f"   Start BioMate with: cd /home/yzhang/biomate/backend && bash start_backend.sh")
        sys.exit(1)

    # Step 2: Register (skip if --check)
    if not args.check:
        print("2. Creating evaluation user account...")
        resp = register_user(args.host, args.email, args.password, args.name)
        if resp.status_code in (200, 201):
            print(f"   Created: {args.email}")
        elif resp.status_code == 409:
            print(f"   Already exists (409) — proceeding with login")
        else:
            print(f"   Registration response: {resp.status_code} — {resp.text[:200]}")
            # May still work if account exists; continue to login
    else:
        print("2. Skipping registration (--check mode)")

    # Step 3: Login
    print("3. Logging in...")
    try:
        token = login_user(args.host, args.email, args.password)
        print(f"   OK — token: {token[:20]}...")
    except RuntimeError as e:
        print(f"   FAILED: {e}")
        sys.exit(1)

    # Step 4: Verify chat endpoint
    print("4. Verifying chat endpoint...")
    ok = verify_chat_endpoint(args.host, token)
    if ok:
        print("   OK — /api/chat/stream responded with streaming data")
    else:
        print("   WARNING: chat endpoint did not respond as expected")
        print("   (BioMate may need ANTHROPIC_API_KEY set in backend/.env)")

    # Step 5: Update config
    if not args.no_config_update:
        print("5. Updating config.yaml...")
        try:
            update_config(CONFIG_PATH, args.host, args.email, args.password)
        except Exception as e:
            print(f"   WARNING: Could not update config: {e}")
    else:
        print("5. Skipping config update (--no-config-update)")

    print()
    print("Setup complete. Run benchmarks with:")
    print("  python runners/run_all.py --suite p0 --output results/")
    print("  python runners/run_biomni_eval1.py --max-tasks 5  # quick smoke test")


if __name__ == "__main__":
    main()
