"""Phase 3: mine BioMate's own hard work — docs (1,811 .md) + git commits (fix/feat with rich bodies) —
into QA pairs, knowledge statements, and real diagnosis->fix trajectories. Highest-value, in-domain,
least-circular data. Uses gemini-3.8-flash (cheap) for extraction. Parallel. API-only.

Output: data_pool_v2/self_docs_qa.jsonl, data_pool_v2/self_commit_fixes.jsonl
"""
import json, os, re, subprocess, urllib.request, glob
from concurrent.futures import ThreadPoolExecutor, as_completed
REPO = "/Users/kky/biomate-review"; POOL = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
os.makedirs(POOL, exist_ok=True)
GK = os.environ["GOOGLE_API_KEY"]
DOC_CAP = int(os.environ.get("DOC_CAP", "500")); COMMIT_CAP = int(os.environ.get("COMMIT_CAP", "600"))
WORKERS = int(os.environ.get("WORKERS", "8"))


def gemini(prompt):
    try:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key={GK}"
        body = json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode()
        d = json.load(urllib.request.urlopen(urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"}), timeout=120))
        return "".join(p.get("text", "") for p in d["candidates"][0]["content"]["parts"]).strip()
    except Exception: return ""


def parse_json_list(txt):
    m = re.search(r"\[.*\]", txt or "", re.S)
    if not m: return []
    try: return json.loads(m.group(0))
    except Exception: return []


def doc_qa(path):
    try: txt = open(path, errors="ignore").read()[:8000]
    except Exception: return []
    if len(txt) < 300: return []
    p = ("From this BioMate engineering document, extract up to 4 high-quality QA pairs a bioinformatics "
         "assistant should know (capabilities, design decisions, incident->fix, how-to). Ground strictly in "
         'the text; no speculation. Reply ONLY a JSON list of {"q":...,"a":...}.\n\nDOC:\n' + txt)
    out = []
    for qa in parse_json_list(gemini(p)):
        if isinstance(qa, dict) and qa.get("q") and qa.get("a"):
            out.append({"task": "knowledge_qa", "source": os.path.relpath(path, REPO), "q": qa["q"], "a": qa["a"]})
    return out


def commit_fix(sha):
    try:
        body = subprocess.check_output(["git", "-C", REPO, "log", "-1", "--format=%s%n%b", sha], text=True)[:4000]
        stat = subprocess.check_output(["git", "-C", REPO, "show", "--stat", "--format=", sha], text=True)[:1500]
    except Exception: return None
    p = ("From this BioMate fix/feature commit, extract ONE {problem, root_cause, fix} training example a "
         "bioinformatics/devops assistant should learn. Ground strictly in the message+diffstat. If it is not "
         'a real problem->fix, reply {}. Reply ONLY JSON {"problem":...,"root_cause":...,"fix":...}.\n\n'
         f"COMMIT:\n{body}\n\nFILES:\n{stat}")
    m = re.search(r"\{.*\}", gemini(p) or "", re.S)
    if not m: return None
    try: d = json.loads(m.group(0))
    except Exception: return None
    if isinstance(d, dict) and d.get("problem") and d.get("fix"):
        return {"task": "diagnosis_fix", "source": f"commit:{sha[:10]}", **d}
    return None


def main():
    # DOCS
    docs = sorted(glob.glob(f"{REPO}/docs/**/*.md", recursive=True), key=os.path.getsize, reverse=True)[:DOC_CAP]
    qa = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for i, f in enumerate(as_completed([ex.submit(doc_qa, d) for d in docs])):
            qa.extend(f.result() or [])
            if (i + 1) % 100 == 0: print(f"  docs {i+1}/{len(docs)} -> {len(qa)} QA", flush=True)
    with open(f"{POOL}/self_docs_qa.jsonl", "w") as fo:
        for r in qa: fo.write(json.dumps(r) + "\n")
    print(f"DOCS QA: {len(qa)} pairs from {len(docs)} docs", flush=True)

    # COMMITS (fix/feat with bodies)
    log = subprocess.check_output(["git", "-C", REPO, "log", "-4000", "--format=%H\t%s"], text=True).splitlines()
    shas = [l.split("\t")[0] for l in log if re.search(r"fix|bug|error|resolve|diagnos|repair|feat", l, re.I)][:COMMIT_CAP]
    fixes = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for i, f in enumerate(as_completed([ex.submit(commit_fix, s) for s in shas])):
            r = f.result()
            if r: fixes.append(r)
            if (i + 1) % 100 == 0: print(f"  commits {i+1}/{len(shas)} -> {len(fixes)} fixes", flush=True)
    with open(f"{POOL}/self_commit_fixes.jsonl", "w") as fo:
        for r in fixes: fo.write(json.dumps(r) + "\n")
    print(f"COMMIT FIXES: {len(fixes)} from {len(shas)} commits", flush=True)
    print("SELF_MINING_DONE", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
