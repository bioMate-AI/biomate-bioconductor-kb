"""BATCHED interaction generation: B anchors per prompt -> list of results. Cuts API calls ~Bx.
gemini-flash mx=8000, backoff, high concurrency. Anchors = workflows + full tool DB + errors.
Output: data_pool_v2/interactions_v2.jsonl {anchor_type, task_type, input, target, split, source}
"""
import json, os, re, sqlite3, random, urllib.request, hashlib, time
from concurrent.futures import ThreadPoolExecutor, as_completed
REPO = "/Users/kky/biomate-review"; DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
P = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
GK = os.environ["GOOGLE_API_KEY"]; WORKERS = int(os.environ.get("WORKERS", "64")); B = int(os.environ.get("BATCH", "5"))
random.seed(23)
split = json.load(open(f"{P}/workflow_split.json")) if os.path.exists(f"{P}/workflow_split.json") else {}
c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True); c.row_factory = sqlite3.Row


def gem(prompt, mx=8000):
    u = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key={GK}"
    b = json.dumps({"contents": [{"parts": [{"text": prompt}]}], "generationConfig": {"maxOutputTokens": mx}}).encode()
    for a in range(6):
        try:
            ca = json.load(urllib.request.urlopen(urllib.request.Request(u, data=b, headers={"Content-Type": "application/json"}), timeout=120))["candidates"][0]
            return "".join(x.get("text", "") for x in ca.get("content", {}).get("parts", [])).strip()  # keep partial too
        except Exception:
            time.sleep(min(2 ** a, 20))
    return ""


def hsplit(k): return "eval" if int(hashlib.sha256(str(k).encode()).hexdigest(), 16) % 100 < 15 else "train"
def wsplit(wf): return split.get(wf, {}).get("split") if wf else None
MENU = ("workflow_routing, parameter_extraction, clarification_request, task_decomposition, "
        "dataset_prerequisite_check, multi_workflow_chaining, workflow_generation, knowledge_recall, "
        "scientific_qa, tool_recommendation, log_diagnosis, autofix_repair, findings_interpretation")


def facts(a):
    if a["type"] == "workflow":
        return (f"[{a['i']}] WORKFLOW {a['name']} (domain {a['domain']}): {(a['desc'] or '')[:320]} | "
                f"in:{a['inp']} out:{a['out']} tools:{a['tools']} params:{(a['params'] or '')[:180]}")
    if a["type"] == "tool":
        return f"[{a['i']}] TOOL {a['name']} ({a['cat']}): {(a['desc'] or '')[:260]} ctx:{(a['ctx'] or '')[:200]}"
    return f"[{a['i']}] ERROR from workflow {a['name']}: {(a['err'] or '')[:600]}"


def batch_job(batch):
    items = "\n".join(facts(a) for a in batch)
    prompt = (f"For EACH of the following {len(batch)} BioMate items, generate 3 DIVERSE realistic single-turn "
              f"interactions grounded in that item's facts (never invent names/params). Task types from: {MENU} "
              f"(errors -> log_diagnosis/autofix_repair). Reply ONLY a JSON list, one object per item: "
              f'{{"i": <index>, "interactions": [{{"task_type":...,"user":...,"assistant":...}}, x3]}}.\n\nITEMS:\n{items}')
    txt = gem(prompt)
    m = re.search(r"\[.*\]", txt, re.S)
    if not m: return []
    try: arr = json.loads(m.group(0))
    except Exception:
        # salvage: parse as many complete objects as possible
        arr = []
        for om in re.finditer(r'\{"i":\s*(\d+),\s*"interactions":\s*(\[.*?\])\}', m.group(0), re.S):
            try: arr.append({"i": int(om.group(1)), "interactions": json.loads(om.group(2))})
            except Exception: pass
    by = {a["i"]: a for a in batch}
    out = []
    for obj in arr:
        if not isinstance(obj, dict): continue
        a = by.get(obj.get("i"))
        if not a: continue
        for d in obj.get("interactions", []):
            if isinstance(d, dict) and d.get("user") and d.get("assistant") and d.get("task_type") and len(str(d["user"]).strip()) >= 20:
                out.append({"anchor_type": a["type"], "task_type": d["task_type"], "input": d["user"],
                            "target": d["assistant"], "workflow": a.get("name") if a["type"] != "tool" else None,
                            "split": wsplit(a.get("name")) or hsplit(d["user"]), "source": f"interv3_{a['type']}"})
    return out


def main():
    anchors, i = [], 0
    for r in c.execute("select name,domain,description,input_types,output_types,tools_used,params_schema from workflows where description is not null and length(description)>20"):
        anchors.append({"i": i, "type": "workflow", "name": r["name"], "domain": r["domain"], "desc": r["description"], "inp": r["input_types"], "out": r["output_types"], "tools": r["tools_used"], "params": r["params_schema"]}); i += 1
    for r in c.execute("select name,category,description,scientific_context from tools where description is not null and length(description)>30"):
        anchors.append({"i": i, "type": "tool", "name": r["name"], "cat": r["category"], "desc": r["description"], "ctx": r["scientific_context"]}); i += 1
    for r in c.execute("select name,real_exec_err from workflows where real_exec_err is not null and length(real_exec_err)>40"):
        anchors.append({"i": i, "type": "error", "name": r["name"], "err": r["real_exec_err"]}); i += 1
    random.shuffle(anchors)
    # re-index within each batch so [i] refs are local 0..B-1
    batches = []
    for k in range(0, len(anchors), B):
        grp = anchors[k:k + B]
        for j, a in enumerate(grp): a["i"] = j
        batches.append(grp)
    print(f"{len(anchors)} anchors -> {len(batches)} batched calls (B={B}) at {WORKERS} workers", flush=True)
    out = []
    with open(f"{P}/interactions_v2.jsonl", "w") as fo:
        with ThreadPoolExecutor(max_workers=WORKERS) as ex:
            for n, f in enumerate(as_completed([ex.submit(batch_job, b) for b in batches])):
                recs = f.result() or []
                for r in recs: fo.write(json.dumps(r) + "\n")
                out += recs
                if (n + 1) % 200 == 0:
                    print(f"  {n+1}/{len(batches)} batches -> {len(out)} interactions", flush=True)
    import collections
    tt = collections.Counter(r["task_type"] for r in out)
    print(f"BATCHED DONE: {len(out)} interactions, {len(tt)} task types: {dict(tt.most_common())}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
