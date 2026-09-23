"""Real-scale interaction generation: MULTIPLE diverse interactions per anchor (one call -> K JSON list)
+ the full 12,312-tool DB (never used before). gemini-flash mx=3000. Target 60k+. Task type emerges.
Output: data_pool_v2/interactions_v2.jsonl {anchor_type, task_type, input, target, split, source}
"""
import json, os, re, sqlite3, random, urllib.request, hashlib
from concurrent.futures import ThreadPoolExecutor, as_completed
REPO = "/Users/kky/biomate-review"; DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
P = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
GK = os.environ["GOOGLE_API_KEY"]; WORKERS = int(os.environ.get("WORKERS", "24"))
random.seed(23)
split = json.load(open(f"{P}/workflow_split.json")) if os.path.exists(f"{P}/workflow_split.json") else {}
c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True); c.row_factory = sqlite3.Row


def gem(prompt, mx=3000):
    u = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key={GK}"
    b = json.dumps({"contents": [{"parts": [{"text": prompt}]}], "generationConfig": {"maxOutputTokens": mx}}).encode()
    for _ in range(4):
        try:
            ca = json.load(urllib.request.urlopen(urllib.request.Request(u, data=b, headers={"Content-Type": "application/json"}), timeout=90))["candidates"][0]
            if ca.get("finishReason") in (None, "STOP"):
                return "".join(x.get("text", "") for x in ca.get("content", {}).get("parts", [])).strip()
        except Exception: pass
    return ""


def hsplit(k): return "eval" if int(hashlib.sha256(str(k).encode()).hexdigest(), 16) % 100 < 15 else "train"
def wsplit(wf): return split.get(wf, {}).get("split") if wf else None
MENU = ("workflow_routing, parameter_extraction, clarification_request, task_decomposition, "
        "dataset_prerequisite_check, multi_workflow_chaining, in_conversation_param_change, "
        "workflow_generation, knowledge_recall, scientific_qa, tool_recommendation, "
        "literal_data_extraction, log_diagnosis, autofix_repair, findings_interpretation")


def parse_list(txt):
    m = re.search(r"\[.*\]", txt or "", re.S)
    if not m: return []
    try: arr = json.loads(m.group(0))
    except Exception: return []
    return [d for d in arr if isinstance(d, dict) and d.get("user") and d.get("assistant") and d.get("task_type")
            and len(str(d["user"]).strip()) >= 20]


def wf_job(r):
    facts = (f"name: {r['name']}\ndomain: {r['domain']}\ndescription: {(r['description'] or '')[:500]}\n"
             f"inputs: {r['input_types']} | outputs: {r['output_types']} | tools: {r['tools_used']}\nparams: {(r['params_schema'] or '')[:350]}")
    p = (f"Given this REAL BioMate workflow:\n{facts}\n\nGenerate 6 DIVERSE realistic single-turn BioMate "
         f"interactions, EACH A DIFFERENT task type from: {MENU}. Ground strictly in the facts — never invent "
         f'workflow names or params. Reply ONLY a JSON list of {{"task_type":...,"user":...,"assistant":...}}.')
    sp = wsplit(r["name"])
    return [{"anchor_type": "workflow", "task_type": d["task_type"], "input": d["user"], "target": d["assistant"],
             "workflow": r["name"], "split": sp or hsplit(d["user"]), "source": "interv2_wf"} for d in parse_list(gem(p))]


def tool_job(r):
    facts = (f"tool: {r['name']}\ncategory: {r['category']}\ndescription: {(r['description'] or '')[:400]}\n"
             f"context: {(r['scientific_context'] or '')[:400]}\nparams: {(r['parameters'] or '')[:300]}")
    p = (f"Given this REAL bioinformatics TOOL in BioMate:\n{facts}\n\nGenerate 3 DIVERSE realistic BioMate "
         f"interactions about it (e.g. tool_recommendation, parameter help, knowledge_recall, when-to-use, "
         f'scientific_qa). Ground in the facts. Reply ONLY a JSON list of {{"task_type":...,"user":...,"assistant":...}}.')
    return [{"anchor_type": "tool", "task_type": d["task_type"], "input": d["user"], "target": d["assistant"],
             "split": hsplit(r["name"] + d["user"][:20]), "source": "interv2_tool"} for d in parse_list(gem(p, 2200))]


def err_job(r):
    p = (f"BioMate workflow '{r['name']}' failed:\n{(r['real_exec_err'] or '')[:1100]}\n\nGenerate 2 interactions "
         f'(log_diagnosis + autofix_repair). Reply ONLY a JSON list of {{"task_type":...,"user":...,"assistant":...}}.')
    return [{"anchor_type": "error", "task_type": d["task_type"], "input": d["user"], "target": d["assistant"],
             "workflow": r["name"], "split": hsplit((r["real_exec_err"] or "")[:80]), "source": "interv2_err"} for d in parse_list(gem(p, 1600))]


def main():
    jobs = []
    for r in c.execute("select name,domain,description,input_types,output_types,tools_used,params_schema from workflows where description is not null and length(description)>20"):
        jobs.append((wf_job, dict(r)))
    for r in c.execute("select name,category,description,scientific_context,parameters from tools where description is not null and length(description)>30"):
        jobs.append((tool_job, dict(r)))
    for r in c.execute("select name,real_exec_err from workflows where real_exec_err is not null and length(real_exec_err)>40"):
        jobs.append((err_job, dict(r)))
    random.shuffle(jobs)
    print(f"anchors: {len(jobs)} (workflows + tools + errors) -> expect ~{len(jobs)*3} interactions", flush=True)
    out = []
    with open(f"{P}/interactions_v2.jsonl", "w") as fo:
        with ThreadPoolExecutor(max_workers=WORKERS) as ex:
            for i, f in enumerate(as_completed([ex.submit(fn, a) for fn, a in jobs])):
                recs = f.result() or []
                for r in recs: fo.write(json.dumps(r) + "\n")
                out += recs
                if (i + 1) % 1000 == 0:
                    import collections
                    print(f"  {i+1}/{len(jobs)} anchors -> {len(out)} interactions, {len(set(r['task_type'] for r in out))} types", flush=True)
    import collections
    tt = collections.Counter(r["task_type"] for r in out)
    print(f"INTERACTIONS_V2 DONE: {len(out)} interactions, {len(tt)} task types:", flush=True)
    for t, n in tt.most_common(): print(f"  {t}: {n}")


if __name__ == "__main__":
    raise SystemExit(main())
