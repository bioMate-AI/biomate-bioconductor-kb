"""Task DIVERSITY expansion (TASK_CATALOG T01-T26, IND excluded): add the missing in-scope tasks to the
pool via committee distillation grounded in REAL DB sources — clarification (T03), chaining/composition
(T09), conditional_param (T10), diagnosis+root-cause (T18), dataset_compatibility (T07), intent (T01),
data_extraction (T02). Query synthesized by a teacher from a real anchor; both teachers answer as
BioMate; consensus recorded. Output committee_<task>.jsonl (folded by assemble_corpus). API + DB.
"""
import json, os, re, sqlite3, random
from concurrent.futures import ThreadPoolExecutor, as_completed
import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_committee_pool import openai, gemini, norm
REPO = "/Users/kky/biomate-review"; DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
POOL = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
CAP = int(os.environ.get("CAP", "400")); WORKERS = int(os.environ.get("WORKERS", "10"))
random.seed(23)
c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True); c.row_factory = sqlite3.Row


def teachers(ans_prompt):
    a, b = openai(ans_prompt), gemini(ans_prompt)
    return a, b, bool(a and b and (norm(a)[:50] in norm(b) or norm(b)[:50] in norm(a)))


# ---- anchors ----
def wf_required_params():  # clarification (T03) + conditional_param (T10)
    out = []
    for r in c.execute("select name,params_schema from workflows where params_schema is not null limit 2500"):
        try: pl = json.loads(r["params_schema"]).get("parameters") or []
        except: continue
        req = [p for p in pl if isinstance(p, dict) and p.get("name") and not p.get("optional", True)]
        defd = [p for p in pl if isinstance(p, dict) and p.get("default") not in (None, "")]
        if req: out.append(("clar", r["name"], req[0]))
        if defd: out.append(("cond", r["name"], defd[0]))
    return out


def wkg_pairs():  # chaining / composition (T09)
    p = f"{POOL}/../routing_data_v1/wkg.json"
    if not os.path.exists(p): return []
    w = json.load(open(p)); pre = w.get("precede") or {}
    return [("chain", a, b) for a, succ in list(pre.items()) for b in (succ or [])[:1]][:CAP]


def real_errors():  # diagnosis + root-cause (T18)
    return [("diag", r["name"], (r["real_exec_err"] or "")[:1400]) for r in
            c.execute("select name,real_exec_err from workflows where real_exec_err is not null and length(real_exec_err)>40 limit 1500")]


def io_anchors():  # dataset_compatibility (T07)
    return [("compat", r["name"], r["input_types"]) for r in
            c.execute("select name,input_types from workflows where input_types is not null and length(input_types)>5 limit 1500")]


def process(kind, wf, x):
    if kind == "clar":
        pn = x.get("name")
        q = openai(f"Write a realistic user request to run '{wf}' that OMITS any value for the required parameter '{pn}'. Reply ONLY the request.", 200)
        if not q: return None
        ap = f"You are BioMate. If a required parameter is missing, ASK the user for it (name it). Request: {q}"
        a, b, cons = teachers(ap)
        return {"task": "clarification", "query": q, "db_gold": pn, "teacher_gpt56": a, "teacher_gemini": b,
                "consensus": cons, "agrees_db_gold": bool(a and norm(pn) in norm(a)), "workflow": wf}
    if kind == "cond":
        pn = x.get("name"); dv = x.get("default")
        q = openai(f"Write a user request to run '{wf}' that explicitly OVERRIDES parameter '{pn}' (default {dv}) to a different value. Reply ONLY the request.", 200)
        if not q: return None
        a, b, cons = teachers(f"You are BioMate. Extract only the parameters the user overrides. Request: {q}")
        return {"task": "conditional_param", "query": q, "db_gold": pn, "teacher_gpt56": a, "teacher_gemini": b, "consensus": cons, "workflow": wf}
    if kind == "chain":
        q = openai(f"Write a realistic request that requires running '{wf}' and THEN '{x}' in sequence (data flows A->B). Reply ONLY the request.", 200)
        if not q: return None
        a, b, cons = teachers(f'You are BioMate. Decompose into an ordered workflow chain. Reply ONLY a JSON list of {{"workflow":...,"order":N}}.\nRequest: {q}')
        return {"task": "chaining", "query": q, "db_gold": [wf, x], "teacher_gpt56": a, "teacher_gemini": b, "consensus": cons}
    if kind == "diag":
        a, b, cons = teachers(f'You are BioMate. Diagnose this pipeline failure. Reply ONLY JSON {{"root_cause":...,"fix":...}}.\nError:\n{x}')
        return {"task": "diagnosis", "query": x[:400], "db_gold": None, "teacher_gpt56": a, "teacher_gemini": b, "consensus": cons, "workflow": wf}
    if kind == "compat":
        ds = openai(f"Invent a one-line dataset description that is EITHER compatible or INcompatible with a workflow expecting inputs: {x}. Reply ONLY the description.", 120)
        if not ds: return None
        a, b, cons = teachers(f"You are BioMate. The workflow expects inputs: {x}. Is this dataset compatible? Reply YES or NO + one-line reason.\nDataset: {ds}")
        return {"task": "dataset_compatibility", "query": ds, "db_gold": x, "teacher_gpt56": a, "teacher_gemini": b, "consensus": cons, "workflow": wf}
    return None


def run(kind_filter, anchors, outname):
    anchors = anchors[:CAP]
    res = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = [ex.submit(process, k, wf, x) for (k, wf, x) in anchors if k == kind_filter or kind_filter == "*"]
        for i, f in enumerate(as_completed(futs)):
            r = f.result()
            if r: res.append(r)
            if (i + 1) % 100 == 0: print(f"  {outname}: {i+1}", flush=True)
    # split by task (a mixed batch may hold clar+cond)
    bytask = {}
    for r in res: bytask.setdefault(r["task"], []).append(r)
    for t, rs in bytask.items():
        with open(f"{POOL}/committee_{t}.jsonl", "w") as fo:
            for r in rs: fo.write(json.dumps(r) + "\n")
        cons = sum(1 for r in rs if r.get("consensus"))
        print(f"COMMITTEE {t}: {len(rs)} | consensus {cons}", flush=True)


rp = wf_required_params(); random.shuffle(rp)
run("clar", rp, "clarification")
run("cond", rp, "conditional_param")
run("chain", wkg_pairs(), "chaining")
run("diag", real_errors(), "diagnosis")
run("compat", io_anchors(), "dataset_compatibility")
print("DIVERSE_TASKS_DONE", flush=True)
