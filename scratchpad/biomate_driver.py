#!/usr/bin/env python3
"""
biomate_driver.py — minimal BioMate dev-public client for demo-stream runs.

Reconstructed from biomate-connector/mcp/biomate_mcp_server.py (BioMateClient).
Base: https://dev-public.biomate.ai  |  Auth: Bearer <key> (embedded below).

CLI:
  python biomate_driver.py quota
  python biomate_driver.py list [--status running|completed|failed|all] [--limit N]
  python biomate_driver.py get <run_id>
  python biomate_driver.py spec <workflow_id>
  python biomate_driver.py search "<query>" [--limit N]
  python biomate_driver.py run <workflow_id> '<json params>'
  python biomate_driver.py preview "<s3_uri>"
"""
import json, os, sys
import requests

BASE = os.environ.get("BIOMATE_API_URL", "https://dev-public.biomate.ai").rstrip("/")
KEY  = os.environ.get("BIOMATE_API_KEY", "bm_live_Ia61Qn8HYhMoLBYzCERivxk-k34IFXOZ")


class BioMate:
    def __init__(self, base=BASE, key=KEY):
        self.base = base.rstrip("/")
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {key}"
        self.s.headers["Content-Type"] = "application/json"
        self.s.headers["User-Agent"] = "BioMate-Driver/1.0"

    def _u(self, p): return f"{self.base}{p}"

    def quota(self):
        r = self.s.get(self._u("/api/billing/quota"), timeout=15); return _j(r)

    def list_runs(self, status="all", limit=15):
        params = {"limit": limit}
        if status and status != "all":
            params["status"] = status
        r = self.s.get(self._u("/api/workflows/runs"), params=params, timeout=20); return _j(r)

    def get_run(self, run_id):
        r = self.s.get(self._u(f"/api/workflows/runs/{run_id}"), timeout=30); return _j(r)

    def spec(self, workflow_id):
        r = self.s.get(self._u("/api/workflows/spec"), params={"workflow_id": workflow_id}, timeout=60); return _j(r)

    def search(self, query, limit=5):
        r = self.s.post(self._u("/api/workflows/search"), json={"query": query, "limit": limit}, timeout=60); return _j(r)

    def preview(self, s3_uri, max_rows=60):
        r = self.s.post(self._u("/api/files/preview"), json={"s3_key": s3_uri, "max_rows": max_rows}, timeout=30); return _j(r)

    def run(self, workflow_id, params):
        """Build workflowDefinition from spec, nest params, POST execute."""
        spec = self.spec(workflow_id)
        if isinstance(spec, dict) and spec.get("error"):
            return spec
        wf = dict((spec or {}).get("workflow_ga") or {})
        for k in ("name", "annotation", "description", "nextflow_path",
                  "format", "workflow_type", "tags"):
            if not wf.get(k) and (spec or {}).get(k) is not None:
                wf[k] = spec[k]
        if not wf.get("name"):
            wf["name"] = workflow_id
        merged = dict(wf.get("parameters") or {})
        merged.update(params or {})
        wf["parameters"] = merged
        # Pre-deploy, the backend validates required inputs against
        # required_params[].value (not the parameters map). Populate those
        # values here, exactly as the connector fix on the branch does.
        for grp in ("required_params", "optional_params"):
            lst = wf.get(grp) or (spec.get(grp) if isinstance(spec, dict) else None)
            if isinstance(lst, list):
                for p in lst:
                    if isinstance(p, dict) and p.get("name") in (params or {}):
                        p["value"] = params[p["name"]]
                wf[grp] = lst
        r = self.s.post(self._u("/api/workflows/execute"), json={"workflowDefinition": wf}, timeout=90)
        return _j(r)

    def signed_url(self, filename, size_bytes=0, content_type=None):
        payload = {"filename": filename, "size_bytes": size_bytes}
        if content_type: payload["content_type"] = content_type
        r = self.s.post(self._u("/api/uploads/signed_url"), json=payload, timeout=20); return _j(r)


def _j(r):
    try:
        body = r.json()
    except Exception:
        body = {"_status": r.status_code, "_text": r.text[:500]}
    if r.status_code >= 400 and isinstance(body, dict):
        body = {"error": True, "_http": r.status_code, **(body if isinstance(body, dict) else {})}
    return body


def main(argv):
    bm = BioMate()
    if not argv:
        print(__doc__); return
    cmd = argv[0]
    if cmd == "quota":
        out = bm.quota()
    elif cmd == "list":
        status = "all"; limit = 15
        if "--status" in argv: status = argv[argv.index("--status")+1]
        if "--limit" in argv: limit = int(argv[argv.index("--limit")+1])
        out = bm.list_runs(status, limit)
    elif cmd == "get":
        out = bm.get_run(argv[1])
    elif cmd == "spec":
        out = bm.spec(argv[1])
    elif cmd == "search":
        limit = 5
        if "--limit" in argv: limit = int(argv[argv.index("--limit")+1])
        out = bm.search(argv[1], limit)
    elif cmd == "run":
        params = json.loads(argv[2]) if len(argv) > 2 else {}
        out = bm.run(argv[1], params)
    elif cmd == "preview":
        out = bm.preview(argv[1])
    elif cmd == "signed_url":
        out = bm.signed_url(argv[1], int(argv[2]) if len(argv) > 2 else 0)
    else:
        out = {"error": f"unknown command {cmd}"}
    print(json.dumps(out, indent=2, default=str))


if __name__ == "__main__":
    main(sys.argv[1:])
