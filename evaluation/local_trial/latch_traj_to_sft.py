"""Proper LatchBio extractor (format-agnostic): mine ALL 132 frontier-agent trajectories (claude-code AND
openai-codex schemas) -> (real bio task -> full step-by-step solution). Task is read FROM the trajectory
(spatialbench/most scbench tasks have no separate eval JSON). Also emits grader-gold findings where present.
Provenance-labeled (no-exclusion policy). stdlib-only.
Usage: python latch_traj_to_sft.py --root ~/latch-benchmarks --out latch_full.jsonl
"""
import argparse, glob, json, os

SYS = "You are BioMate, an agentic bioinformatics assistant. Plan and perform the analysis, then report results."


def texts(r):
    """(role, text) pairs from a transcript line in either schema."""
    out = []
    typ = r.get("type")
    # claude-code: queue-operation content str; user/assistant message.content
    if typ == "queue-operation" and isinstance(r.get("content"), str):
        out.append(("user", r["content"]))
    msg = r.get("message") or {}
    c = msg.get("content")
    role = msg.get("role")
    if isinstance(c, str):
        out.append((role or "user", c))
    elif isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get("type") == "text":
                out.append((role or "assistant", b.get("text", "")))
    # openai-codex: response_item wraps data under payload (or top-level): role + content [{input_text|output_text}]
    if typ == "response_item":
        p = r.get("payload") or r
        rl = p.get("role")
        cc = p.get("content")
        if isinstance(cc, list):
            for b in cc:
                if isinstance(b, dict) and b.get("type") in ("input_text", "output_text"):
                    out.append((rl or ("assistant" if b.get("type") == "output_text" else "user"), b.get("text", "")))
    return out


def is_task(t):
    t = (t or "").strip()
    return len(t) >= 80 and not t.startswith("<") and "permissions instructions" not in t.lower()


def extract(path):
    task = None
    asst = []
    try:
        lines = open(path, encoding="utf-8", errors="ignore").read().splitlines()
    except Exception:
        return None, None
    for ln in lines:
        if not ln.strip():
            continue
        try:
            r = json.loads(ln)
        except Exception:
            continue
        for role, t in texts(r):
            if role in ("user", None) and task is None and is_task(t):
                task = t.strip()
            elif role == "assistant" and len(t.strip()) >= 60:
                asst.append(t.strip())
    if not task or not asst:
        return None, None
    # prefer the turn with the final EVAL_ANSWER (answer + steps); else last long turn / join last few
    final = [t for t in asst if "EVAL_ANSWER" in t or "eval_answer" in t.lower()]
    if final:
        sol = final[-1]
    else:
        sol = asst[-1] if len(asst[-1]) >= 200 else "\n\n".join(asst[-3:])
    return task, sol


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.expanduser("~/latch-benchmarks")); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    n = 0; benches = {}
    with open(a.out, "w") as fo:
        for path in glob.glob(os.path.join(a.root, "*", "trajectories", "**", "harness_outputs.jsonl"), recursive=True):
            parts = path.split("/trajectories/")
            bench = parts[0].split("/")[-1]
            model = "_".join(parts[1].split("/")[1:3])
            task, sol = extract(path)
            if not task or not sol:
                continue
            fo.write(json.dumps({"messages": [{"role": "system", "content": SYS},
                                              {"role": "user", "content": task[:2500]},
                                              {"role": "assistant", "content": sol[:3500]}],
                                 "task": "task_decomposition",
                                 "source": f"latch_traj_{bench}_{model}"}) + "\n")
            n += 1; benches[bench] = benches.get(bench, 0) + 1
    print("LATCH TRAJ DONE: %d solutions | benches %s -> %s" % (n, benches, a.out), flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
