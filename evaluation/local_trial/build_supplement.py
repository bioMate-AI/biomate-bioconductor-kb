"""Rebalance starved tasks + add new-version LLM targets N1-N4 (task taxonomy re-exam). gemini-flash,
one call/anchor, grounded. Appends to interactions.jsonl.
  chaining        <- WKG precede edges (A->B)
  task_decomposition <- multi-step step_metadata DAGs
  N1 lane_arbitration <- workflow/knowledge/design/prediction scenarios -> lane + why
  N3 design_constraint <- de-novo design goals -> {stage,target,scaffold,property,count}
  N4 model_selection <- prediction requests -> which pretrained model + applicability
(N1 out-of-catalog composition itself = existing composition_sft.jsonl, folded at assembly.)
"""
import json, os, re, sqlite3, random, urllib.request, hashlib
from concurrent.futures import ThreadPoolExecutor, as_completed
REPO = "/Users/kky/biomate-review"; DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
P = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
GK = os.environ["GOOGLE_API_KEY"]; CAP = int(os.environ.get("CAP", "1200")); WORKERS = int(os.environ.get("WORKERS", "24"))
random.seed(23)
split = json.load(open(f"{P}/workflow_split.json")) if os.path.exists(f"{P}/workflow_split.json") else {}
c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True); c.row_factory = sqlite3.Row


def gem(prompt, mx=1200):
    u = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key={GK}"
    b = json.dumps({"contents": [{"parts": [{"text": prompt}]}], "generationConfig": {"maxOutputTokens": max(mx, 1200)}}).encode()
    for _ in range(4):
        try:
            ca = json.load(urllib.request.urlopen(urllib.request.Request(u, data=b, headers={"Content-Type": "application/json"}), timeout=60))["candidates"][0]
            if ca.get("finishReason") in (None, "STOP"):
                return "".join(x.get("text", "") for x in ca.get("content", {}).get("parts", [])).strip()
        except Exception: pass
    return ""


def hsplit(k): return "eval" if int(hashlib.sha256(str(k).encode()).hexdigest(), 16) % 100 < 15 else "train"
def okq(q): return bool(q and len(q.strip()) >= 25 and " " in q.strip())


def chain_anchors():
    p = f"{P}/../routing_data_v1/wkg.json"
    if not os.path.exists(p): return []
    pre = json.load(open(p)).get("precede") or {}
    return [("chain", a, b) for a, s in pre.items() for b in (s or [])[:1]]
def dag_anchors():
    out = []
    for r in c.execute("select name,step_metadata from workflows where step_metadata is not null and length(step_metadata)>80"):
        try: s = json.loads(r["step_metadata"])
        except: continue
        st = [x.get("step") for x in s if isinstance(x, dict) and x.get("step")]
        if len(st) >= 4: out.append(("dag", r["name"], st))
    return out
def wf_anchors():
    return [("lane", r["name"], r["domain"]) for r in c.execute("select name,domain from workflows where domain is not null limit 3000")]


def build(kind, a, x):
    if kind == "chain":
        q = gem(f"Write a realistic request needing workflow '{a}' then '{x}' in sequence (A output feeds B). Reply ONLY the request.")
        if not okq(q): return None
        return {"task_type": "multi_workflow_chaining", "input": q, "target": json.dumps([a, x]), "source": "supp_chain", "split": hsplit(q)}
    if kind == "dag":
        goal = "; ".join(x[:6])
        q = gem(f"Write a realistic multi-step analysis request whose plan is: {goal}. Reply ONLY the request.")
        if not okq(q): return None
        return {"task_type": "task_decomposition", "input": q, "target": json.dumps([{"sub_task": s, "order": i + 1} for i, s in enumerate(x)]), "source": "supp_dag", "workflow": a, "split": split.get(a, {}).get("split") or hsplit(q)}
    if kind == "lane":  # N2
        out = gem(f"For BioMate workflow '{a}' (domain {x}): write a realistic user goal AND classify the correct execution lane among "
                  f"[instant_cited, instant_compute, cloud_workflow, cloud_design, cloud_models] with a one-sentence why. "
                  f'Reply ONLY JSON {{"user":...,"lane":...,"why":...}}.')
        try: d = json.loads(re.search(r"\{.*\}", out, re.S).group(0))
        except: return None
        if not (d.get("user") and d.get("lane")): return None
        return {"task_type": "lane_arbitration", "input": d["user"], "target": f"{d['lane']}: {d.get('why','')}", "source": "supp_N2", "split": hsplit(d["user"])}
    return None


DESIGN_SEEDS = ["a novel kinase inhibitor scaffold", "macrocyclic peptide binders for a PPI target",
                "de-novo antibody CDR-H3 for an antigen", "PROTAC linkers for a given warhead+E3",
                "small molecules optimizing logP and hERG safety", "RNA aptamers for a protein target"]
PREDICT_SEEDS = ["protein 3D structure from sequence", "ADMET (hERG, CYP, oral bioavailability)",
                 "protein-ligand binding affinity", "variant pathogenicity", "cell-type from scRNA profile",
                 "molecular property (solubility, logD)"]


def n3(seed):  # design-constraint extraction
    out = gem(f"Write a realistic de-novo design request for: {seed}. Then extract its constraints. "
              f'Reply ONLY JSON {{"user":...,"stage":"generate|optimize|rank","target":...,"scaffold_policy":...,"property_envelope":...,"count":N}}.')
    try: d = json.loads(re.search(r"\{.*\}", out, re.S).group(0))
    except: return None
    if not d.get("user"): return None
    tgt = {k: d.get(k) for k in ("stage", "target", "scaffold_policy", "property_envelope", "count")}
    return {"task_type": "design_constraint", "input": d["user"], "target": json.dumps(tgt), "source": "supp_N3", "split": hsplit(d["user"])}
def n4(seed):  # model selection + applicability
    out = gem(f"Write a realistic user request to predict: {seed}. Then name the appropriate pretrained model class and state "
              f'what it can/can''t speak to. Reply ONLY JSON {{"user":...,"model":...,"applicability":...}}.')
    try: d = json.loads(re.search(r"\{.*\}", out, re.S).group(0))
    except: return None
    if not d.get("user"): return None
    return {"task_type": "model_selection", "input": d["user"], "target": f"{d.get('model','')}: {d.get('applicability','')}", "source": "supp_N4", "split": hsplit(d["user"])}


def run(name, kind, anchors):
    anchors = anchors[:CAP]; out = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for i, f in enumerate(as_completed([ex.submit(build, kind, a, x) for (_, a, x) in anchors])):
            r = f.result()
            if r: out.append(r)
    print(f"  {name}: {len(out)}", flush=True); return out


rows = []
ch = chain_anchors(); random.shuffle(ch); rows += run("chaining", "chain", ch)
dg = dag_anchors(); random.shuffle(dg); rows += run("decomposition", "dag", dg)
wl = wf_anchors(); random.shuffle(wl); rows += run("lane_arbitration(N2)", "lane", wl[:CAP])
# N3/N4: many samples over the seeds
for gen, name, seeds, n in [(n3, "design_constraint(N3)", DESIGN_SEEDS, 500), (n4, "model_selection(N4)", PREDICT_SEEDS, 400)]:
    out = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for f in as_completed([ex.submit(gen, random.choice(seeds)) for _ in range(n)]):
            r = f.result()
            if r: out.append(r)
    print(f"  {name}: {len(out)}", flush=True); rows += out

with open(f"{P}/interactions.jsonl", "a") as f:
    for r in rows: f.write(json.dumps(r) + "\n")
import collections
print("SUPPLEMENT DONE. +", len(rows), dict(collections.Counter(r["task_type"] for r in rows)), flush=True)
