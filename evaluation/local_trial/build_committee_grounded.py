"""Fix 1 (committee data audit): rerun committee distillation the way BioMate ACTUALLY runs —
retrieval-GROUNDED for routing (teachers pick from real top-k candidates or NO_MATCH) and
SCHEMA-GROUNDED for param (teachers emit only real schema keys). Reuses the Phase-2 synthesized queries.
Separates candidate-RECALL (retrieval) from teacher SELECTION quality, per the audit. API + local TF-IDF.
Output: data_pool_v2/grounded_routing.jsonl , grounded_param.jsonl
"""
import json, os, re, sqlite3, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
REPO = "/Users/kky/biomate-review"; POOL = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
OK, GK = os.environ["OPENAI_API_KEY"], os.environ["GOOGLE_API_KEY"]
WORKERS = int(os.environ.get("WORKERS", "8")); K = 20


def openai(p, mx=500):
    try:
        b = json.dumps({"model": "gpt-5.6", "messages": [{"role": "user", "content": p}], "max_completion_tokens": mx, "reasoning_effort": "low"}).encode()
        r = urllib.request.Request("https://api.openai.com/v1/chat/completions", data=b, headers={"Authorization": f"Bearer {OK}", "Content-Type": "application/json"})
        return json.load(urllib.request.urlopen(r, timeout=120))["choices"][0]["message"]["content"].strip()
    except Exception: return ""


def gemini(p):
    try:
        u = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key={GK}"
        b = json.dumps({"contents": [{"parts": [{"text": p}]}]}).encode()
        d = json.load(urllib.request.urlopen(urllib.request.Request(u, data=b, headers={"Content-Type": "application/json"}), timeout=120))
        return "".join(x.get("text", "") for x in d["candidates"][0]["content"]["parts"]).strip()
    except Exception: return ""


def norm(s): return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()

c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True); c.row_factory = sqlite3.Row

# ---- ROUTING: TF-IDF retriever over workflow docs ----
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
wf = [dict(r) for r in c.execute("select name,domain,description,input_types,output_types,tools_used from workflows where description is not null")]
names = [w["name"] for w in wf]
docs = [" ".join(str(w.get(k) or "") for k in ("name", "domain", "description", "input_types", "output_types", "tools_used"))[:2000] for w in wf]
vec = TfidfVectorizer(ngram_range=(1, 2), min_df=2, max_features=50000); M = vec.fit_transform(docs)


def retrieve(q, k=K):
    sc = cosine_similarity(vec.transform([q]), M)[0]
    import numpy as np
    return [names[i] for i in np.argsort(-sc)[:k]]


def route_one(r):
    q, gold = r["query"], r.get("db_gold")
    cands = retrieve(q)
    cand_recall = gold in cands if gold else None
    prompt = (f"You are BioMate. Choose the SINGLE best workflow for the request from the CANDIDATES, "
              f"or reply NO_MATCH. Reply ONLY the exact candidate name.\n\nCandidates:\n" +
              "\n".join(f"- {x}" for x in cands) + f"\n\nRequest: {q}")
    a, b = openai(prompt), gemini(prompt)
    pa = next((x for x in cands if norm(x) == norm(a)), a); pb = next((x for x in cands if norm(x) == norm(b)), b)
    return {"task": "routing_grounded", "query": q, "db_gold": gold, "candidates_k": len(cands),
            "candidate_recall": cand_recall, "gpt_pick": pa, "gemini_pick": pb,
            "gpt_in_cands": pa in cands, "consensus": norm(pa) == norm(pb),
            "gpt_correct": (norm(pa) == norm(gold)) if gold else None,
            "gemini_correct": (norm(pb) == norm(gold)) if gold else None}


# ---- PARAM: schema-grounded ----
schema_of = {}
for r in c.execute("select name,params_schema from workflows where params_schema is not null"):
    try:
        s = json.loads(r["params_schema"]); pl = s.get("parameters") or [] if isinstance(s, dict) else []
        schema_of[r["name"]] = [p.get("name") for p in pl if isinstance(p, dict) and p.get("name")]
    except Exception: pass


def param_one(r):
    q, wfn, gold = r["query"], r.get("workflow"), r.get("db_gold")
    keys = schema_of.get(wfn, [])
    if not keys: return None
    prompt = (f"You are BioMate. Extract parameters this request implies, using ONLY these exact schema "
              f"keys (omit any not implied): {keys}. Reply ONLY a JSON object of key:value.\n\nRequest: {q}")
    a = openai(prompt)
    try: ext = json.loads(re.search(r"\{.*\}", a, re.S).group(0))
    except Exception: ext = {}
    valid = {k: v for k, v in ext.items() if k in keys}
    gkeys = set((gold or {}).keys())
    return {"task": "param_grounded", "query": q, "workflow": wfn, "db_gold": gold,
            "extracted": valid, "schema_valid_keys": len(valid) == len(ext) and len(ext) > 0,
            "key_recall": (len(gkeys & set(valid)) / len(gkeys)) if gkeys else None}


def run(name, infile, fn):
    rows = [json.loads(l) for l in open(f"{POOL}/{infile}")]
    out = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for i, f in enumerate(as_completed([ex.submit(fn, r) for r in rows])):
            r = f.result()
            if r: out.append(r)
            if (i + 1) % 100 == 0: print(f"  {name}: {i+1}/{len(rows)}", flush=True)
    with open(f"{POOL}/{name}.jsonl", "w") as fo:
        for r in out: fo.write(json.dumps(r) + "\n")
    return out


rt = run("grounded_routing", "committee_routing.jsonl", route_one)
cr = sum(1 for r in rt if r["candidate_recall"]); gc = sum(1 for r in rt if r.get("gpt_correct"))
sel = sum(1 for r in rt if r["candidate_recall"] and r.get("gpt_correct"))
print(f"ROUTING grounded: n={len(rt)} | candidate_recall@{K}={cr}/{len(rt)} ({cr/max(len(rt),1):.2f}) | "
      f"gpt_correct={gc} ({gc/max(len(rt),1):.2f}) | selection-given-recall={sel}/{max(cr,1)} ({sel/max(cr,1):.2f})", flush=True)
pm = run("grounded_param", "committee_param.jsonl", param_one)
sv = sum(1 for r in pm if r["schema_valid_keys"])
print(f"PARAM grounded: n={len(pm)} | schema-valid={sv} ({sv/max(len(pm),1):.2f})", flush=True)
print("GROUNDED_REDISTILL_DONE", flush=True)
