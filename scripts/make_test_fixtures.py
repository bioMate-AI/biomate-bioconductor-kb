#!/usr/bin/env python3
"""
Create test fixtures for AfterRunReport branches not currently exercisable
against dev's existing run inventory:
  - A cancelled run (status='cancelled')
  - A failed run that went through the auto-fix loop (autofix.state='failed')

Both fixtures are real BioMate API calls against dev so the resulting runs
land in /api/workflows/runs and the panel renders them with real data.
"""
import json
import sys
import time
import urllib.error
import urllib.request

BASE = "https://dev-public.biomate.ai"
TOKEN = "biomate-e2e-bypass-token-dev-only"  # bypass token used by other E2E tests


def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(
        f"{BASE}{path}",
        method=method,
        headers={
            "Content-Type": "application/json",
            "X-E2E-Test-Token": TOKEN,
            "User-Agent": "Mozilla/5.0 (fixture-maker)",
        },
        data=data,
    )
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:
        return -1, str(e).encode()


def jget(path):
    code, body = req("GET", path)
    return json.loads(body) if code == 200 else None


# ── Fixture 1: cancelled run ─────────────────────────────────────────────
print("\n== Fixture 1: cancelled run ==")
print("Strategy: trigger a long-running workflow, then immediately cancel it.")

# Pick any registered nextflow workflow that exists
runs = jget("/api/workflows/runs?limit=50") or []
candidate_wfs = list({(r.get("workflowDefinition") or {}).get("name") for r in runs if r.get("workflowDefinition")})
candidate_wfs = [w for w in candidate_wfs if w][:5]
print(f"Existing workflow names on dev: {candidate_wfs}")

if not candidate_wfs:
    print("  ⚠ no existing workflows to trigger from. Skipping cancelled-run fixture.")
else:
    # Submit a fresh run of the first one
    wf_name = candidate_wfs[0]
    payload = {
        "workflowDefinition": {"name": wf_name, "format": "nextflow"},
        "parameters": {"_fixture": "afterrun-cancelled-test"},
        "chatSessionId": None,
    }
    code, body = req("POST", "/api/workflows/execute", payload)
    print(f"  POST /api/workflows/execute → HTTP {code}")
    if code in (200, 201, 202):
        try:
            data = json.loads(body)
            run_id = data.get("runId") or data.get("id") or (data.get("run") or {}).get("id")
            if run_id:
                print(f"  Created run {run_id} — sleeping 5s then cancelling")
                time.sleep(5)
                ccode, cbody = req("POST", f"/api/workflows/runs/{run_id}/cancel")
                print(f"  POST /api/workflows/runs/{run_id}/cancel → HTTP {ccode}")
                # Give the cancel a moment to register, then verify
                time.sleep(5)
                detail = jget(f"/api/workflows/runs/{run_id}")
                final_status = (detail or {}).get("execution", {}).get("status")
                print(f"  Final status: {final_status!r}")
                if final_status == "cancelled":
                    print(f"  ✓ FIXTURE 1 CREATED — runId={run_id}")
                else:
                    print(f"  ⚠ run did not enter cancelled state ({final_status}); may have completed too fast")
            else:
                print(f"  ⚠ response did not include a runId: {data}")
        except Exception as e:
            print(f"  ⚠ unable to parse response: {e}")
    else:
        print(f"  ⚠ trigger failed: {body[:200].decode(errors='replace')}")


# ── Fixture 2: autofix-failed run ────────────────────────────────────────
print("\n== Fixture 2: autofix-failed run ==")
print("Strategy: look for any existing run with nextflowStatus.autofix populated.")
print("If none exists, the autofix system isn't running for current run set —")
print("triggering one would require submitting an autoloop-family workflow")
print("with knowingly-bad parameters, which needs domain-specific knowledge")
print("(ADMET / CYP-DDI / Docking / NCA-PK / Structure-prediction / Cryo-EM).")

runs = jget("/api/workflows/runs?limit=200") or []
autofix_runs = [r for r in runs if (r.get("execution",{}).get("nextflowStatus") or {}).get("autofix")]
print(f"  Found {len(autofix_runs)} runs with nextflowStatus.autofix populated")
for r in autofix_runs[:3]:
    e = r.get("execution",{})
    af = (e.get("nextflowStatus") or {}).get("autofix") or {}
    wf = (r.get("workflowDefinition") or {}).get("name", "?")
    print(f"    • {wf} runId={r['id'][:12]}… state={af.get('state')!r} attempts={af.get('totalAttempts')}")
if not autofix_runs:
    print("  ⚠ No existing autofix runs. Recommendation: ship an autoloop test workflow")
    print("    (e.g. trigger ADMET with hERG threshold deliberately set too strict so the")
    print("     auto-loop's remediation iterations all fail and the run terminates with")
    print("     autofix.state='failed').")

print("\nDone.")
