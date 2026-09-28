"""Objective 17-task eval via a vLLM server (continuous batching, high concurrency). No LLM judge.
Runs multiple arms (e.g. base + sft_v4 LoRA served by one vLLM). Graders match eval_tasks_objective.
Usage: python eval_vllm.py --models base,sft_v4 --evalfile objective_eval.jsonl --out result.json
"""
import argparse, json, re, time, collections, urllib.request
from concurrent.futures import ThreadPoolExecutor
URL = "http://localhost:8000/v1/chat/completions"
STOP = set("the a an of to and or for with is are was on in at by from this that these those into as be it its their his her our your you we they i can could should would will may might use used using given provide provides which what when where how why does do".split())
def norm(s): return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()
def ans_of(o): return o.rsplit("</think>", 1)[1].strip() if "</think>" in o else o.strip()
def first_letter(o):
    m = re.search(r"\b([ABCDE])\b", ans_of(o).upper()); return m.group(1) if m else ""
def salient(g):
    bt = re.findall(r"`([^`]+)`", g); nums = re.findall(r"\d+\.?\d+|\b\d{2,}\b", g)
    w = [x for x in norm(g).split() if len(x) > 3 and x not in STOP]
    return {t for t in (set(norm(x) for x in bt if x) | set(nums) | set(w[:25])) if t}
def score(it, out):
    grd = it.get("grader"); a = ans_of(out); na = norm(a)
    if grd == "accept_set": return float(any(norm(x) in na for x in it["accept"]))
    if grd == "mcqa": return float(first_letter(out) == str(it["gold"]).strip().upper())
    if grd == "clarify_ask": return float("?" in a)
    S = salient(it.get("gold", "")); return sum(1 for t in S if t in na) / len(S) if S else 0.0
def gen(model, prompt, mx=320):
    body = json.dumps({"model": model, "messages": [{"role": "user", "content": prompt}], "max_tokens": mx, "temperature": 0}).encode()
    for a in range(3):
        try:
            d = json.load(urllib.request.urlopen(urllib.request.Request(URL, body, {"Content-Type": "application/json"}), timeout=180))
            return d["choices"][0]["message"]["content"]
        except Exception: time.sleep(2)
    return ""
def run_arm(model, rows, workers=128):
    with ThreadPoolExecutor(max_workers=workers) as ex:
        outs = list(ex.map(lambda r: gen(model, r["prompt"]), rows))
    agg = collections.defaultdict(lambda: [0.0, 0])
    for r, o in zip(rows, outs): agg[r["task"]][0] += score(r, o); agg[r["task"]][1] += 1
    per = {t: {"score": round(v[0] / max(v[1], 1), 3), "n": v[1]} for t, v in agg.items()}
    return {"macro": round(sum(p["score"] for p in per.values()) / max(len(per), 1), 3), "per_task": per}
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", required=True); ap.add_argument("--evalfile", required=True); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rows = [json.loads(l) for l in open(a.evalfile)]
    res = {}
    for m in a.models.split(","):
        t0 = time.time(); res[m] = run_arm(m, rows); res[m]["secs"] = round(time.time() - t0)
        print(f"ARM {m}: macro={res[m]['macro']} in {res[m]['secs']}s", flush=True)
    # combined table
    tasks = sorted(set().union(*[set(res[m]["per_task"]) for m in res]))
    tbl = {t: {m: res[m]["per_task"].get(t, {}).get("score") for m in res} for t in tasks}
    out = {"macro": {m: res[m]["macro"] for m in res}, "per_task": tbl}
    json.dump(out, open(a.out, "w"), indent=2); print("VLLM_OBJ:", json.dumps(out))
if __name__ == "__main__":
    raise SystemExit(main())
