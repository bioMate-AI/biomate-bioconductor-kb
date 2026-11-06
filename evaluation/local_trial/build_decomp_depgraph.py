#!/usr/bin/env python3
"""Build the decomposition-v2 dependency-graph benchmark + SFT training rows from the
catalog (CPU-only, no LLM, no fabricated biology).

Root cause being fixed (docs/20260912_onprem_llm/20261006_DECOMPOSITION_ERROR_ANALYSIS.md):
  0/12,319 existing decomposition training rows carry a `depends_on` field, and 0 carry
  parallel/mixed topology. The target DAG behaviour has 0% density in the SFT target.
  Intra-workflow DAG edges are also essentially absent from the catalog (2/4,210), so the
  real, synthesizable signal is INTER-workflow composition:
    * parallel   = I/O-disjoint distinct domains as independent roots (depends_on=[])
    * sequential = workflow A output_types feed workflow B input_types  (depends_on=[prev])
    * mixed      = per-domain prep->analysis pairs, partition {2,2} (two parallel 2-chains)

Leakage control: workflows are split into a BENCH pool (~20%, hash-based) and a TRAIN pool
(~80%). Benchmark compositions draw ONLY from BENCH workflows; training rows ONLY from TRAIN
workflows. The two workflow-name sets are disjoint and this is verified at the end.

Outputs:
  evaluation/datasets/decomposition_v2/decomposition_v2.jsonl   (benchmark, n>=150, ~1:1:1)
  docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.jsonl   (SFT rows, eval output schema)
  docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.split.json (held-out split proof)
"""
import sqlite3, json, hashlib, collections, random, os, re

REPO = "/Users/kky/biomate-review"
DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
BENCH_OUT = f"{REPO}/evaluation/datasets/decomposition_v2/decomposition_v2.jsonl"
TRAIN_OUT = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.jsonl"
SPLIT_OUT = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.split.json"
random.seed(20261006)

INSTR = ('Decompose this request into an ordered plan of sub-tasks. Reply ONLY a JSON list of '
         '{"sub_task": ..., "order": N, "depends_on": [prerequisite orders]} — independent '
         'sub-tasks have empty depends_on (they can run in parallel).')
SYS = "You are BioMate, an agentic assistant. Decompose the request into an ordered sub-task plan."


def jl(s):
    try:
        v = json.loads(s or "[]")
        return [x for x in v if x] if isinstance(v, list) else []
    except Exception:
        return []


def split_of(name):
    # deterministic, stable held-out split; ~20% BENCH
    return "B" if int(hashlib.md5(name.encode()).hexdigest(), 16) % 100 < 20 else "T"


def primary_tool(w):
    return (w["tools"][0] if w["tools"] else w["name"])


def scrub(text, name):
    """Light scrub: drop the workflow name so the query doesn't leak the node label."""
    t = re.sub(re.escape(name), "", text, flags=re.I)
    t = re.sub(r"\s+", " ", t).strip()
    return t[:360]


def load_pool():
    db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    pool = []
    for r in db.execute(
        "select name,domain,description,input_types,output_types,tools_used,real_exec_status "
        "from workflows where input_types is not null and output_types is not null "
        "and description is not null"):
        it, ot = set(jl(r["input_types"])), set(jl(r["output_types"]))
        if it and ot and r["domain"] and len(r["description"] or "") > 40:
            pool.append(dict(name=r["name"], domain=r["domain"], desc=r["description"],
                             itin=it, ot=ot, tools=jl(r["tools_used"]),
                             exec=r["real_exec_status"]))
    db.close()
    return pool


def node(w, order, depends_on, role):
    return {"sub_task": w["name"], "order": order, "depends_on": depends_on,
            "node_key": f"{w['domain']}:{role}", "tool_id": primary_tool(w),
            "input_types": sorted(w["itin"]), "output_types": sorted(w["ot"]),
            "domain": w["domain"], "role": role}


def disjoint(a, b):
    """No I/O chaining in EITHER direction -> safe to call independent/parallel."""
    return not (a["ot"] & b["itin"]) and not (b["ot"] & a["itin"])


def build_pool_structures(sub, want_par, want_seq, want_mix, seen_signatures):
    """Return (parallel_rows, sequential_rows, mixed_rows) of gold_subtasks-lists built from `sub`."""
    bydom = collections.defaultdict(list)
    for w in sub:
        bydom[w["domain"]].append(w)
    domains = [d for d in bydom if len(bydom[d]) >= 1]

    # within-domain prep->analysis pairs (real output->input edge inside one domain)
    dom_pairs = {}
    for d, ws in bydom.items():
        pairs = []
        for a in ws:
            for b in ws:
                if a["name"] != b["name"] and (a["ot"] & b["itin"]):
                    pairs.append((a, b))
        if pairs:
            dom_pairs[d] = pairs

    # global chainable edges a.ot & b.itin
    def edges_from(w, cands):
        return [b for b in cands if b["name"] != w["name"] and (w["ot"] & b["itin"])]

    par, seq, mix = [], [], []

    # ---- PARALLEL: k distinct, I/O-disjoint domains as roots ----
    tries = 0
    while len(par) < want_par and tries < want_par * 400:
        tries += 1
        k = random.choice([2, 2, 3, 3, 4])
        if len(domains) < k:
            break
        ds = random.sample(domains, k)
        picks = [random.choice(bydom[d]) for d in ds]
        ok = all(disjoint(picks[i], picks[j]) for i in range(k) for j in range(i + 1, k))
        if not ok:
            continue
        sig = ("par", tuple(sorted(p["name"] for p in picks)))
        if sig in seen_signatures:
            continue
        seen_signatures.add(sig)
        nodes = [node(p, i + 1, [], "analysis") for i, p in enumerate(picks)]
        par.append(nodes)

    # ---- SEQUENTIAL: chain of length L via out->in edges ----
    tries = 0
    while len(seq) < want_seq and tries < want_seq * 600:
        tries += 1
        L = random.choice([2, 2, 3, 3, 4])
        start = random.choice(sub)
        chain = [start]
        used = {start["name"]}
        cur = start
        while len(chain) < L:
            nxt = [b for b in edges_from(cur, sub) if b["name"] not in used]
            if not nxt:
                break
            cur = random.choice(nxt)
            chain.append(cur)
            used.add(cur["name"])
        if len(chain) < 2:
            continue
        sig = ("seq", tuple(w["name"] for w in chain))
        if sig in seen_signatures:
            continue
        seen_signatures.add(sig)
        nodes = []
        for i, w in enumerate(chain):
            role = "prep" if i == 0 else ("analysis" if i == len(chain) - 1 else "step")
            nodes.append(node(w, i + 1, ([i] if i > 0 else []), role))
        seq.append(nodes)

    # ---- MIXED: two independent domains, each a prep->analysis pair -> partition {2,2} ----
    pair_domains = list(dom_pairs)
    tries = 0
    while len(mix) < want_mix and tries < want_mix * 800 and len(pair_domains) >= 2:
        tries += 1
        d1, d2 = random.sample(pair_domains, 2)
        a1, b1 = random.choice(dom_pairs[d1])
        a2, b2 = random.choice(dom_pairs[d2])
        # the two domain pipelines must be mutually independent (no cross chaining)
        grp1, grp2 = (a1, b1), (a2, b2)
        if any(not disjoint(x, y) for x in grp1 for y in grp2):
            continue
        names = (a1["name"], b1["name"], a2["name"], b2["name"])
        if len(set(names)) < 4:
            continue
        sig = ("mix", tuple(sorted(names)))
        if sig in seen_signatures:
            continue
        seen_signatures.add(sig)
        nodes = [node(a1, 1, [], "prep"), node(b1, 2, [1], "analysis"),
                 node(a2, 3, [], "prep"), node(b2, 4, [3], "analysis")]
        mix.append(nodes)

    return par, seq, mix


def make_query(structure, nodes):
    """Build a realistic, tool-name-free query from the REAL workflow descriptions."""
    # group nodes into pipelines by weakly-connected components (follow depends_on)
    order2node = {n["order"]: n for n in nodes}
    parent = {n["order"]: n["order"] for n in nodes}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        parent[find(a)] = find(b)

    # we need the source workflow descriptions; stashed on node under _desc
    for n in nodes:
        for d in n["depends_on"]:
            union(n["order"], d)
    comps = collections.defaultdict(list)
    for n in nodes:
        comps[find(n["order"])].append(n)
    comp_list = list(comps.values())

    def desc_of(n):
        return scrub(n["_desc"], n["sub_task"])

    parts = []
    if structure == "parallel":
        head = (f"I have {len(nodes)} independent analyses to run on separate datasets; please "
                f"treat them as separate jobs that can proceed concurrently:")
        for i, n in enumerate(nodes, 1):
            parts.append(f"{i}) {n['domain'].replace('_',' ').title()} goal — {desc_of(n)}")
        return head + "\n\n" + "\n\n".join(parts)
    if structure == "sequential":
        head = ("I need a single end-to-end pipeline where each stage consumes the previous "
                "stage's output; please run them in order:")
        for i, n in enumerate(sorted(nodes, key=lambda x: x["order"]), 1):
            io = f"(produces {', '.join(n['output_types'][:3])})"
            parts.append(f"Step {i}: {desc_of(n)} {io}")
        return head + "\n\n" + "\n\n".join(parts)
    # mixed
    head = (f"I have {len(comp_list)} independent projects; within each project the steps are "
            f"sequential, but the projects are unrelated and can run in parallel:")
    for pi, comp in enumerate(comp_list, 1):
        comp = sorted(comp, key=lambda x: x["order"])
        sub = [f"first {desc_of(comp[0])}"]
        for n in comp[1:]:
            sub.append(f"then {desc_of(n)}")
        parts.append(f"Project {pi} ({comp[0]['domain'].replace('_',' ').title()}): " + "; ".join(sub))
    return head + "\n\n" + "\n\n".join(parts)


def attach_desc(nodes, by_name):
    for n in nodes:
        n["_desc"] = by_name[n["sub_task"]]["desc"]


def strip_internal(nodes):
    return [{k: v for k, v in n.items() if not k.startswith("_")} for n in nodes]


def main():
    pool = load_pool()
    by_name = {w["name"]: w for w in pool}
    bench = [w for w in pool if split_of(w["name"]) == "B"]
    train = [w for w in pool if split_of(w["name"]) == "T"]
    print(f"pool={len(pool)}  bench_pool={len(bench)}  train_pool={len(train)}")

    seen = set()
    # ---- BENCHMARK (BENCH pool): ~55 per class -> n~165 ----
    bpar, bseq, bmix = build_pool_structures(bench, 55, 55, 55, seen)
    bench_rows = []
    for struct, group in (("parallel", bpar), ("sequential", bseq), ("mixed", bmix)):
        for nodes in group:
            attach_desc(nodes, by_name)
            q = make_query(struct, nodes)
            clean = strip_internal(nodes)
            rid = f"decv2_{struct}_{len(bench_rows)}"
            bench_rows.append({"id": rid, "query": q, "structure": struct,
                               "gold_subtasks": clean, "instr": INSTR,
                               "source": "catalog_inter_workflow_composition"})
    random.shuffle(bench_rows)

    # ---- TRAINING (TRAIN pool): over-represent parallel+mixed ----
    tpar, tseq, tmix = build_pool_structures(train, 1700, 900, 1700, seen)
    train_rows = []
    for struct, group in (("parallel", tpar), ("sequential", tseq), ("mixed", tmix)):
        for nodes in group:
            attach_desc(nodes, by_name)
            q = make_query(struct, nodes)
            clean = strip_internal(nodes)
            # assistant target = the eval OUTPUT SCHEMA exactly: list of {sub_task,order,depends_on}
            target = [{"sub_task": n["sub_task"], "order": n["order"],
                       "depends_on": n["depends_on"]} for n in clean]
            train_rows.append({
                "messages": [
                    {"role": "system", "content": SYS},
                    {"role": "user", "content": f"{q}\n\n{INSTR}"},
                    {"role": "assistant", "content": json.dumps(target)},
                ],
                "task": "task_decomposition",
                "source": "catalog_depgraph_synth",
                "structure": struct,
            })
    random.shuffle(train_rows)

    # ---- write ----
    os.makedirs(os.path.dirname(BENCH_OUT), exist_ok=True)
    with open(BENCH_OUT, "w") as f:
        for r in bench_rows:
            f.write(json.dumps(r) + "\n")
    with open(TRAIN_OUT, "w") as f:
        for r in train_rows:
            f.write(json.dumps(r) + "\n")

    # ---- leakage proof ----
    def wf_names(rows, is_train):
        s = set()
        for r in rows:
            if is_train:
                tgt = json.loads(r["messages"][2]["content"])
                for n in tgt:
                    s.add(n["sub_task"])
            else:
                for n in r["gold_subtasks"]:
                    s.add(n["sub_task"])
        return s

    bench_wf = wf_names(bench_rows, False)
    train_wf = wf_names(train_rows, True)
    overlap = bench_wf & train_wf
    split_proof = {
        "method": "md5(name)%100<20 -> BENCH else TRAIN (deterministic, stable)",
        "bench_pool_workflows": len(bench),
        "train_pool_workflows": len(train),
        "bench_workflows_used": len(bench_wf),
        "train_workflows_used": len(train_wf),
        "workflow_name_overlap": len(overlap),
        "overlap_examples": sorted(overlap)[:20],
        "bench_rows": len(bench_rows),
        "train_rows": len(train_rows),
        "bench_balance": dict(collections.Counter(r["structure"] for r in bench_rows)),
        "train_balance": dict(collections.Counter(r["structure"] for r in train_rows)),
    }
    with open(SPLIT_OUT, "w") as f:
        json.dump(split_proof, f, indent=2)

    print("BENCH", split_proof["bench_balance"], "n=", len(bench_rows))
    print("TRAIN", split_proof["train_balance"], "n=", len(train_rows))
    print("workflow_name_overlap (must be 0):", len(overlap))


if __name__ == "__main__":
    main()
