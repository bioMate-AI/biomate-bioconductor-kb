"""FAST data generation: gemini-3.8-flash only, ONE call per real anchor (synthesize the query, or
classify the error), DB anchor = the target. No slow dual-teacher answer step (we already have ground
truth). High concurrency. Covers all in-scope tasks over all anchors. Emits corpus_train_v2.jsonl +
corpus_eval_v2.jsonl directly (family-disjoint split, routing eval carries accept-sets).
"""
import json, os, re, sqlite3, random, urllib.request, hashlib
from concurrent.futures import ThreadPoolExecutor, as_completed
REPO = "/Users/kky/biomate-review"; DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
P = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
OK = os.environ["OPENAI_API_KEY"]; MODEL = os.environ.get("SYNTH_MODEL", "gpt-6-luna")
CAP = int(os.environ.get("CAP", "1600")); WORKERS = int(os.environ.get("WORKERS", "24"))
random.seed(23)
split = json.load(open(f"{P}/workflow_split.json")) if os.path.exists(f"{P}/workflow_split.json") else {}
accept = json.load(open(f"{P}/accept_sets.json")) if os.path.exists(f"{P}/accept_sets.json") else {}
c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True); c.row_factory = sqlite3.Row


def gem(prompt, mx=400):  # now gpt-6-luna (clean output; gemini-flash truncated 51% via thinking tokens)
    b = json.dumps({"model": MODEL, "messages": [{"role": "user", "content": prompt}], "max_completion_tokens": mx}).encode()
    for _ in range(3):
        try:
            r = urllib.request.Request("https://api.openai.com/v1/chat/completions", data=b,
                                       headers={"Authorization": f"Bearer {OK}", "Content-Type": "application/json"})
            out = json.load(urllib.request.urlopen(r, timeout=90))["choices"][0]["message"]["content"].strip()
            if out: return out
        except Exception: pass
    return ""


def wsplit(wf): return split.get(wf, {}).get("split", "train") if wf else None
def hsplit(k): return "eval" if int(hashlib.sha256(str(k).encode()).hexdigest(), 16) % 100 < 15 else "train"
def toks(s):
    try: return set(json.loads(s)) if s else set()
    except: return set(t.strip() for t in re.split(r"[,;|]+", str(s or "")) if t.strip())


# each task -> (list of (workflow, gold, aux), record-builder using a synthesized query q)
def anchors_routing():
    return [(r["name"], r["name"], r["domain"]) for r in c.execute("select name,domain,description from workflows where description is not null and length(description)>20")]
def anchors_param():
    out = []
    for r in c.execute("select name,params_schema from workflows where params_schema is not null"):
        try: pl = json.loads(r["params_schema"]).get("parameters") or []
        except: continue
        g = {}
        for p in pl:
            if isinstance(p, dict) and p.get("name"):
                v = p.get("default") or (p.get("allowed_values") or [None])[0]
                if v not in (None, ""): g[p["name"]] = v
            if len(g) >= 3: break
        if g: out.append((r["name"], g, None))
    return out
def anchors_decomp():
    out = []
    for r in c.execute("select name,step_metadata from workflows where step_metadata is not null and length(step_metadata)>60"):
        try: s = json.loads(r["step_metadata"])
        except: continue
        st = [{"sub_task": x.get("step"), "order": i + 1} for i, x in enumerate(s) if isinstance(x, dict) and x.get("step")]
        if len(st) >= 3: out.append((r["name"], st, None))
    return out
def anchors_autofix():
    return [(r["name"], None, (r["real_exec_err"] or "")[:1400]) for r in c.execute("select name,real_exec_err from workflows where real_exec_err is not null and length(real_exec_err)>40")]


def okq(q): return bool(q and len(q.strip()) >= 25 and " " in q.strip() and "do not name" not in q.lower())


def build(task, wf, gold, aux):
    if task == "routing":
        q = gem(f"Write a realistic 1-2 sentence user request a scientist would type that should run the bioinformatics workflow '{wf}' (domain {aux}). Do NOT name the workflow. Reply ONLY the request.", 160)
        if not okq(q): return None
        r = {"task": "routing", "input": q, "target": wf, "workflow": wf}
    elif task == "wfgen":
        q = gem(f"Write a realistic user request handled by workflow '{wf}' (domain {aux}). Don't name it. Reply ONLY the request.", 160)
        if not okq(q): return None
        r = {"task": "wfgen", "input": q, "target": aux, "workflow": wf}
    elif task == "param":
        q = gem(f"Write a user request for a '{wf}' analysis that IMPLIES these parameter values without naming the keys: {json.dumps(gold)}. Reply ONLY the request.", 180)
        if not okq(q): return None
        r = {"task": "param", "input": q, "target": gold, "workflow": wf}
    elif task == "decompose":
        goal = "; ".join(s["sub_task"] for s in gold[:6])
        q = gem(f"Write a realistic multi-step analysis request whose plan is roughly: {goal}. Reply ONLY the request.", 200)
        if not okq(q): return None
        r = {"task": "decompose", "input": q, "target": gold, "workflow": wf}
    elif task == "autofix":
        cat = gem(f"Classify this pipeline failure into ONE short fix category (e.g. genome_mismatch, missing_input, resource_limit, container_error, dependency, format_error). Reply ONLY the category.\nError:\n{aux}", 30)
        if not cat: return None
        r = {"task": "autofix", "input": aux, "target": cat.strip().lower().replace(" ", "_"), "workflow": wf}
    else: return None
    r["split"] = wsplit(wf) or hsplit(r["input"])
    r["source"] = "fast_gemini"; r["weight"] = 1.0
    if task == "routing" and r["split"] == "eval":
        r["accept_set"] = accept.get(wf, [wf])
    return r


def run_task(task, anchors):
    random.shuffle(anchors); anchors = anchors[:CAP]
    out = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = [ex.submit(build, task, wf, g, a) for (wf, g, a) in anchors]
        for i, f in enumerate(as_completed(futs)):
            r = f.result()
            if r: out.append(r)
            if (i + 1) % 300 == 0: print(f"  {task}: {i+1}/{len(anchors)}", flush=True)
    return out


all_rows = []
for task, af in [("routing", anchors_routing), ("wfgen", anchors_routing), ("param", anchors_param),
                 ("decompose", anchors_decomp), ("autofix", anchors_autofix)]:
    rows = run_task(task, af())
    all_rows += rows
    ev = sum(1 for r in rows if r["split"] == "eval")
    print(f"TASK {task}: {len(rows)} (eval {ev})", flush=True)

tr = [r for r in all_rows if r["split"] == "train"]; ev = [r for r in all_rows if r["split"] == "eval"]
with open(f"{P}/corpus_train_v2.jsonl", "w") as f:
    for r in tr: f.write(json.dumps(r) + "\n")
with open(f"{P}/corpus_eval_v2.jsonl", "w") as f:
    for r in ev: f.write(json.dumps(r) + "\n")
from collections import Counter
print("FAST POOL DONE. train", len(tr), dict(Counter(r["task"] for r in tr)), "| eval", len(ev), dict(Counter(r["task"] for r in ev)), flush=True)
