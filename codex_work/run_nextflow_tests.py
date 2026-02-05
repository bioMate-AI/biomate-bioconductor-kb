#!/usr/bin/env python3
import json
import os
import sys
import time
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError


def env(name, default=None, required=False):
    value = os.environ.get(name, default)
    if required and not value:
        print(f"ERROR: Missing required env var {name}")
        sys.exit(1)
    return value


def http_json(method, url, data=None, headers=None):
    headers = headers or {}
    body = None
    if data is not None:
        body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = Request(url, data=body, headers=headers, method=method)
    try:
        with urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else {}
    except HTTPError as e:
        raw = e.read().decode("utf-8")
        try:
            payload = json.loads(raw) if raw else {}
        except Exception:
            payload = {"error": raw}
        return e.code, payload
    except URLError as e:
        return 0, {"error": str(e)}


def http_text(url):
    req = Request(url, method="GET")
    with urlopen(req, timeout=15) as resp:
        return resp.status, resp.read().decode("utf-8")


def load_json_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def main():
    biomate_url = env("BIOMATE_URL", "http://localhost:5000")
    galaxy_url = env("GALAXY_URL", "http://localhost:8081")
    galaxy_api_key = env("GALAXY_API_KEY", "", required=False)
    workflow_json_path = env("WORKFLOW_JSON", "", required=True)
    inputs_json_path = env("INPUTS_JSON", "", required=False)
    auto_fix = env("AUTO_FIX", "false").lower() == "true"

    print("== Health Checks ==")
    status, _ = http_json("GET", f"{galaxy_url}/api/version")
    if status != 200:
        print("ERROR: Galaxy not reachable")
        sys.exit(1)
    print("Galaxy OK")

    status, text = http_text(f"{biomate_url}/")
    if status != 200:
        print("ERROR: BioMate not reachable")
        sys.exit(1)
    print("BioMate OK")

    print("\n== Load Workflow ==")
    workflow_def = load_json_file(workflow_json_path)
    inputs = []
    if inputs_json_path:
        inputs = load_json_file(inputs_json_path)

    print("\n== Execute Workflow (Nextflow) ==")
    execute_payload = {
        "workflowDefinition": workflow_def,
        "workflowName": workflow_def.get("name", "BioMate Workflow"),
        "executionConfig": {
            "mode": "sandbox",
            "executionEngine": "nextflow",
            "dataScope": {"fraction": 1.0, "samplingStrategy": "sequential"},
        },
        "inputs": inputs,
    }

    status, execute_resp = http_json("POST", f"{biomate_url}/api/workflows/execute", execute_payload)
    if status != 200:
        print("ERROR: Execute failed", execute_resp)
        sys.exit(1)

    run_id = execute_resp.get("runId")
    invocation_id = execute_resp.get("invocationId")
    print(f"Run ID: {run_id}")
    print(f"Invocation ID: {invocation_id}")
    print(f"Galaxy Invocation ID: {execute_resp.get('galaxyInvocationId')}")
    print(f"Galaxy History ID: {execute_resp.get('galaxyHistoryId')}")
    print(f"Execution Engine: {execute_resp.get('executionEngine')}")

    print("\n== Poll Status ==")
    status_url = f"{biomate_url}/api/workflows/runs/{run_id}/status?includeSteps=true"
    deadline = time.time() + 120
    last_status = None
    while time.time() < deadline:
        s, status_resp = http_json("GET", status_url)
        if s != 200:
            print("ERROR: Status check failed", status_resp)
            sys.exit(1)
        last_status = status_resp.get("status")
        print(f"Status: {last_status}")
        if last_status in ("completed", "failed", "cancelled"):
            break
        time.sleep(3)

    if last_status not in ("completed", "failed", "cancelled"):
        print("WARNING: Timeout waiting for completion")

    print("\n== Fetch Outputs ==")
    outputs_url = f"{biomate_url}/api/invocations/{invocation_id}/outputs"
    s, outputs = http_json("GET", outputs_url)
    if s != 200:
        print("ERROR: Outputs fetch failed", outputs)
        sys.exit(1)
    if not outputs:
        print("No outputs yet. Triggering fetch-outputs fallback...")
        s, fallback = http_json("POST", f"{biomate_url}/api/invocations/{invocation_id}/fetch-outputs", {})
        if s != 200:
            print("ERROR: fetch-outputs failed", fallback)
            sys.exit(1)
        s, outputs = http_json("GET", outputs_url)
        if s != 200:
            print("ERROR: Outputs fetch failed after fallback", outputs)
            sys.exit(1)

    print(f"Outputs found: {len(outputs)}")

    if last_status == "failed" and auto_fix:
        print("\n== AutoFix ==")
        headers = {"x-api-key": galaxy_api_key} if galaxy_api_key else {}
        s, autofix = http_json(
            "POST",
            f"{biomate_url}/api/invocations/{invocation_id}/ai/autofix",
            {"fix_mode": "safe"},
            headers=headers,
        )
        print("AutoFix response:", autofix)

    print("\n== Done ==")


if __name__ == "__main__":
    main()
