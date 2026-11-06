"""Phase 2: committee-as-teacher distillation pool. For each real gold anchor (Phase 1), a teacher
synthesizes a realistic user query (anti-circular: persona-based, never quoting the description), then
BOTH teachers (gpt-5.6 + gemini-3.8-flash) answer AS BioMate. We record both responses, their consensus,
and agreement with the DB gold. Consensus = silver gold; DB gold = ground truth; disagreements flagged.

API-only (no GPU). Parallel. CAP per task via env CAP (default 500). Output: data_pool_v2/committee_<task>.jsonl
"""
import json, os, re, random, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
REPO = "/Users/kky/biomate-review"; POOL = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
CAP = int(os.environ.get("CAP", "500")); WORKERS = int(os.environ.get("WORKERS", "8"))
OK, GK = os.environ["OPENAI_API_KEY"], os.environ["GOOGLE_API_KEY"]
random.seed(23)


def openai(prompt, model="gpt-5.6", mx=1200):
    body = json.dumps({"model": model, "messages": [{"role": "user", "content": prompt}],
                       "max_completion_tokens": mx, "reasoning_effort": "low"}).encode()
    try:
        r = urllib.request.Request("https://api.openai.com/v1/chat/completions", data=body,
                                   headers={"Authorization": f"Bearer {OK}", "Content-Type": "application/json"})
        return json.load(urllib.request.urlopen(r, timeout=120))["choices"][0]["message"]["content"].strip()
    except Exception: return ""


def gemini(prompt, model="gemini-3.8-flash"):
    try:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={GK}"
        body = json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode()
        d = json.load(urllib.request.urlopen(urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"}), timeout=120))
        return "".join(p.get("text", "") for p in d["candidates"][0]["content"]["parts"]).strip()
    except Exception: return ""


def norm(s): return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()


# per-task: (query-synthesis prompt from anchor, BioMate-answer prompt from query, gold extractor)
def synth_prompt(task, a):
    if task in ("routing", "wfgen"):
        an = a["anchor"]
        return (f"Write a realistic, natural user request a scientist would type that should be handled by the "
                f"bioinformatics workflow '{a['workflow']}' (domain {a.get('domain')}). Use the real I/O as a hint "
                f"but DO NOT quote its description. Inputs: {an.get('input_types')}. Outputs: {an.get('output_types')}. "
                f"Tools: {an.get('tools_used')}. Reply ONLY the user request (1-3 sentences).")
    if task == "param":
        return (f"Write a realistic user request for a '{a['workflow']}' analysis that IMPLIES these parameter "
                f"values WITHOUT naming the parameter keys: {json.dumps(a['gold_params'])}. Reply ONLY the request.")
    if task == "decompose":
        goal = "; ".join(s.get("sub_task", "") for s in a["gold"][:6])
        return (f"Write a realistic multi-step analysis request whose correct plan is roughly: {goal}. "
                f"Reply ONLY the user request (2-4 sentences).")
    return ""


def answer_prompt(task, q, a):
    if task == "routing":
        return f"You are BioMate. Name the single correct workflow for this request. Reply ONLY the workflow name.\n\nRequest: {q}"
    if task == "wfgen":
        return f"You are BioMate. Name the workflow CATEGORY/domain for this request. Reply ONLY the category.\n\nRequest: {q}"
    if task == "param":
        return f"You are BioMate. Extract ONLY the parameters explicitly implied by this request as key: value lines. Do not invent.\n\nRequest: {q}"
    if task == "autofix":
        return f"You are BioMate. A pipeline failed. Classify the failure into ONE fix category. Reply ONLY the category.\n\nError log:\n{a['error_log']}"
    if task == "decompose":
        return f'You are BioMate. Decompose into an ordered sub-task plan. Reply ONLY a JSON list of {{"sub_task":...,"order":N}}.\n\nRequest: {q}'
    return ""


def gold_of(task, a):
    return {"routing": a.get("gold_workflow"), "wfgen": a.get("gold_category"),
            "param": a.get("gold_params"), "decompose": a.get("gold"), "autofix": None}.get(task)


def process(task, a):
    # autofix uses the real error directly as input; others synthesize a query
    q = a["error_log"][:400] if task == "autofix" else openai(synth_prompt(task, a), mx=300)
    if task != "autofix" and not q:
        return None
    ra = openai(answer_prompt(task, q, a))
    rb = gemini(answer_prompt(task, q, a))
    if not ra and not rb:
        return None
    consensus = bool(ra and rb and (norm(ra)[:60] in norm(rb) or norm(rb)[:60] in norm(ra)))
    g = gold_of(task, a)
    agrees = None
    if g and isinstance(g, str):
        agrees = norm(g) in norm(ra) or norm(g) in norm(rb)
    return {"task": task, "split": a.get("split", "train"), "query": q, "db_gold": g,
            "teacher_gpt56": ra, "teacher_gemini": rb, "consensus": consensus, "agrees_db_gold": agrees,
            "workflow": a.get("workflow")}


def main():
    tasks = {"routing": "anchor_routing.jsonl", "wfgen": "anchor_wfgen.jsonl", "param": "anchor_param.jsonl",
             "autofix": "anchor_autofix.jsonl", "decompose": "decomp_intra.jsonl"}
    for task, fn in tasks.items():
        p = f"{POOL}/{fn}"
        if not os.path.exists(p): continue
        anchors = [json.loads(l) for l in open(p)]
        random.shuffle(anchors); anchors = anchors[:CAP]
        out = []
        with ThreadPoolExecutor(max_workers=WORKERS) as ex:
            futs = [ex.submit(process, task, a) for a in anchors]
            for i, f in enumerate(as_completed(futs)):
                r = f.result()
                if r: out.append(r)
                if (i + 1) % 100 == 0: print(f"  {task}: {i+1}/{len(anchors)}", flush=True)
        cons = sum(1 for r in out if r["consensus"]); agr = sum(1 for r in out if r.get("agrees_db_gold"))
        with open(f"{POOL}/committee_{task}.jsonl", "w") as fo:
            for r in out: fo.write(json.dumps(r) + "\n")
        print(f"COMMITTEE {task}: {len(out)} pooled | teacher-consensus {cons} | agrees-DB-gold {agr}", flush=True)
    print("COMMITTEE_POOL_DONE", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
