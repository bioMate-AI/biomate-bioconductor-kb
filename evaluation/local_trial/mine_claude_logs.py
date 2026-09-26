"""Mine Claude Code transcripts for REAL task_decomposition data: (user narrative task) -> (the plan the
assistant produced = TodoWrite todos / ExitPlanMode plan). Our own expert artifacts, in the user's own
assignment style. Coding-domain (teaches decomposition STRUCTURE, not bio content). stdlib-only.
Usage: python mine_claude_logs.py --root ~/.claude/projects --out claude_decomp.jsonl [--limit N]
"""
import argparse, glob, json, os, re

NOISE = re.compile(r"^\s*(source |cd |ls |cat |npm |git |python|bash |export |\./|/|\[Request interrupted|"
                   r"<command|<local-command|Caveat:|<system-reminder)", re.I)
SYS = "You are BioMate, an agentic assistant. Decompose the request into an ordered sub-task plan."


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


def tool_uses(content):
    if isinstance(content, list):
        return [b for b in content if isinstance(b, dict) and b.get("type") == "tool_use"]
    return []


def is_task(t):
    t = t.strip()
    if len(t) < 80 or " " not in t:
        return False
    if t.startswith("{") or NOISE.match(t):
        return False
    return True


def plan_from(tu):
    if tu.get("name") == "TodoWrite":
        todos = (tu.get("input") or {}).get("todos") or []
        steps = [td.get("content", "") for td in todos if isinstance(td, dict) and td.get("content")]
        if len(steps) >= 2:
            return "\n".join("%d. %s" % (i + 1, s) for i, s in enumerate(steps))
    if tu.get("name") == "ExitPlanMode":
        p = (tu.get("input") or {}).get("plan", "")
        if len(p) >= 80:
            return p
    return None


def mine_file(path):
    out = []
    last_task = None
    used_task = None
    try:
        lines = open(path, encoding="utf-8", errors="ignore").read().splitlines()
    except Exception:
        return out
    for ln in lines:
        if not ln.strip():
            continue
        try:
            r = json.loads(ln)
        except Exception:
            continue
        typ = r.get("type")
        msg = r.get("message") or {}
        content = msg.get("content")
        if typ == "user" and msg.get("role") == "user":
            t = text_of(content)
            if is_task(t):
                last_task = t.strip()
        elif typ == "assistant":
            txt = text_of(content).strip()
            if last_task and last_task != used_task and len(txt) >= 150 and any(
                    k in txt.lower() for k in ("first", "then", "let me", "i'll", "step", "1.", "plan", "next")):
                out.append({"messages": [{"role": "system", "content": SYS},
                                         {"role": "user", "content": last_task[:2000]},
                                         {"role": "assistant", "content": txt[:2500]}],
                            "task": "task_decomposition", "source": "claude_code_logs"})
                used_task = last_task
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--out", required=True)
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    files = glob.glob(os.path.join(a.root, "**", "*.jsonl"), recursive=True)
    if a.limit:
        files = files[:a.limit]
    n = seen = 0
    with open(a.out, "w") as fo:
        for i, f in enumerate(files):
            for r in mine_file(f):
                fo.write(json.dumps(r) + "\n")
                n += 1
            seen += 1
            if (i + 1) % 500 == 0:
                print("  %d/%d files -> %d decomp examples" % (i + 1, len(files), n), flush=True)
    print("CLAUDE DECOMP DONE: %d examples from %d transcripts -> %s" % (n, seen, a.out), flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
