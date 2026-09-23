"""Input-driven, full-spectrum interaction generation (replaces the 5 hardcoded task generators).
Given a DIVERSE real anchor (workflow / error / doc / tool / chain), the teacher produces ONE realistic
BioMate interaction of WHATEVER type fits — task type EMERGES (self-labeled), grounded in the anchor.
Diverse inputs -> the full task spectrum (T01-T26) naturally. gemini-flash, mx>=1024, high concurrency.
Output: data_pool_v2/interactions.jsonl  {anchor_type, task_type, input, target, split, source}
"""
import json, os, re, sqlite3, random, urllib.request, hashlib
from concurrent.futures import ThreadPoolExecutor, as_completed
REPO = "/Users/kky/biomate-review"; DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
P = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
GK = os.environ["GOOGLE_API_KEY"]; CAP = int(os.environ.get("CAP", "100000")); WORKERS = int(os.environ.get("WORKERS", "24"))
random.seed(23)
split = json.load(open(f"{P}/workflow_split.json")) if os.path.exists(f"{P}/workflow_split.json") else {}
c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True); c.row_factory = sqlite3.Row


def gem(prompt, mx=1400):
    u = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key={GK}"
    b = json.dumps({"contents": [{"parts": [{"text": prompt}]}], "generationConfig": {"maxOutputTokens": max(mx, 1400)}}).encode()
    for _ in range(4):
        try:
            ca = json.load(urllib.request.urlopen(urllib.request.Request(u, data=b, headers={"Content-Type": "application/json"}), timeout=60))["candidates"][0]
            if ca.get("finishReason") in (None, "STOP"):
                return "".join(x.get("text", "") for x in ca.get("content", {}).get("parts", [])).strip()
        except Exception: pass
    return ""


def hsplit(k): return "eval" if int(hashlib.sha256(str(k).encode()).hexdigest(), 16) % 100 < 15 else "train"
def wsplit(wf): return split.get(wf, {}).get("split") if wf else None

# the FULL in-scope task menu the teacher can pick from (T01-T26, IND excluded)
MENU = ("intent_classification, literal_data_extraction, workflow_routing, parameter_extraction, "
        "clarification_request, dataset_prerequisite_check, workflow_generation, task_decomposition, "
        "multi_workflow_chaining, in_conversation_param_change, nextflow_composition, scientific_qa, "
        "evidence_synthesis, log_diagnosis, autofix_repair, findings_interpretation, methods_report, "
        "tool_recommendation, session_summary, yes_no_classification")


def parse(txt):
    try:
        d = json.loads(re.search(r"\{.*\}", txt, re.S).group(0))
        if d.get("user") and d.get("assistant") and d.get("task_type"):
            return d
    except Exception: pass
    return None


def wf_anchor(r):
    facts = (f"name: {r['name']}\ndomain: {r['domain']}\ndescription: {(r['description'] or '')[:600]}\n"
             f"inputs: {r['input_types']}\noutputs: {r['output_types']}\ntools: {r['tools_used']}\nparams: {(r['params_schema'] or '')[:400]}")
    prompt = (f"You are generating ONE realistic training interaction for BioMate (agentic bioinformatics "
              f"assistant). Here is a REAL catalog workflow:\n{facts}\n\nInvent a realistic single-turn user "
              f"message and the correct BioMate response. Pick the MOST NATURAL interaction type for THIS "
              f"workflow from: {MENU}. Ground everything in the facts above — never invent workflow names or "
              f'params. Reply ONLY JSON: {{"task_type": "...", "user": "...", "assistant": "..."}}')
    d = parse(gem(prompt))
    if not d: return None
    return {"anchor_type": "workflow", "task_type": d["task_type"], "input": d["user"], "target": d["assistant"],
            "workflow": r["name"], "split": wsplit(r["name"]) or hsplit(d["user"]), "source": "interaction_wf"}


def err_anchor(r):
    prompt = (f"You are generating ONE realistic BioMate interaction from a REAL pipeline error. Workflow "
              f"'{r['name']}' failed with:\n{(r['real_exec_err'] or '')[:1200]}\n\nInvent the realistic user "
              f"message (reporting/asking about the failure) and the correct BioMate response. Type is one of: "
              f'log_diagnosis, autofix_repair. Reply ONLY JSON: {{"task_type": "...", "user": "...", "assistant": "..."}}')
    d = parse(gem(prompt))
    if not d: return None
    return {"anchor_type": "error", "task_type": d["task_type"], "input": d["user"], "target": d["assistant"],
            "workflow": r["name"], "split": hsplit((r["real_exec_err"] or "")[:100]), "source": "interaction_err"}


def doc_anchor(r):
    txt = (r.get("q", "") + "\n" + r.get("a", ""))[:400]
    prompt = (f"From this BioMate knowledge snippet, generate ONE realistic user question + correct grounded "
              f"answer. Type: scientific_qa or knowledge_recall.\nSnippet:\n{txt}\n\nReply ONLY JSON: "
              f'{{"task_type": "...", "user": "...", "assistant": "..."}}')
    d = parse(gem(prompt))
    if not d: return None
    return {"anchor_type": "doc", "task_type": d["task_type"], "input": d["user"], "target": d["assistant"],
            "split": hsplit(txt), "source": "interaction_doc"}


def main():
    tasks = []
    wfs = [dict(r) for r in c.execute("select name,domain,description,input_types,output_types,tools_used,params_schema from workflows where description is not null and length(description)>20")]
    for r in wfs[:CAP]: tasks.append((wf_anchor, r))
    for r in c.execute("select name,real_exec_err from workflows where real_exec_err is not null and length(real_exec_err)>40"):
        tasks.append((err_anchor, dict(r)))
    docp = f"{P}/self_docs_qa_clean.jsonl"
    if os.path.exists(docp):
        for l in open(docp): tasks.append((doc_anchor, json.loads(l)))
    random.shuffle(tasks); tasks = tasks[:CAP]
    out = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for i, f in enumerate(as_completed([ex.submit(fn, a) for fn, a in tasks])):
            r = f.result()
            if r: out.append(r)
            if (i + 1) % 500 == 0:
                import collections
                print(f"  {i+1}/{len(tasks)} | task types so far: {len(set(x['task_type'] for x in out))}", flush=True)
    with open(f"{P}/interactions.jsonl", "w") as fo:
        for r in out: fo.write(json.dumps(r) + "\n")
    import collections
    tt = collections.Counter(r["task_type"] for r in out)
    print(f"INTERACTIONS DONE: {len(out)} | {len(tt)} DISTINCT task types emerged:")
    for t, n in tt.most_common(): print(f"  {t}: {n}")


if __name__ == "__main__":
    raise SystemExit(main())
