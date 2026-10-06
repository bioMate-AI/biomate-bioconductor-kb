#!/usr/bin/env python3
"""STAGE-2 verifiable reward for on-prem 9B task-decomposition (GRPO + inference re-ranker).

Design doc: docs/20260912_onprem_llm/20261006_DECOMP_STAGE2_GRPO_DESIGN.md
Builds on:  docs/20260912_onprem_llm/20261006_DECOMPOSITION_ERROR_ANALYSIS.md (node/edge-F1 is the
            honest metric; parallel/mixed expression is the failing capability)
            docs/20260912_onprem_llm/20261006_DECOMP_DATA_AND_BENCHMARK.md (the held-out gauge)

The reward has two halves, combined into one bounded, deterministic scalar:

  (A) GOLD-GROUNDED  — reuses the benchmark scorer's node-F1 + edge-F1 (score_one in
      evaluation/datasets/decomposition_v2/score.py). This anchors the reward to the right
      sub-tasks and the right dependency edges, so degenerate structures (all-chain / all-parallel /
      over-decomposed) cannot score high by gaming structure alone. Requires the prompt's gold DAG,
      which GRPO training prompts carry (they are drawn from the SAME catalog mine as the SFT rows).

  (B) CATALOG STRUCTURAL VERIFIER (gold-free) — grounds the plan in backend/database/galaxy_ai_tools.db:
        (a) node existence  : every predicted sub_task resolves to a real catalog workflow
        (b) edge type-match : each depends_on edge is a real output_types -> input_types overlap
        (c) parallel roots  : independent roots are genuinely I/O-disjoint (no chaining either way)
        (d) acyclic + well-formed (orders valid, depends_on reference existing earlier orders)
      This supplies a DENSE signal even when gold node-matching is partial, and it is exactly the
      "plausible but non-executable" gap GRPO should close. It is also the re-ranker's selection key
      (no gold needed at serve time).

  reward = w_node*node_f1 + w_edge*edge_f1 + w_struct*struct_validity  (minus a malformed penalty).

Purity / determinism / speed (it is called once per rollout, thousands of times):
  - No network, no LLM, no randomness. Pure function of (pred, gold, catalog_index).
  - The catalog is parsed once into a module-level, path-keyed cache (load_catalog); all per-call
    work is set intersections over small precomputed token/type sets.
  - Reward is bounded in [-malformed_penalty, 1.0].

Usage (dry-run self-proof on the benchmark; no model, no GPU):
    python3 decomp_reward.py --selftest \
        --bench ../datasets/decomposition_v2/decomposition_v2.jsonl \
        --db ../../backend/database/galaxy_ai_tools.db
"""
from __future__ import annotations
import json, re, os, sqlite3, importlib.util, argparse
from functools import lru_cache

HERE = os.path.dirname(os.path.abspath(__file__))
_DEFAULT_SCORER = os.path.join(HERE, "..", "datasets", "decomposition_v2", "score.py")
_DEFAULT_DB = os.path.join(HERE, "..", "..", "backend", "database", "galaxy_ai_tools.db")

_WORD = re.compile(r"[a-z0-9]+")


def _toks(s):
    return set(_WORD.findall(str(s).lower()))


# --------------------------------------------------------------------------------------
# reuse the benchmark scorer for node-F1 / edge-F1 (single source of truth, no re-impl)
# --------------------------------------------------------------------------------------
@lru_cache(maxsize=4)
def _load_scorer(path):
    spec = importlib.util.spec_from_file_location("decompv2_score", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# --------------------------------------------------------------------------------------
# catalog index (parsed once, path-keyed; read-only connection)
# --------------------------------------------------------------------------------------
_CATALOG_CACHE = {}


def _jl(s):
    try:
        v = json.loads(s or "[]")
        return [x for x in v if x] if isinstance(v, list) else []
    except Exception:
        return []


def load_catalog(db_path=_DEFAULT_DB):
    """Return a cached, read-only catalog index keyed by db_path.

    index = {
      "by_norm":  normalized-name -> {name,in,out,domain,tools} (exact resolve),
      "entries":  list of the same dicts + precomputed match-token set (fuzzy resolve),
      "tool_io":  normalized tool_id -> (in_types, out_types) aggregated across workflows,
    }
    """
    db_path = os.path.abspath(db_path)
    if db_path in _CATALOG_CACHE:
        return _CATALOG_CACHE[db_path]
    db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    by_norm, entries, tool_io = {}, [], {}
    for r in db.execute(
            "select name,domain,input_types,output_types,tools_used from workflows "
            "where name is not null"):
        it, ot = frozenset(_jl(r["input_types"])), frozenset(_jl(r["output_types"]))
        tools = _jl(r["tools_used"])
        e = {"name": r["name"], "domain": r["domain"] or "",
             "in": it, "out": ot, "tools": tools,
             "mtok": _toks(r["name"]) | _toks((r["domain"] or "").replace("_", " "))
             | set().union(*[_toks(t) for t in tools]) if tools else _toks(r["name"]) | _toks((r["domain"] or "").replace("_", " "))}
        by_norm[_norm_name(r["name"])] = e
        entries.append(e)
        for t in tools:
            tn = _norm_name(t)
            pin, pout = tool_io.get(tn, (set(), set()))
            tool_io[tn] = (pin | set(it), pout | set(ot))
    db.close()
    idx = {"by_norm": by_norm, "entries": entries,
           "tool_io": {k: (frozenset(a), frozenset(b)) for k, (a, b) in tool_io.items()},
           "n": len(entries)}
    _CATALOG_CACHE[db_path] = idx
    return idx


def _norm_name(s):
    return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()


def resolve_node(sub_task, catalog, thresh=0.34):
    """Resolve a predicted sub_task string to a catalog workflow entry (or None).

    Exact normalized-name match first; else best token-F1 over the entry's match tokens
    (workflow name + domain + tool names). Deterministic (stable argmax tie-break by name)."""
    if not sub_task:
        return None
    nn = _norm_name(sub_task)
    hit = catalog["by_norm"].get(nn)
    if hit is not None:
        return hit
    # tool-id exact match -> synthesize an entry carrying that tool's aggregated I/O
    tn = _norm_name(sub_task)
    if tn in catalog["tool_io"]:
        tin, tout = catalog["tool_io"][tn]
        return {"name": sub_task, "domain": "", "in": tin, "out": tout, "tools": [sub_task]}
    pt = _toks(sub_task)
    if not pt:
        return None
    best, best_s = None, 0.0
    for e in catalog["entries"]:
        gt = e["mtok"]
        inter = len(pt & gt)
        if not inter:
            continue
        p, r = inter / len(pt), inter / len(gt)
        f = 2 * p * r / (p + r)
        if f > best_s or (f == best_s and best is not None and e["name"] < best["name"]):
            best, best_s = e, f
    return best if best_s >= thresh else None


# --------------------------------------------------------------------------------------
# graph helpers (depends_on are `order` ids; translate to list indices)
# --------------------------------------------------------------------------------------
def _order_index(plan):
    idx = {}
    for i, s in enumerate(plan):
        idx[s.get("order", i + 1)] = i
    return idx


def _edges(plan):
    idx = _order_index(plan)
    E = set()
    for i, s in enumerate(plan):
        for d in (s.get("depends_on", []) or []):
            if d in idx:
                E.add((idx[d], i))
    return E


def _is_acyclic(plan):
    idx = _order_index(plan)
    n = len(plan)
    adj = {i: [] for i in range(n)}
    for u, v in _edges(plan):
        adj[u].append(v)
    color = [0] * n  # 0=white 1=gray 2=black

    def dfs(u):
        color[u] = 1
        for w in adj[u]:
            if color[w] == 1:
                return False
            if color[w] == 0 and not dfs(w):
                return False
        color[u] = 2
        return True

    return all(color[i] != 0 or dfs(i) for i in range(n))


def _wellformed(plan):
    """Every depends_on references an existing, earlier order; no self-dep."""
    if not isinstance(plan, list) or not plan:
        return False
    orders = []
    for s in plan:
        if not isinstance(s, dict) or "sub_task" not in s:
            return False
        orders.append(s.get("order"))
    oset = set(orders)
    for s in plan:
        o = s.get("order")
        for d in (s.get("depends_on", []) or []):
            if d == o or d not in oset:
                return False
    return True


# --------------------------------------------------------------------------------------
# catalog structural verifier (gold-free) — returns [0,1] validity + component breakdown
# --------------------------------------------------------------------------------------
def structural_validity(plan, catalog, detail=False):
    comp = {"node_exist": 0.0, "edge_type": 1.0, "parallel_disjoint": 1.0,
            "acyclic": 0.0, "wellformed": 0.0}
    if not isinstance(plan, list) or not plan:
        return (0.0, comp) if detail else 0.0
    resolved = [resolve_node(s.get("sub_task", ""), catalog) if isinstance(s, dict) else None
                for s in plan]
    comp["node_exist"] = sum(1 for r in resolved if r is not None) / len(plan)
    comp["wellformed"] = 1.0 if _wellformed(plan) else 0.0
    comp["acyclic"] = 1.0 if _is_acyclic(plan) else 0.0

    # (b) edge type-match: dep.out ∩ node.in non-empty
    E = _edges(plan)
    if E:
        ok = 0
        for u, v in E:
            ru, rv = resolved[u], resolved[v]
            if ru and rv and (ru["out"] & rv["in"]):
                ok += 1
        comp["edge_type"] = ok / len(E)

    # (c) parallel roots genuinely I/O-disjoint (no chaining in either direction)
    roots = [resolved[i] for i, s in enumerate(plan)
             if isinstance(s, dict) and not (s.get("depends_on", []) or [])]
    roots = [r for r in roots if r is not None]
    if len(roots) >= 2:
        pairs = ok = 0
        for i in range(len(roots)):
            for j in range(i + 1, len(roots)):
                pairs += 1
                a, b = roots[i], roots[j]
                if not (a["out"] & b["in"]) and not (b["out"] & a["in"]):
                    ok += 1
        comp["parallel_disjoint"] = ok / pairs if pairs else 1.0

    val = (0.35 * comp["node_exist"] + 0.25 * comp["edge_type"]
           + 0.20 * comp["parallel_disjoint"] + 0.10 * comp["acyclic"]
           + 0.10 * comp["wellformed"])
    return (round(val, 4), comp) if detail else round(val, 4)


# --------------------------------------------------------------------------------------
# malformed detection
# --------------------------------------------------------------------------------------
def is_malformed(plan):
    if not isinstance(plan, list) or not plan:
        return True
    for s in plan:
        if not isinstance(s, dict) or "sub_task" not in s:
            return True
    return not _wellformed(plan)


# --------------------------------------------------------------------------------------
# the reward
# --------------------------------------------------------------------------------------
DEFAULT_WEIGHTS = {"node": 0.30, "edge": 0.40, "struct": 0.30}
DEFAULT_MALFORMED_PENALTY = 0.5


def decomp_reward(pred, gold_subtasks, catalog, weights=None,
                  malformed_penalty=DEFAULT_MALFORMED_PENALTY, scorer_path=_DEFAULT_SCORER,
                  detail=False):
    """Bounded deterministic reward for one decomposition rollout.

    pred:          parsed model plan (list of {sub_task,order,depends_on}) or raw str (parsed here)
    gold_subtasks: the prompt's gold DAG (list of gold node dicts); enables node/edge-F1.
    catalog:       load_catalog(db_path) index.
    """
    w = dict(DEFAULT_WEIGHTS)
    if weights:
        w.update(weights)
    if isinstance(pred, str):
        pred = _parse_plan(pred)
    if not isinstance(pred, list):
        pred = []

    malformed = is_malformed(pred)
    sc = _load_scorer(scorer_path)
    one = sc.score_one(gold_subtasks, pred if not malformed else [])
    node_f1 = one["node_f1"]
    edge_f1 = one["edge_f1"]
    struct = structural_validity(pred if not malformed else [], catalog)

    base = w["node"] * node_f1 + w["edge"] * edge_f1 + w["struct"] * struct
    reward = base - (malformed_penalty if malformed else 0.0)
    reward = max(-malformed_penalty, min(1.0, reward))
    if detail:
        return {"reward": round(reward, 4), "node_f1": node_f1, "edge_f1": edge_f1,
                "struct_validity": struct, "malformed": malformed,
                "pred_structure": one["pred_structure"], "gold_structure": one["gold_structure"]}
    return round(reward, 4)


def _parse_plan(txt):
    m = re.search(r"\[.*\]", txt or "", re.S)
    if not m:
        return []
    try:
        p = json.loads(m.group())
        return p if isinstance(p, list) else []
    except Exception:
        return []


# --------------------------------------------------------------------------------------
# TRL GRPO adapter: a reward_fn(prompts, completions, **kw) -> list[float]
# --------------------------------------------------------------------------------------
def make_trl_reward_fn(gold_by_prompt, db_path=_DEFAULT_DB, weights=None,
                       malformed_penalty=DEFAULT_MALFORMED_PENALTY, scorer_path=_DEFAULT_SCORER):
    """Build the callable TRL GRPOTrainer expects.

    gold_by_prompt: dict mapping the *prompt text* (or a stable key column) -> gold_subtasks list.
    The GRPO dataset must carry a column that lets us recover the gold for each prompt; the training
    script passes `gold` through as an extra dataset column and TRL forwards it as a kwarg, so we
    prefer the kwarg path and fall back to the prompt-text map."""
    catalog = load_catalog(db_path)

    def reward_fn(prompts=None, completions=None, gold=None, **kw):
        outs = []
        for i, comp in enumerate(completions or []):
            text = comp if isinstance(comp, str) else (
                comp[-1]["content"] if isinstance(comp, list) and comp else "")
            g = None
            if gold is not None:
                g = gold[i] if isinstance(gold, list) else gold
                if isinstance(g, str):
                    try:
                        g = json.loads(g)
                    except Exception:
                        g = None
            if g is None and prompts is not None:
                g = gold_by_prompt.get(prompts[i])
            if not g:
                outs.append(0.0)
                continue
            outs.append(decomp_reward(text, g, catalog, weights, malformed_penalty, scorer_path))
        return outs

    reward_fn.__name__ = "decomp_structural_reward"
    return reward_fn


# --------------------------------------------------------------------------------------
# dry-run self-proof (no model / no GPU): oracle=high, all-chain=low, malformed=penalized
# --------------------------------------------------------------------------------------
def _degrade(gold_subtasks, mode):
    base = [{"sub_task": n["sub_task"], "order": n["order"],
             "depends_on": list(n.get("depends_on", []) or [])} for n in gold_subtasks]
    if mode == "oracle":
        return base
    if mode == "all_chain":  # the SFT "chain everything" failure mode
        return [{"sub_task": n["sub_task"], "order": i + 1,
                 "depends_on": ([i] if i > 0 else [])} for i, n in enumerate(base)]
    if mode == "all_parallel":  # the opposite degeneracy: drop every edge
        return [{"sub_task": n["sub_task"], "order": n["order"], "depends_on": []} for n in base]
    if mode == "over_decomp":  # 2x node inflation with fabricated chain nodes
        out, o = [], 1
        for n in base:
            out.append({"sub_task": n["sub_task"], "order": o, "depends_on": []}); o += 1
            out.append({"sub_task": n["sub_task"] + " step 2", "order": o, "depends_on": [o - 1]}); o += 1
        return out
    if mode == "malformed":
        return {}
    return base


def selftest(bench_path, db_path):
    catalog = load_catalog(db_path)
    rows = [json.loads(l) for l in open(bench_path) if l.strip()]
    by_class = {}
    for r in rows:
        by_class.setdefault(r["structure"], []).append(r)
    modes = ["oracle", "all_chain", "all_parallel", "over_decomp", "malformed"]
    print(f"catalog workflows indexed: {catalog['n']}  |  bench rows: {len(rows)}\n")
    agg = {m: [] for m in modes}
    for struct, rs in sorted(by_class.items()):
        print(f"=== structure class: {struct}  (n={len(rs)}) ===")
        cls = {m: [] for m in modes}
        for r in rs:
            for m in modes:
                d = decomp_reward(_degrade(r["gold_subtasks"], m), r["gold_subtasks"],
                                  catalog, detail=True)
                cls[m].append(d["reward"]); agg[m].append(d["reward"])
        for m in modes:
            v = cls[m]
            print(f"  {m:13s} mean reward = {sum(v)/len(v): .4f}   "
                  f"[min {min(v): .3f}, max {max(v): .3f}]")
        print()
    print("=== overall mean reward by candidate type ===")
    for m in modes:
        v = agg[m]
        print(f"  {m:13s} {sum(v)/len(v): .4f}")
    # assertions that must hold for the reward to be usable as a GRPO signal
    ok = (sum(agg["oracle"]) / len(agg["oracle"]) > 0.85
          and sum(agg["oracle"]) / len(agg["oracle"]) - sum(agg["all_chain"]) / len(agg["all_chain"]) > 0.1
          and sum(agg["malformed"]) / len(agg["malformed"]) < 0.0)
    print("\nSELFTEST", "PASS" if ok else "FAIL",
          "(oracle>0.85, oracle-allchain>0.1, malformed<0)")
    return ok


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--bench", default=os.path.join(HERE, "..", "datasets",
                                                     "decomposition_v2", "decomposition_v2.jsonl"))
    ap.add_argument("--db", default=_DEFAULT_DB)
    a = ap.parse_args()
    if a.selftest:
        raise SystemExit(0 if selftest(a.bench, a.db) else 1)
    ap.print_help()
