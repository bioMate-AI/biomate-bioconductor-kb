#!/usr/bin/env python3
"""Run the HARD clarification tier (context-aware): the agent may inspect the available context."""
import json, os, re, sys, urllib.request, time, concurrent.futures as cf, importlib.util
HERE = os.path.dirname(os.path.abspath(__file__))
ITEMS = [json.loads(l) for l in open(os.path.join(HERE, "data_hard.jsonl"))]
KEY = os.environ.get("OPENROUTER_API_KEY", "")
_sp = importlib.util.spec_from_file_location("sc", os.path.join(HERE, "score.py")); SC = importlib.util.module_from_spec(_sp); _sp.loader.exec_module(SC)
INSTR = ('Return ONLY JSON: {"action":"interpret"|"clarify","value":"<value if resolvable>","clarify_about":"<what to ask>"}. '
         'You MAY resolve the value from the available context (file headers, manifests, sample sheets, prior turns, cited methods) — '
         'if the context resolves it, INTERPRET and do not ask. CLARIFY only when it is genuinely unresolved, ambiguous, or the request '
         'conflicts with the data/tool. Do not over-ask when the context settles it; do not silently proceed on a real conflict.')
def prompt(it):
    slot = {"branch": "workflow choice", "param": "parameter", "input": "input file", "design": "analysis design"}[it["slot_type"]]
    p = f'User request: "{it["query"]}"'
    if it.get("context"): p += f'\nAvailable context (you may inspect it): {it["context"]}'
    return p + f'\n\nFor the {slot} "{it["gold_target"]}", decide interpret or clarify.\n\n' + INSTR
def ask(model, it):
    body = json.dumps({"model": model, "temperature": 0, "max_tokens": 2500, "messages": [{"role": "user", "content": prompt(it)}]}).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body, headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    for _ in range(3):
        try:
            c = json.loads(urllib.request.urlopen(req, timeout=75).read())["choices"][0]["message"].get("content") or ""
            m = re.search(r"\{.*\}", c, re.S)
            if m:
                try: return json.loads(m.group())
                except Exception: pass
        except Exception: time.sleep(4)
    return {}
def run(model):
    preds = [{"id": it["id"], **ask(model, it)} for it in ITEMS]
    json.dump(preds, open(os.path.join(HERE, "_receipts_%s.json" % model.replace("/","_")), "w"), indent=2)
    s = SC.score(ITEMS, preds)
    print(f"{model:28s} decision={s['decision_acc']} outcome={s['outcome']} over={s['over_clarify']} under={s['under_clarify']}", flush=True)
    return {"model": model, **s}
if __name__ == "__main__":
    models = sys.argv[1].split(",") if len(sys.argv) > 1 else []
    print("HARD clarification tier (v2, context-aware)\n")
    rows = []
    if models and KEY:
        with cf.ThreadPoolExecutor(max_workers=3) as ex: rows = list(ex.map(run, models))
    json.dump(rows, open(os.path.join(HERE, "results_hard.json"), "w"), indent=2)
    print("\nwrote results_hard.json")
