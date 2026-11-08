#!/usr/bin/env python3
"""Build REAL (non-synthetic) task-decomposition training + held-out validation data.

Sources (topology NOT designed by our synthetic constructor build_decomp_depgraph.py):
  A) nf-core / Nextflow subworkflow channel graphs  (backend/biomni_workflows + backend/nf-core-*)
       node = process invocation, edge = channel out->in wiring (versions plumbing excluded)
  B) workflow_chains DB table (curated, execution-grounded) — real intents + explicit from/to edges
  C) GTN tutorials — expert ordered multi-tool pipelines (sequential)

EXCLUDED (documented): Biomni/biomni_nextflow — degenerate 2-node (tool+OUTPUT) and
  numpy-primitive STEP_n__NP_* micro-step chains; not real biological tool DAGs.

Outputs:
  docs/20260912_onprem_llm/data_pool_v2/decomp_real.jsonl              (SFT train rows, decomp_depgraph schema)
  evaluation/datasets/decomposition_real/decomposition_real.jsonl     (held-out val, decomposition_v2 schema)
  evaluation/datasets/decomposition_real/score.py                     (reused v2 scorer)
  evaluation/datasets/decomposition_real/README.md
  docs/20260912_onprem_llm/data_pool_v2/decomp_real.split.json        (disjointness proof)
  docs/20260912_onprem_llm/data_pool_v2/decomp_real.stats.json        (real-vs-synthetic distribution)
Leakage control: split per SOURCE-UNIT (file / chain name / tutorial id); train ∩ val = ∅.
"""
import sqlite3, json, re, glob, hashlib, os, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nf_parse as P

REPO = "/Users/kky/biomate-review"
DB = f"{REPO}/backend/database/galaxy_ai_tools.db"
GTN = f"{REPO}/docs/20260912_onprem_llm/midtrain_corpus/gtn_corpus.jsonl"
SYNTH = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2/decomp_depgraph.jsonl"

OUT_TRAIN = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2/decomp_real.jsonl"
OUT_SPLIT = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2/decomp_real.split.json"
OUT_STATS = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2/decomp_real.stats.json"
VAL_DIR = f"{REPO}/evaluation/datasets/decomposition_real"
OUT_VAL = f"{VAL_DIR}/decomposition_real.jsonl"

INSTR = ('Decompose this request into an ordered plan of sub-tasks. Reply ONLY a JSON list of '
         '{"sub_task": ..., "order": N, "depends_on": [prerequisite orders]} — independent '
         'sub-tasks have empty depends_on (they can run in parallel).')
SYS = "You are BioMate, an agentic assistant. Decompose the request into an ordered sub-task plan."
DEGEN = {'OUTPUT', 'PUBLISH', 'COLLECT', 'DONE', 'FINISH', 'MULTIQC_REPORT'}


def h(name):
    return int(hashlib.md5(name.encode()).hexdigest(), 16)


def split_of(unit_id):
    # ~25% held-out validation, deterministic & stable
    return "VAL" if h(unit_id) % 100 < 25 else "TRAIN"


def stratified_split(rows):
    """Deterministic per-(provenance,structure) holdout. Rare branching classes
    (mixed/parallel) get a higher holdout rate so the OOD eval has statistical power;
    sequential gets the standard rate. Still a hard partition (unit in exactly one side)."""
    buckets = collections.defaultdict(list)
    for r in rows:
        buckets[(r["provenance"], r["structure"])].append(r)
    train, val = [], []
    import math
    for key, bucket in buckets.items():
        bucket = sorted(bucket, key=lambda r: h(r["unit"]))
        frac = 0.40 if key[1] in ("mixed", "parallel") else 0.22
        k = max(1, round(frac * len(bucket))) if len(bucket) >= 2 else 0
        val.extend(bucket[:k])
        train.extend(bucket[k:])
    return train, val


def structure_of(nodes_in_order, deps):
    dc = [len(deps[n]) for n in nodes_in_order]
    if all(c == 0 for c in dc):
        return "parallel"
    if all(c > 0 for c in dc[1:]):
        return "sequential"
    return "mixed"


def roles(nodes, deps):
    """root/prep/step/analysis by position in the DAG."""
    is_dep = set()
    for n in nodes:
        is_dep |= deps[n]
    r = {}
    for n in nodes:
        terminal = n not in is_dep
        rootish = not deps[n]
        if rootish and terminal:
            r[n] = "analysis"          # isolated parallel leaf
        elif rootish:
            r[n] = "prep"
        elif terminal:
            r[n] = "analysis"
        else:
            r[n] = "step"
    return r


def scrub(text, tokens):
    t = text or ""
    for tok in sorted(tokens, key=len, reverse=True):
        if len(tok) < 3:
            continue
        t = re.sub(re.escape(tok), "", t, flags=re.I)
        t = re.sub(re.escape(tok.replace('_', ' ')), "", t, flags=re.I)
    t = re.sub(r"\s+", " ", t).strip()
    return t[:600]


def humanize(proc):
    return re.sub(r"_+", " ", proc).title()


# ---------------------------------------------------------------------------
# catalog descriptions for nf-core filename join
# ---------------------------------------------------------------------------
def load_catalog_desc():
    db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    m = {}
    for name, fn, desc in db.execute(
            "select name, filename, description from workflows where filename is not null"):
        if fn:
            m[fn] = (name, desc or "")
    db.close()
    return m


CAT = load_catalog_desc()


def catalog_key(path):
    # path .../nextflow_nfcore/subworkflows/<d>/<name>/main.nf -> filename stored as
    # 'nextflow_nfcore/subworkflows/<d>/<name>/main.nf'
    for anchor in ("nextflow_nfcore/", "nf-core-workflows/", "nf-core-modules/"):
        if anchor in path:
            return path[path.index(anchor):]
    return None


# ---------------------------------------------------------------------------
# A) nf-core subworkflow DAGs
# ---------------------------------------------------------------------------
def build_nfcore():
    rows = []
    files = (glob.glob(f"{REPO}/backend/biomni_workflows/**/*.nf", recursive=True)
             + glob.glob(f"{REPO}/backend/nf-core-workflows/**/*.nf", recursive=True)
             + glob.glob(f"{REPO}/backend/nf-core-modules/**/*.nf", recursive=True))
    for f in files:
        try:
            txt = open(f).read()
        except Exception:
            continue
        d = P.parse_dag(txt)
        if not d:
            continue
        nodes = [n for n in d['nodes'] if n.upper() not in DEGEN and not re.match(r'STEP_\d+__', n)]
        if len(nodes) < 2:
            continue
        keep = set(nodes)
        deps = {n: {x for x in d['deps'][n] if x in keep} for n in nodes}
        # domain = parent-of-parent dir name under subworkflows/workflows
        parts = f.split('/')
        domain = parts[-3] if len(parts) >= 3 else "general"
        oi = {n: i + 1 for i, n in enumerate(nodes)}
        rl = roles(nodes, deps)
        procmeta = d['procs']
        gold = []
        for n in nodes:
            pm = procmeta.get(n, {})
            gold.append({
                "sub_task": humanize(n), "order": oi[n],
                "depends_on": sorted(oi[x] for x in deps[n]),
                "node_key": f"{domain}:{rl[n]}", "tool_id": n,
                "input_types": sorted(set(pm.get('in', [])))[:8],
                "output_types": sorted(set(pm.get('out', [])))[:8],
                "domain": domain, "role": rl[n],
            })
        struct = structure_of(nodes, deps)
        # query from the REAL catalog description. Scrub ONLY exact tool-id strings and
        # their humanized phrase (not generic word fragments) so the science goal survives.
        # If what's left is not a real tool-free description, DROP the row (no fabrication).
        ck = catalog_key(f)
        cname, cdesc = CAT.get(ck, (None, ""))
        toks = set()
        for n in nodes:
            toks.add(n); toks.add(humanize(n))
        if cname:
            toks.add(cname)
        # strip the leading "<domain>/<name> " provenance prefix catalog descriptions carry
        cdesc = re.sub(r'^\s*[\w\-]+/[\w\-/]+\s+', '', cdesc)
        query = scrub(cdesc, toks)
        unit = "nfcore:" + (ck or f.split('backend/')[-1])
        rows.append(dict(unit=unit, provenance="nfcore_subworkflow", domain=domain,
                         structure=struct, gold=gold, query=query))
    return rows


# ---------------------------------------------------------------------------
# B) workflow_chains DAGs
# ---------------------------------------------------------------------------
def build_chains():
    db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    rows = []
    for r in db.execute("select name,display_name,domain,description,steps,connections,required_inputs,"
                        "expected_outputs,example_queries,source from workflow_chains"):
        steps = json.loads(r['steps'] or "[]")
        if len(steps) < 2:
            continue
        conn = json.loads(r['connections'] or "[]")
        steps = sorted(steps, key=lambda s: s['order'])
        orders = [s['order'] for s in steps]
        deps = {o: set() for o in orders}
        inputs_to = collections.defaultdict(set)
        outputs_from = collections.defaultdict(set)
        for c in conn:
            fs, ts = c.get('from_step'), c.get('to_step')
            if ts in deps and fs in deps and fs != ts:
                deps[ts].add(fs)
                inputs_to[ts].add(c.get('to_input', ''))
                outputs_from[fs].add(c.get('from_output', ''))
        # normalize order -> 1..n index
        oi = {o: i + 1 for i, o in enumerate(orders)}
        nodes = [s['workflow_name'] for s in steps]
        dmap = {s['workflow_name']: deps[s['order']] for s in steps}  # by name? collisions possible
        # work in order space to avoid name collisions
        depidx = {oi[s['order']]: sorted(oi[x] for x in deps[s['order']]) for s in steps}
        is_dep = set()
        for s in steps:
            is_dep |= deps[s['order']]
        gold = []
        for s in steps:
            o = s['order']
            terminal = o not in is_dep
            rootish = not deps[o]
            role = s.get('role') or ("prep" if rootish and not terminal else
                                     "analysis" if terminal else "step")
            gold.append({
                "sub_task": s['workflow_name'], "order": oi[o],
                "depends_on": depidx[oi[o]],
                "node_key": f"{r['domain']}:{role}", "tool_id": s['workflow_name'],
                "input_types": sorted(x for x in inputs_to[o] if x)[:8],
                "output_types": sorted(x for x in outputs_from[o] if x)[:8],
                "domain": r['domain'], "role": role,
            })
        dc = [len(g['depends_on']) for g in sorted(gold, key=lambda x: x['order'])]
        struct = 'parallel' if all(c == 0 for c in dc) else (
            'sequential' if all(c > 0 for c in dc[1:]) else 'mixed')
        eqs = json.loads(r['example_queries'] or "[]")
        # scrub ONLY exact workflow-name strings (and their '/'->' ' form), not word fragments,
        # so the real user intent survives. Chain example_queries are tool-free by design.
        toks = set()
        for s in steps:
            wn = s['workflow_name']
            toks.add(wn); toks.add(wn.replace('/', ' ').replace('_', ' '))
        # prefer a real user intent; fall back to the chain's own display_name + description
        raw = eqs[0] if eqs else ""
        fallback = f"{r['display_name']}. {r['description'] or ''}"
        query = scrub(raw, toks)
        if len([w for w in re.findall(r'[A-Za-z]{3,}', query)]) < 6:
            query = scrub(fallback, toks)
        rows.append(dict(unit="chain:" + r['name'], provenance="workflow_chain",
                         domain=r['domain'], structure=struct, gold=gold, query=query))
    db.close()
    return rows


# ---------------------------------------------------------------------------
# C) GTN tutorials -> sequential tool chains
# ---------------------------------------------------------------------------
TOOLPAT = re.compile(r'{%\s*tool\s*\[([^\]]+)\]\(([^)]+)\)\s*%}')


def build_gtn():
    rows = []
    for line in open(GTN):
        try:
            rr = json.loads(line)
        except Exception:
            continue
        rid = rr.get('id', '')
        if not rid.endswith('tutorial.md'):
            continue
        txt = rr.get('text') or ''
        tools = TOOLPAT.findall(txt)
        # ordered, de-duplicated-consecutive tool labels
        seq = []
        for label, tid in tools:
            label = label.strip()
            tid = tid.strip()
            if not label:
                continue
            if not seq or seq[-1][0] != label:
                seq.append((label, tid))
        # collapse to distinct tools preserving first-seen order, require >=2 distinct
        distinct = []
        seen = set()
        for label, tid in seq:
            if label not in seen:
                seen.add(label)
                distinct.append((label, tid))
        if len(distinct) < 2:
            continue
        distinct = distinct[:7]
        topic = rid.split('/')[1] if '/' in rid else 'general'
        domain = f"gtn_{topic}"
        gold = []
        toks = set()
        for i, (label, tid) in enumerate(distinct):
            toks.add(label); toks |= set(re.split(r'[_\s/]', label.lower()))
            role = "prep" if i == 0 else ("analysis" if i == len(distinct) - 1 else "step")
            gold.append({
                "sub_task": label, "order": i + 1,
                "depends_on": [i] if i > 0 else [],
                "node_key": f"{domain}:{role}", "tool_id": tid,
                "input_types": [], "output_types": [], "domain": domain, "role": role,
            })
        # query: tutorial title + first prose sentence, scrubbed of tool labels
        title = rid.split('/')[-2].replace('_', ' ').replace('-', ' ')
        intro = re.sub(r'\{%[^%]*%\}', '', txt)
        intro = re.sub(r'[#>*`\[\]]', ' ', intro)
        intro = re.sub(r'\s+', ' ', intro).strip()
        query = scrub(f"{title}. {intro}", toks)
        if len(query) < 40:
            continue
        rows.append(dict(unit="gtn:" + rid, provenance="gtn_tutorial",
                         domain=domain, structure="sequential", gold=gold, query=query))
    return rows


# ---------------------------------------------------------------------------
# emit
# ---------------------------------------------------------------------------
def to_sft(row):
    answer = [{"sub_task": g["sub_task"], "order": g["order"], "depends_on": g["depends_on"]}
              for g in sorted(row["gold"], key=lambda x: x["order"])]
    user = row["query"].rstrip() + "\n\n" + INSTR
    return {"messages": [{"role": "system", "content": SYS},
                         {"role": "user", "content": user},
                         {"role": "assistant", "content": json.dumps(answer)}],
            "task": "task_decomposition", "source": "real_" + row["provenance"],
            "structure": row["structure"], "provenance": row["provenance"],
            "unit": row["unit"]}


def to_bench(row, idx):
    return {"id": f"decreal_{row['structure']}_{idx}", "query": row["query"],
            "structure": row["structure"],
            "gold_subtasks": sorted(row["gold"], key=lambda x: x["order"]),
            "instr": INSTR, "source": "real_" + row["provenance"], "unit": row["unit"]}


def dag_stats(gold):
    n = len(gold)
    depth = n if all(len(g["depends_on"]) <= 1 for g in gold) else None
    # longest path for depth
    oi = {g["order"]: g for g in gold}
    memo = {}

    def lp(o):
        if o in memo:
            return memo[o]
        g = oi[o]
        memo[o] = 1 + (max((lp(d) for d in g["depends_on"]), default=0))
        return memo[o]
    depth = max(lp(g["order"]) for g in gold)
    indeg = [len(g["depends_on"]) for g in gold]
    outdeg = collections.Counter()
    for g in gold:
        for d in g["depends_on"]:
            outdeg[d] += 1
    roots = sum(1 for g in gold if not g["depends_on"])
    max_fanin = max(indeg) if indeg else 0
    max_fanout = max(outdeg.values()) if outdeg else 0
    return {"n": n, "depth": depth, "roots": roots, "max_fanin": max_fanin,
            "max_fanout": max_fanout, "edges": sum(indeg)}


def synth_stats():
    """Distribution over the synthetic generator's answers."""
    agg = collections.defaultdict(list)
    struct = collections.Counter()
    for line in open(SYNTH):
        r = json.loads(line)
        struct[r.get("structure")] += 1
        try:
            ans = json.loads(r["messages"][-1]["content"])
        except Exception:
            continue
        gold = [{"order": a["order"], "depends_on": a.get("depends_on", [])} for a in ans]
        s = dag_stats(gold)
        for k, v in s.items():
            agg[k].append(v)
    return struct, agg


def summarize(agg):
    out = {}
    for k, vs in agg.items():
        if not vs:
            continue
        out[k] = {"mean": round(sum(vs) / len(vs), 3), "max": max(vs), "min": min(vs)}
    return out


def main():
    nf = build_nfcore()
    ch = build_chains()
    gt = build_gtn()
    all_rows = nf + ch + gt

    # dedup by unit + drop rows whose query is not a real, tool-free description
    def informative(q):
        return len([w for w in re.findall(r'[A-Za-z]{3,}', q or "")])
    seen = set()
    uniq = []
    dropped = collections.Counter()
    for r in all_rows:
        if r["unit"] in seen:
            dropped["dup"] += 1
            continue
        if informative(r["query"]) < 6:
            dropped[r["provenance"]] += 1
            continue
        seen.add(r["unit"])
        uniq.append(r)

    # split per source-unit, stratified by (provenance, structure)
    train, val = stratified_split(uniq)

    # write SFT train
    os.makedirs(os.path.dirname(OUT_TRAIN), exist_ok=True)
    with open(OUT_TRAIN, "w") as f:
        for r in train:
            f.write(json.dumps(to_sft(r)) + "\n")

    # write held-out bench + extended scorer
    os.makedirs(VAL_DIR, exist_ok=True)
    import shutil
    shutil.copy(os.path.join(os.path.dirname(os.path.abspath(__file__)), "score_real_base.py"),
                os.path.join(VAL_DIR, "score.py"))
    val_sorted = sorted(val, key=lambda r: (r["structure"], r["unit"]))
    with open(OUT_VAL, "w") as f:
        for i, r in enumerate(val_sorted):
            f.write(json.dumps(to_bench(r, i)) + "\n")

    # disjointness proof
    train_units = sorted(r["unit"] for r in train)
    val_units = sorted(r["unit"] for r in val)
    unit_overlap = sorted(set(train_units) & set(val_units))

    def nodeset(rows):
        s = set()
        for r in rows:
            for g in r["gold"]:
                s.add(g["tool_id"])
        return s
    tn, vn = nodeset(train), nodeset(val)
    node_overlap = sorted(tn & vn)

    split = {
        "train_rows": len(train), "val_rows": len(val),
        "train_units": len(train_units), "val_units": len(val_units),
        "unit_overlap_count": len(unit_overlap), "unit_overlap": unit_overlap,
        "train_nodes": len(tn), "val_nodes": len(vn),
        "node_overlap_count": len(node_overlap),
        "node_overlap_examples": node_overlap[:25],
        "split_rule": "md5(unit)%100 < 25 -> VAL else TRAIN",
        "note": ("unit sets are a hard partition (overlap=0 by construction). Node (tool_id) "
                 "overlap is reported honestly: it comes from workflow_chain nodes that reuse "
                 "the same catalog workflow across different chains; nf-core and gtn nodes are "
                 "file/tutorial-local so do not overlap."),
    }

    # provenance + structure breakdowns
    def breakdown(rows):
        prov = collections.Counter(r["provenance"] for r in rows)
        st = collections.Counter(r["structure"] for r in rows)
        pst = collections.Counter((r["provenance"], r["structure"]) for r in rows)
        return {"by_provenance": dict(prov), "by_structure": dict(st),
                "by_prov_struct": {f"{a}|{b}": c for (a, b), c in pst.items()}}

    # real distribution stats
    real_agg = collections.defaultdict(list)
    real_struct = collections.Counter()
    for r in uniq:
        real_struct[r["structure"]] += 1
        s = dag_stats(r["gold"])
        for k, v in s.items():
            real_agg[k].append(v)
    sstruct, sagg = synth_stats()

    stats = {
        "counts": {
            "total_real_rows": len(uniq),
            "nfcore_parsed": len(nf), "workflow_chains_parsed": len(ch), "gtn_parsed": len(gt),
            "dropped_thin_query": dict(dropped),
        },
        "all": breakdown(uniq),
        "train": breakdown(train),
        "val": breakdown(val),
        "distribution_comparison": {
            "real": {"structure": dict(real_struct), "metrics": summarize(real_agg)},
            "synthetic": {"structure": dict(sstruct), "metrics": summarize(sagg)},
        },
    }
    with open(OUT_SPLIT, "w") as f:
        json.dump(split, f, indent=2)
    with open(OUT_STATS, "w") as f:
        json.dump(stats, f, indent=2)

    print(json.dumps({"counts": stats["counts"], "split": {k: split[k] for k in
          ["train_rows", "val_rows", "unit_overlap_count", "node_overlap_count",
           "train_nodes", "val_nodes"]},
          "all_breakdown": stats["all"], "val_breakdown": stats["val"],
          "dist": stats["distribution_comparison"]}, indent=2))


if __name__ == "__main__":
    main()
