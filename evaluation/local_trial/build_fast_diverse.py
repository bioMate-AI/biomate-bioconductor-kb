"""Fast diverse-task generation (gemini-flash @ mx>=1024, one call/anchor) — APPENDS clarification,
conditional_param, chaining, diagnosis, dataset_compatibility + knowledge to corpus_{train,eval}_v2.jsonl.
Same clean/fast config as build_fast_pool (no thinking-token truncation, high RPM).
"""
import json, os, re, sqlite3, random, urllib.request, hashlib
from concurrent.futures import ThreadPoolExecutor, as_completed
REPO = "/Users/kky/biomate-review"; DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
P = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
GK = os.environ["GOOGLE_API_KEY"]; CAP = int(os.environ.get("CAP", "100000")); WORKERS = int(os.environ.get("WORKERS", "24"))  # no artificial cap
random.seed(23)
split = json.load(open(f"{P}/workflow_split.json")) if os.path.exists(f"{P}/workflow_split.json") else {}
c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True); c.row_factory = sqlite3.Row


def gem(prompt, mx=1024):
    mx = max(mx, 1024)
    u = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key={GK}"
    b = json.dumps({"contents": [{"parts": [{"text": prompt}]}], "generationConfig": {"maxOutputTokens": mx}}).encode()
    for _ in range(4):
        try:
            ca = json.load(urllib.request.urlopen(urllib.request.Request(u, data=b, headers={"Content-Type": "application/json"}), timeout=60))["candidates"][0]
            if ca.get("finishReason") in (None, "STOP"):
                out = "".join(x.get("text", "") for x in ca.get("content", {}).get("parts", [])).strip()
                if out: return out
        except Exception: pass
    return ""


def hsplit(k): return "eval" if int(hashlib.sha256(str(k).encode()).hexdigest(), 16) % 100 < 15 else "train"
def wsplit(wf): return split.get(wf, {}).get("split") if wf else None
def okq(q): return bool(q and len(q.strip()) >= 25 and " " in q.strip())


# anchors
def clar_cond():
    out = []
    for r in c.execute("select name,params_schema from workflows where params_schema is not null limit 3000"):
        try: pl = json.loads(r["params_schema"]).get("parameters") or []
        except: continue
        req = [p for p in pl if isinstance(p, dict) and p.get("name") and not p.get("optional", True)]
        dfl = [p for p in pl if isinstance(p, dict) and p.get("default") not in (None, "")]
        if req: out.append(("clar", r["name"], req[0]["name"]))
        if dfl: out.append(("cond", r["name"], dfl[0]["name"]))
    return out
def chains():
    p = f"{P}/../routing_data_v1/wkg.json"
    if not os.path.exists(p): return []
    pre = json.load(open(p)).get("precede") or {}
    return [("chain", a, b) for a, s in pre.items() for b in (s or [])[:1]]
def errors():
    return [("diag", r["name"], (r["real_exec_err"] or "")[:1400]) for r in c.execute("select name,real_exec_err from workflows where real_exec_err is not null and length(real_exec_err)>40")]
def ios():
    return [("compat", r["name"], r["input_types"]) for r in c.execute("select name,input_types from workflows where input_types is not null and length(input_types)>5")]


def build(kind, wf, x):
    if kind == "clar":
        q = gem(f"Write a realistic user request to run '{wf}' that OMITS any value for required parameter '{x}'. Reply ONLY the request.")
        if not okq(q): return None
        return {"task": "clarification", "input": q, "target": x, "workflow": wf}
    if kind == "cond":
        q = gem(f"Write a user request to run '{wf}' that explicitly OVERRIDES parameter '{x}' to a non-default value. Reply ONLY the request.")
        if not okq(q): return None
        return {"task": "conditional_param", "input": q, "target": x, "workflow": wf}
    if kind == "chain":
        q = gem(f"Write a realistic request requiring '{wf}' then '{x}' in sequence (data flows A->B). Reply ONLY the request.")
        if not okq(q): return None
        return {"task": "chaining", "input": q, "target": [wf, x]}
    if kind == "diag":
        a = gem(f'Diagnose this pipeline failure. Reply ONLY JSON {{"root_cause":...,"fix":...}}.\nError:\n{x}')
        if not a or "{" not in a: return None
        return {"task": "diagnosis", "input": x[:600], "target": a}
    if kind == "compat":
        a = gem(f"A workflow expects inputs: {x}. Invent a one-line dataset description AND say if compatible. Reply ONLY: <dataset> || YES or NO")
        if "||" not in (a or ""): return None
        ds, lab = a.split("||", 1)
        return {"task": "dataset_compatibility", "input": ds.strip(), "target": "YES" if "yes" in lab.lower() else "NO", "workflow": wf}
    return None


def run(kind, anchors):
    anchors = [(k, w, x) for (k, w, x) in anchors if k == kind][:CAP]
    out = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for i, f in enumerate(as_completed([ex.submit(build, k, w, x) for (k, w, x) in anchors])):
            r = f.result()
            if r:
                r["split"] = wsplit(r.get("workflow")) or hsplit(r["input"]); r["source"] = "fast_diverse"; r["weight"] = 1.0
                out.append(r)
            if (i + 1) % 400 == 0: print(f"  {kind}: {i+1}/{len(anchors)}", flush=True)
    return out


rows = []
cc = clar_cond(); random.shuffle(cc)
rows += run("clar", cc); rows += run("cond", cc)
rows += run("chain", chains()); rows += run("diag", errors()); rows += run("compat", ios())
# knowledge (no API)
for r in (json.loads(l) for l in open(f"{P}/self_docs_qa_clean.jsonl")):
    if r.get("q") and r.get("a"):
        rows.append({"task": "knowledge_qa", "input": r["q"], "target": r["a"], "split": hsplit(r["q"]), "source": "self_docs", "weight": 0.7})

# APPEND to corpus_v2
import collections
tr = [r for r in rows if r["split"] == "train"]; ev = [r for r in rows if r["split"] == "eval"]
with open(f"{P}/corpus_train_v2.jsonl", "a") as f:
    for r in tr: f.write(json.dumps(r) + "\n")
with open(f"{P}/corpus_eval_v2.jsonl", "a") as f:
    for r in ev: f.write(json.dumps(r) + "\n")
print("DIVERSE APPENDED. +train", len(tr), dict(collections.Counter(r['task'] for r in tr)), "| +eval", len(ev), dict(collections.Counter(r['task'] for r in ev)), flush=True)
