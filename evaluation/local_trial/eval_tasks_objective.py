"""Objective per-task eval (NO LLM judge) across ALL tasks. Graders:
 accept_set (routing), mcqa (QA exact-match), content_overlap (fraction of gold's salient tokens in output),
 clarify_ask (did it ask a question). Per-task, thinking stripped. Usage:
   python eval_tasks_objective.py --base <p> --adapter <p> --model <n> --evalfile objective_eval.jsonl --out o.json
"""
import argparse, json, os, re, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_removal import direct_load, call_direct_batch
STOP = set("the a an of to and or for with is are was on in at by from this that these those into as be it its their his her our your you we they i can could should would will may might use used using given provide provides which what when where how why does do".split())
def norm(s): return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()
def ans_of(o): return o.rsplit("</think>", 1)[1].strip() if "</think>" in o else o.strip()
def first_letter(o):
    m = re.search(r"\b([ABCDE])\b", ans_of(o).upper()); return m.group(1) if m else ""
def salient(gold):
    bt = re.findall(r"`([^`]+)`", gold); nums = re.findall(r"\d+\.?\d+|\b\d{2,}\b", gold)
    words = [w for w in norm(gold).split() if len(w) > 3 and w not in STOP]
    terms = set(norm(x) for x in bt if x) | set(nums) | set(words[:25])
    return {t for t in terms if t}
def score(item, out):
    g = item.get("grader"); a = ans_of(out); na = norm(a)
    if g == "accept_set": return float(any(norm(x) in na for x in item["accept"]))
    if g == "mcqa": return float(first_letter(out) == str(item["gold"]).strip().upper())
    if g == "clarify_ask": return float("?" in a)
    S = salient(item.get("gold", ""))
    return round(sum(1 for t in S if t in na) / len(S), 4) if S else 0.0
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True); ap.add_argument("--adapter", default="")
    ap.add_argument("--model", default="m"); ap.add_argument("--evalfile", required=True); ap.add_argument("--out", required=True)
    a = ap.parse_args(); os.environ["EVAL_DTYPE"] = "bf16"
    direct_load(a.base, a.adapter or None)
    rows = [json.loads(l) for l in open(a.evalfile)]
    BS = int(os.environ.get("GEN_BATCH", "24")); outs = []
    for i in range(0, len(rows), BS):
        outs.extend(call_direct_batch([r["prompt"] for r in rows[i:i + BS]], 320))
        print(f"[obj] {min(i+BS,len(rows))}/{len(rows)}", flush=True)
    agg = collections.defaultdict(lambda: [0.0, 0])
    for r, o in zip(rows, outs):
        agg[r["task"]][0] += score(r, o); agg[r["task"]][1] += 1
    per = {t: {"score": round(v[0] / max(v[1], 1), 3), "n": v[1]} for t, v in agg.items()}
    macro = round(sum(p["score"] for p in per.values()) / max(len(per), 1), 3)
    json.dump({"model": a.model, "macro": macro, "per_task": per}, open(a.out, "w"), indent=2)
    print("OBJ EVAL:", json.dumps({"model": a.model, "macro": macro, "per_task": per}))
if __name__ == "__main__":
    raise SystemExit(main())
