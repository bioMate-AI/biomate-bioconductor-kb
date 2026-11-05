#!/usr/bin/env python3
"""Replay multi-turn chat scenarios on dev and record the system's full reaction per turn.

Each scenario is {"id", "turns": [message, ...], "files": {"<turn index>": [filename, ...]},
"expect": "<what a good reaction is>"}. Turns run in order in ONE session: earlier turns and
replies are passed as previousMessages, as the chat UI does. Files are uploaded from
--files-dir (POST /api/datasets/upload) and the composer's "[Attached files]/[Uploaded
datasets]" blocks are appended to that turn, as chat-interface.tsx does.

Per turn it records: final state, the workflow card (workflow_ready.workflow_name), tools used,
run_code exit codes and staged inputs, output files, whether tool-call markup leaked into the
reply text (<function_calls>/<invoke>/<run_code>/<read_file>), and the full reply. Chat only:
nothing is executed on Batch (a card is never confirmed).

Usage:
  scripts/routing_eval/replay_sessions.py <scenarios.json> <out.json> [--files-dir DIR] [--lanes 3]
The fixture password comes from E2E_FIXTURE_PASSWORD or ~/.config/biomate/e2e_fixture_password.
"""
import argparse
import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import route_eval as R  # noqa: E402  (shared login / SSE / upload helpers)

LEAK_RE = re.compile(r"</?(?:antml:)?(?:function_calls|invoke|parameter)\b|<run_code>|<read_file>|<dataset_id>", re.I)


def parse_turn(text):
    out = {"state": None, "card": None, "card_type": None, "tools": [], "run_code": [], "output_files": [], "reply": ""}
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
            out["state"] = j.get("state", out["state"])
        elif name == "workflow_ready":
            out["card"] = j.get("workflow_name") or "+".join(j.get("chain_steps", []) or []) or out["card"]
            out["card_type"] = j.get("workflow_type") or out["card_type"]
        elif name in ("tool", "tool_event"):
            t = j.get("tool") or j.get("name")
            if t and t not in out["tools"]:
                out["tools"].append(t)
            if j.get("type") == "tool_result" and j.get("name") == "run_code":
                o = j.get("output") or {}
                out["run_code"].append({"exit": o.get("exit_code"), "stderr": (o.get("stderr") or "")[-300:],
                                        "files": [f.get("name") for f in (o.get("output_files") or [])]})
                out["output_files"] += [f.get("name") for f in (o.get("output_files") or [])]
        elif name == "delta":
            out["reply"] += j.get("text", "")
    out["tool_markup_leaked"] = bool(LEAK_RE.search(out["reply"]))
    return out


def run_scenario(jwt, sc, files_dir):
    session = f"replay-{sc['id']}-{int(time.time())}"
    history, turns = [], []
    for i, msg in enumerate(sc["turns"]):
        names = (sc.get("files") or {}).get(str(i)) or []
        if names:
            p = {"prompt": msg, "files": names, "track": ""}
            old = R.DEMO_ROOT
            R.DEMO_ROOT = files_dir  # with_attachments resolves <root>/cold-start/<name> or <root>/mg_demo/<name>
            try:
                os.makedirs(os.path.join(files_dir, "cold-start"), exist_ok=True)
                for n in names:
                    src, dst = os.path.join(files_dir, n), os.path.join(files_dir, "cold-start", n)
                    if os.path.exists(src) and not os.path.exists(dst):
                        os.symlink(src, dst)
                content = R.with_attachments(jwt, p)
            finally:
                R.DEMO_ROOT = old
        else:
            content = msg
        t0 = time.time()
        st, text = R.post("/api/chat/stream", {"message": content, "stream": True,
                          "context": {"sessionId": session, "previousMessages": history[-16:]}},
                          bearer=jwt, deadline=300)
        res = parse_turn(text)
        res.update({"turn": i, "http": st, "secs": round(time.time() - t0), "message": content})
        turns.append(res)
        history += [{"role": "user", "content": content}, {"role": "assistant", "content": res["reply"]}]
    return {"id": sc["id"], "expect": sc.get("expect", ""), "turns": turns}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios")
    ap.add_argument("out")
    ap.add_argument("--files-dir", default=".")
    ap.add_argument("--lanes", type=int, default=3)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    password = R.fixture_password()
    if not password:
        sys.exit("set E2E_FIXTURE_PASSWORD or create ~/.config/biomate/e2e_fixture_password")
    st, body = R.post("/api/auth/login", {"email": R.EMAIL, "password": password})
    jwt = json.loads(body).get("token", "") if st == 200 else ""
    if len(jwt) < 50:
        sys.exit(f"login failed: HTTP {st}")
    scs = json.load(open(a.scenarios))
    if a.only:
        keep = set(a.only.split(","))
        scs = [s for s in scs if s["id"] in keep]
    results = []
    with ThreadPoolExecutor(a.lanes) as ex:
        for r in ex.map(lambda s: run_scenario(jwt, s, os.path.abspath(a.files_dir)), scs):
            results.append(r)
            last = r["turns"][-1]
            print(f"{r['id']:26s} turns={len(r['turns'])} last: state={last['state']} card={last['card']} "
                  f"tools={last['tools']} rc={[x['exit'] for x in last['run_code']]} leak={last['tool_markup_leaked']}", flush=True)
            json.dump(results, open(a.out, "w"), ensure_ascii=False, indent=1)
    print("DONE", len(results))


if __name__ == "__main__":
    main()
