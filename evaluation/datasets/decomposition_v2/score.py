#!/usr/bin/env python3
"""Scorer for the decomposition-v2 dependency-graph benchmark.

Replaces the coarse 4-class `structure_accuracy` (evaluation/datasets/public_export/score.py
`_structure_of`) with graph-aware metrics, as called for by
docs/20260912_onprem_llm/20261006_DECOMPOSITION_ERROR_ANALYSIS.md:

  * node_f1   : did the plan recover the right sub-tasks (matched by tool/workflow/domain tokens)?
  * edge_f1   : did the plan recover the right dependency edges (on matched nodes)?
  * structure_accuracy_by_class : 4-class shape match, reported per parallel/sequential/mixed
  * label-free topology diagnostics (WCC-count, parallel-width, partition) carried over from the
    error analysis so regressions in parallel expression stay visible.

A prediction is the model's raw answer: a JSON list of {"sub_task","order","depends_on"}.
Node identity in a tool-free query is hard, so node matching is token-overlap based against the
gold node's {sub_task, domain, tool_id} — a model answering at domain granularity still scores,
while the gold retains the real workflow/tool provenance.

Usage:
    python score.py --gold decomposition_v2.jsonl --pred preds.jsonl
      preds.jsonl rows: {"id": <bench id>, "pred": [ {"sub_task","order","depends_on"}, ... ]}
    or import score_batch(gold_by_id, pred_by_id) -> dict.
"""
import json, re, argparse, math
from collections import Counter, defaultdict

_WORD = re.compile(r"[a-z0-9]+")


def _toks(s):
    return set(_WORD.findall(str(s).lower()))


def _tok_f1(a, b):
    if not a or not b:
        return 0.0
    inter = len(a & b)
    if not inter:
        return 0.0
    p, r = inter / len(a), inter / len(b)
    return 2 * p * r / (p + r)


def wilson(k, n, z=1.96):
    if not n:
        return [None, None]
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    m = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return [round((c - m) / d, 4), round((c + m) / d, 4)]


def _structure_of(plan):
    deps = [len(s.get("depends_on", []) or []) for s in plan if isinstance(s, dict)]
    if not deps:
        return "empty"
    if all(d == 0 for d in deps):
        return "parallel"
    if all(d > 0 for d in deps[1:]):
        return "sequential"
    return "mixed"


def _gold_match_tokens(gn):
    """Strings a pred node may legitimately match a gold node on."""
    t = _toks(gn.get("sub_task", ""))
    t |= _toks(gn.get("domain", "").replace("_", " "))
    t |= _toks(gn.get("tool_id", ""))
    return t


def _match_nodes(pred, gold, thresh=0.3):
    """Greedy bipartite match pred->gold by token-F1; return mapping pred_idx->gold_idx."""
    gtoks = [_gold_match_tokens(g) for g in gold]
    ptoks = [_toks(p.get("sub_task", "")) for p in pred]
    cand = []
    for pi, pt in enumerate(ptoks):
        for gi, gt in enumerate(gtoks):
            s = _tok_f1(pt, gt)
            if s >= thresh:
                cand.append((s, pi, gi))
    cand.sort(reverse=True)
    pused, gused, m = set(), set(), {}
    for s, pi, gi in cand:
        if pi in pused or gi in gused:
            continue
        pused.add(pi); gused.add(gi); m[pi] = gi
    return m


def _order_index(plan):
    """Map a node's declared `order` -> its list index, for resolving depends_on."""
    idx = {}
    for i, s in enumerate(plan):
        o = s.get("order", i + 1)
        idx[o] = i
    return idx


def _edges(plan):
    """Return set of (dep_list_idx, node_list_idx) directed edges via depends_on orders."""
    idx = _order_index(plan)
    E = set()
    for i, s in enumerate(plan):
        for d in (s.get("depends_on", []) or []):
            if d in idx:
                E.add((idx[d], i))
    return E


def _wcc_count(plan):
    n = len(plan)
    if not n:
        return 0
    parent = list(range(n))

    def f(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    for u, v in _edges(plan):
        parent[f(u)] = f(v)
    return len({f(i) for i in range(n)})


def _parallel_width(plan):
    return sum(1 for s in plan if not (s.get("depends_on", []) or []))


def score_one(gold_subtasks, pred):
    if not isinstance(pred, list):
        pred = []
    gstruct = _structure_of(gold_subtasks)
    pstruct = _structure_of(pred)
    m = _match_nodes(pred, gold_subtasks)
    tp = len(m)
    node_p = tp / len(pred) if pred else 0.0
    node_r = tp / len(gold_subtasks) if gold_subtasks else 0.0
    node_f1 = 2 * node_p * node_r / (node_p + node_r) if (node_p + node_r) else 0.0

    # edge-F1 on matched nodes: translate pred edges (pred_idx) -> gold_idx space
    ge = _edges(gold_subtasks)
    pe_raw = _edges(pred)
    pe = set()
    for u, v in pe_raw:
        if u in m and v in m:
            pe.add((m[u], m[v]))
    etp = len(pe & ge)
    edge_p = etp / len(pe) if pe else (1.0 if not ge else 0.0)
    edge_r = etp / len(ge) if ge else (1.0 if not pe else 0.0)
    edge_f1 = 2 * edge_p * edge_r / (edge_p + edge_r) if (edge_p + edge_r) else (
        1.0 if (not ge and not pe) else 0.0)

    return {
        "gold_structure": gstruct, "pred_structure": pstruct,
        "structure_hit": int(pstruct == gstruct),
        "node_f1": round(node_f1, 4), "edge_f1": round(edge_f1, 4),
        "wcc_count_hit": int(_wcc_count(pred) == _wcc_count(gold_subtasks)),
        "parallel_width_hit": int(_parallel_width(pred) == _parallel_width(gold_subtasks)),
        "n_pred_nodes": len(pred), "n_gold_nodes": len(gold_subtasks),
    }


def score_batch(gold_by_id, pred_by_id):
    per = []
    for i, g in gold_by_id.items():
        if i not in pred_by_id:
            continue
        per.append((g.get("structure") or _structure_of(g["gold_subtasks"]),
                    score_one(g["gold_subtasks"], pred_by_id[i])))
    n = len(per)
    if not n:
        return {"n": 0}

    def mean(key):
        return round(sum(r[key] for _, r in per) / n, 4)
    struct_hit = sum(r["structure_hit"] for _, r in per)
    out = {
        "n": n,
        "node_f1": mean("node_f1"),
        "edge_f1": mean("edge_f1"),
        "structure_accuracy": round(struct_hit / n, 4),
        "structure_ci95": wilson(struct_hit, n),
        "wcc_count_match": mean("wcc_count_hit"),
        "parallel_width_match": mean("parallel_width_hit"),
        "by_class": {},
    }
    byc = defaultdict(list)
    for s, r in per:
        byc[s].append(r)
    for s, rs in byc.items():
        k = len(rs)
        hit = sum(r["structure_hit"] for r in rs)
        out["by_class"][s] = {
            "n": k,
            "structure_accuracy": round(hit / k, 4),
            "structure_ci95": wilson(hit, k),
            "node_f1": round(sum(r["node_f1"] for r in rs) / k, 4),
            "edge_f1": round(sum(r["edge_f1"] for r in rs) / k, 4),
            "wcc_count_match": round(sum(r["wcc_count_hit"] for r in rs) / k, 4),
        }
    return out


def _load(path):
    return [json.loads(l) for l in open(path) if l.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gold", default="decomposition_v2.jsonl")
    ap.add_argument("--pred", required=True,
                    help='jsonl of {"id":..., "pred":[{sub_task,order,depends_on}...]}')
    a = ap.parse_args()
    gold = {r["id"]: r for r in _load(a.gold)}
    preds = {}
    for r in _load(a.pred):
        p = r.get("pred")
        if isinstance(p, str):
            try:
                p = json.loads(p)
            except Exception:
                p = []
        preds[r["id"]] = p
    print(json.dumps(score_batch(gold, preds), indent=2))


if __name__ == "__main__":
    main()
