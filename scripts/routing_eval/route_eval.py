#!/usr/bin/env python3
"""Routing evaluation on dev with the EXACT cold-start UI payloads.

Logs in ONCE as the canonical E2E fixture (no /api/auth/register), sends each payload to
/api/chat/stream in N parallel lanes, and appends one JSONL row per payload: final state,
routed workflow (workflow_ready.workflow_name), tools used, and the response head. Chat-only:
no workflow is executed (no Batch), so it cannot disturb runs on dev. Demo FILES are not
uploaded by default (text context only). Set ROUTE_EVAL_WITH_FILES=1 to reproduce the UI
exactly: each example's demo files are uploaded (POST /api/datasets/upload, as lib/upload.ts) and
the "[Attached files: ...]\n[Uploaded datasets: ...]" blocks are appended as chat-interface.tsx
handleSendMessage does — routing that depends on attached data (e.g. the GEO fast path's
"data already attached" guard) is then measured faithfully.

Usage:
  E2E_FIXTURE_PASSWORD=... scripts/routing_eval/route_eval.py <payloads.json> <out.jsonl> [lanes] [idx,idx,...] [reps]
Payloads come from scripts/routing_eval/dump_payloads.sh. Attribute card swaps from the dev
frontend log (Step 6b / Step 6c-2 lines). See docs/20261103_ALL_LLM_AGENTIC_UNIFICATION_AND_COLDSTART.md §5.
"""
import json, os, re, ssl, sys, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

BASE = os.environ.get("BIOMATE_URL", "https://dev-public.biomate.ai")
EMAIL = "lifeifei163361@163.com"
CTX = ssl.create_default_context()


def post(path, body, bearer=None, timeout=180, deadline=240):
    """Read SSE line by line and stop at the `final` event (+ its data line), with a hard total
    deadline. A plain r.read() waits for connection close: heartbeats reset the socket timeout,
    and a lost FIN on the client<->EC2 path (2026-11-03: the server logged POST 200 while the
    client blocked) stalled a whole run for 90 min. http -1 = client-side error, -2 = deadline."""
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(), method="POST")
    req.add_header("content-type", "application/json")
    if bearer:
        req.add_header("Authorization", "Bearer " + bearer)
    t0, out = time.time(), []
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            if not path.endswith("/stream"):
                return r.status, r.read().decode(errors="replace")
            saw_final = False
            while time.time() - t0 < deadline:
                line = r.readline()
                if not line:
                    break
                s = line.decode(errors="replace")
                out.append(s)
                if s.startswith("event: final"):
                    saw_final = True
                elif saw_final and s.startswith("data:"):
                    break
            else:
                return -2, "".join(out)
            return r.status, "".join(out)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")
    except Exception as e:  # noqa: BLE001 — recorded, not raised: one dropped stream must not stop the run
        return -1, "".join(out) + f"\nERR {type(e).__name__}: {e}"


def parse(text):
    state = wf = None
    tools, reply = [], ""
    for blk in re.split(r"\nevent:\s*|^event:\s*", text):
        name, _, rest = blk.partition("\n")
        m = re.search(r"data:\s*(\{.*)", rest)
        if not m:
            continue
        try:
            j = json.loads(m.group(1).split("\n")[0])
        except ValueError:
            continue
        if name == "final":
            state = j.get("state", state)
        elif name == "workflow_ready":
            wf = j.get("workflow_name") or "+".join(j.get("chain_steps", []) or []) or wf
        elif name in ("tool", "tool_event"):
            t = j.get("tool") or j.get("name")
            if t and t not in tools:
                tools.append(t)
        elif name == "delta":
            reply += j.get("text", "")
    return state, wf, tools, reply[:240].replace("\n", " ")


DEMO_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "frontend", "client", "public", "demo")
_upload_cache = {}


def upload(jwt, path):
    """Upload one demo file like lib/upload.ts (multipart: file, file_type, description); cached
    per run so repeated examples reuse the same dataset."""
    if path in _upload_cache:
        return _upload_cache[path]
    import mimetypes, uuid
    name = os.path.basename(path)
    ctype = mimetypes.guess_type(name)[0] or ""
    boundary = uuid.uuid4().hex
    parts = []
    for field, value in (("file_type", ctype or "auto"), ("description", "Uploaded from BioMate chat composer")):
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"\r\n\r\n{value}\r\n'.encode())
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\n'
                 f'Content-Type: {ctype or "application/octet-stream"}\r\n\r\n'.encode() + open(path, "rb").read() + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    req = urllib.request.Request(BASE + "/api/datasets/upload", data=b"".join(parts), method="POST")
    req.add_header("content-type", f"multipart/form-data; boundary={boundary}")
    req.add_header("Authorization", "Bearer " + jwt)
    with urllib.request.urlopen(req, timeout=180, context=CTX) as r:
        res = json.loads(r.read().decode())
    _upload_cache[path] = (res.get("dataset_id"), res.get("galaxy_dataset_id"), res.get("s3_uri"))
    return _upload_cache[path]


def with_attachments(jwt, p):
    """The message exactly as chat-interface.tsx handleSendMessage sends it with attached files."""
    files = p.get("files") or []
    if not files:
        return p["prompt"]
    root = os.path.join(DEMO_ROOT, "mg_demo" if p.get("track") == "Try sample data" else "cold-start")
    blocks, failed = [], []
    for name in files:
        path = os.path.join(root, name)
        if not os.path.exists(path):
            path = os.path.join(DEMO_ROOT, "cold-start", name)
        try:
            did, gid, s3 = upload(jwt, path)
        except Exception as e:  # noqa: BLE001 — the UI keeps going and reports it; so do we
            msg = e.read().decode(errors="replace")[:120] if hasattr(e, "read") else str(e)
            failed.append(f"{name} ({msg})")
            continue
        blocks.append(f"{name}: dataset_id={did or 'n/a'}" + (f", galaxy_dataset_id={gid}" if gid else "") + (f", s3_uri={s3}" if s3 else ""))
    content = p["prompt"]
    return (content + ("\n\n" if content else "") + f"[Attached files: {', '.join(files)}]"
            + (f"\n[Uploaded datasets: {'; '.join(blocks)}]" if blocks else "")
            + (f"\n[Upload warnings: {', '.join(failed)}]" if failed else ""))


def main():
    payloads_path, out_path = sys.argv[1], sys.argv[2]
    lanes = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    only = {int(x) for x in sys.argv[4].split(",")} if len(sys.argv) > 4 and sys.argv[4] else None
    reps = int(sys.argv[5]) if len(sys.argv) > 5 else 1
    password = os.environ.get("E2E_FIXTURE_PASSWORD")
    if not password:
        sys.exit("E2E_FIXTURE_PASSWORD is not set (the fixture password is never committed)")
    st, body = post("/api/auth/login", {"email": EMAIL, "password": password})
    jwt = json.loads(body).get("token", "") if st == 200 else ""
    if len(jwt) < 50:
        sys.exit(f"login failed: HTTP {st}")
    payloads = json.load(open(payloads_path))
    if only:
        payloads = [p for p in payloads if p["idx"] in only]

    def run(job):
        rep, p = job
        t0 = time.time()
        message = with_attachments(jwt, p) if os.environ.get("ROUTE_EVAL_WITH_FILES") == "1" else p["prompt"]
        st, text = post("/api/chat/stream", {"message": message, "stream": True,
                        "context": {"sessionId": f"re-{p['idx']}-{rep}-{int(t0)}", "previousMessages": []}}, bearer=jwt)
        state, wf, tools, reply = parse(text)
        row = {"idx": p["idx"], "rep": rep, "module": p["module"], "track": p["track"], "mod": p["mod"],
               "seed": p["seed"], "http": st, "state": state, "wf": wf, "tools": tools,
               "secs": round(time.time() - t0), "reply": reply}
        with open(out_path, "a") as f:
            f.write(json.dumps(row) + "\n")
        print(f"[{p['idx']:3d}] r{rep} {p['module'][:12]:12s} {p['track'][:22]:22s} {p['mod']:7s} -> {state} | {wf}", flush=True)

    jobs = [(rep, p) for rep in range(1, reps + 1) for p in payloads]
    with ThreadPoolExecutor(lanes) as ex:
        list(ex.map(run, jobs))
    print("DONE", len(jobs))


if __name__ == "__main__":
    main()
