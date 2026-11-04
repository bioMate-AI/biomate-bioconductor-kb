#!/usr/bin/env python3
"""Routing evaluation on dev with the EXACT cold-start UI payloads.

Logs in ONCE as the canonical E2E fixture (no /api/auth/register), sends each payload to
/api/chat/stream in N parallel lanes, and appends one JSONL row per payload: final state,
routed workflow (workflow_ready.workflow_name), tools used, and the response head. Chat-only:
no workflow is executed (no Batch), so it cannot disturb runs on dev. Demo FILES are not
uploaded (text context only) — routing reads the text; examples whose answer depends on file
contents are probe artifacts, not routing bugs.

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
        st, text = post("/api/chat/stream", {"message": p["prompt"], "stream": True,
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
