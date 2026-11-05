#!/usr/bin/env python3
"""Score decomposition-benchmark predictions against the held-out gold DAGs.

Gold nodes are catalog workflow names ("nf-core/sarek"); predictions are task descriptions
("germline variant calling on WES …"), so string matching would score every model ~0. An LLM
judge (one call per prediction) aligns predicted nodes to gold nodes ONE-TO-ONE from the request
text and the two node lists only — it is not shown edges or which model produced them. Edges and
structure are then scored deterministically from that alignment:
  node P/R/F1  — aligned nodes / predicted, / gold
  edge F1      — gold edges (dep → step) vs predicted edges mapped through the alignment
  structure    — single / parallel / sequential / mixed of the predicted DAG vs the gold label
Cost per decomposition uses the recorded token usage × OpenRouter prices.

Usage: scripts/routing_eval/decomp_judge.py <bench.jsonl> <judged.jsonl> [--judge anthropic/claude-sonnet-5.5]
Prints the per-model table (accuracy, $/decomposition, latency, failures).
"""
import argparse
import json
import os
import statistics
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
GOLD = os.path.join(ROOT, "evaluation", "datasets", "decomposition_real", "decomposition_real.jsonl")
KEY = open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()

PROMPT = """You align two decompositions of the same bioinformatics request.

REQUEST:
{query}

GOLD steps (reference workflows):
{gold}

PREDICTED steps (written by a planner, as task descriptions):
{pred}

Match each predicted step to the ONE gold step that performs the same analysis (same purpose and
data), or to null if none does. One-to-one: a gold step may be matched by at most one predicted
step. Judge by what the step does, not by wording.
Reply with ONLY a JSON object: {{"mapping": {{"<predicted number>": <gold number or null>, ...}}}}"""


def chat(model, prompt, max_tokens=600):
    body = json.dumps({"model": model, "messages": [{"role": "user", "content": prompt}],
                       "max_tokens": max_tokens, "temperature": 0}).encode()
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=body, method="POST",
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                j = json.loads(r.read())
            return j["choices"][0]["message"]["content"] or "", j.get("usage") or {}
        except Exception:  # noqa: BLE001 — transient OpenRouter errors are retried
            time.sleep(3 * (attempt + 1))
    return "", {}


def parse_mapping(text):
    s = text[text.find("{"): text.rfind("}") + 1] if "{" in text else "{}"
    try:
        return {int(k): (int(v) if v is not None else None) for k, v in json.loads(s).get("mapping", {}).items()}
    except Exception:  # noqa: BLE001
        return {}


def structure(nodes):
    n = len(nodes)
    if n <= 1:
        return "single"
    edges = sum(len(x["depends_on"]) for x in nodes)
    if edges == 0:
        return "parallel"
    roots = sum(1 for x in nodes if not x["depends_on"])
    chain = roots == 1 and all(len(x["depends_on"]) <= 1 for x in nodes) and edges == n - 1
    return "sequential" if chain else "mixed"


def f1(p, r):
    return 0.0 if p + r == 0 else 2 * p * r / (p + r)


def score(row, gold, mapping):
    g = gold["gold_subtasks"]
    pred = row["nodes"]
    one2one, used = {}, set()
    for pi, gi in sorted(mapping.items()):
        if gi and 1 <= gi <= len(g) and gi not in used and 1 <= pi <= len(pred):
            one2one[pi] = gi
            used.add(gi)
    np_, ng = len(pred), len(g)
    node_p = len(one2one) / np_ if np_ else 0.0
    node_r = len(one2one) / ng if ng else 0.0
    gold_e = {(d, x["order"]) for x in g for d in x["depends_on"]}
    pred_e = {(one2one[d], one2one[x["order"]]) for x in pred for d in x["depends_on"]
              if d in one2one and x["order"] in one2one}
    raw_pred_e = sum(len(x["depends_on"]) for x in pred)
    ep = len(pred_e & gold_e) / raw_pred_e if raw_pred_e else (1.0 if not gold_e else 0.0)
    er = len(pred_e & gold_e) / len(gold_e) if gold_e else (1.0 if raw_pred_e == 0 else 0.0)
    return {"node_f1": f1(node_p, node_r), "edge_f1": f1(ep, er),
            "structure_ok": structure(pred) == gold["structure"], "n_pred": np_, "n_gold": ng}


def prices():
    with urllib.request.urlopen("https://openrouter.ai/api/v1/models", timeout=60) as r:
        return {m["id"]: (float(m["pricing"]["prompt"]), float(m["pricing"]["completion"]))
                for m in json.loads(r.read())["data"]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bench")
    ap.add_argument("judged")
    ap.add_argument("--judge", default="anthropic/claude-sonnet-5.5")
    a = ap.parse_args()
    gold = {json.loads(l)["id"]: json.loads(l) for l in open(GOLD) if l.strip()}
    rows = [json.loads(l) for l in open(a.bench) if l.strip()]
    rows = list({(r["model"], r["id"]): r for r in rows}.values())  # last attempt wins
    done = {}
    if os.path.exists(a.judged):
        for l in open(a.judged):
            if l.strip():
                j = json.loads(l)
                done[(j["model"], j["id"])] = j

    def judge(r):
        key = (r["model"], r["id"])
        if key in done:
            return done[key]
        g = gold[r["id"]]
        if not r.get("usage"):  # analyzeIntent fell back to a heuristic: not this model's answer
            r = {**r, "error": r["error"] or "no model response"}
        if r["error"] or not r["nodes"]:
            mapping, ju = {}, {}
        else:
            gtxt = "\n".join(f'{x["order"]}. {x["sub_task"]}' + (f' (tool {x["tool_id"]})' if x.get("tool_id") else "")
                             for x in g["gold_subtasks"])
            ptxt = "\n".join(f'{x["order"]}. {x["text"]}' for x in r["nodes"])
            out, ju = chat(a.judge, PROMPT.format(query=g["query"][:1500], gold=gtxt, pred=ptxt))
            mapping = parse_mapping(out)
        res = {"model": r["model"], "id": r["id"], "error": r["error"], "secs": r["secs"], "usage": r.get("usage"),
               "mapping": {str(k): v for k, v in mapping.items()}, "judge_usage": ju, **score(r, g, mapping)}
        with open(a.judged, "a") as f:
            f.write(json.dumps(res) + "\n")
        return res

    with ThreadPoolExecutor(8) as ex:
        judged = list(ex.map(judge, rows))

    pr = prices()
    by = {}
    for j in judged:
        by.setdefault(j["model"], []).append(j)
    table = []
    for m, js in by.items():
        ok = [j for j in js if not j["error"] and j["n_pred"]]
        pin, pout = pr.get(m, (0, 0))
        costs = [((j.get("usage") or {}).get("input_tokens", 0) * pin + (j.get("usage") or {}).get("output_tokens", 0) * pout) for j in ok]
        table.append({
            "model": m, "n": len(js), "failed": len(js) - len(ok),
            "node_f1": statistics.mean(j["node_f1"] for j in js),
            "edge_f1": statistics.mean(j["edge_f1"] for j in js),
            "structure": statistics.mean(1.0 if j["structure_ok"] else 0.0 for j in js),
            "usd_per_call": statistics.mean(costs) if costs else 0.0,
            "median_secs": statistics.median([j["secs"] for j in ok]) if ok else 0.0,
        })
    table.sort(key=lambda t: (-(t["edge_f1"] + t["node_f1"] + t["structure"]), t["usd_per_call"]))
    print(f'{"model":32s} {"n":>3} {"fail":>4} {"node_F1":>7} {"edge_F1":>7} {"struct":>6} {"$/call":>8} {"med_s":>6}')
    for t in table:
        print(f'{t["model"]:32s} {t["n"]:3d} {t["failed"]:4d} {t["node_f1"]:7.3f} {t["edge_f1"]:7.3f} {t["structure"]:6.2f} {t["usd_per_call"]:8.4f} {t["median_secs"]:6.1f}')
    json.dump(table, open(a.judged.replace(".jsonl", "_table.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
