#!/usr/bin/env python3
"""
generate_training_data_from_db.py
---------------------------------
GENERALIZED, DB-SCALE training-data generator. The real answer to "why 30 examples when the
catalog has 4,210 workflows": walk backend/database/galaxy_ai_tools.db and emit THOUSANDS of
grounded, leakage-controlled SFT + GRPO rows.

Two generators:
  ROUTING  (query -> workflow filename): templated NL queries synthesized from each workflow's
           REAL metadata (description / annotation_v2 / domain / tools_used); gold = the real
           filename. Target is real catalog; only the query phrasing is synthetic.
  PARAM    (query+context -> required params): from each workflow's REAL params_schema, gold =
           the required param NAMES; must_not_fill = param names sampled from OTHER workflows.
           Teaches param SELECTION + restraint (the must_not_fill model-owned failure). NOTE: the
           DB has param names/types but not gold VALUES, so this is a name-selection task, not
           value prediction — stated honestly, not conflated with the value task.

HONESTY (critical — the decomp_depgraph lesson): TARGETS ARE REAL DB ENTRIES; QUERIES ARE
SYNTHETIC/TEMPLATED. This is a scaled CANDIDATE pool. Its value MUST be validated on the REAL
held-out distribution (cross_domain_routing / decomposition_real / param_prefill), NEVER on this
generator's own distribution — scoring on-distribution is exactly the leaked-win mistake.

LEAKAGE CONTROL: excludes any generated query whose normalized form matches a held-out eval query,
and any workflow whose filename maps to a held-out routing gold; plus a deterministic 10% dev split
held out of train. Manifest emits the leakage proof (0 overlap).

Run:  python3 generate_training_data_from_db.py            # full generation
      python3 generate_training_data_from_db.py --selftest # small sample; assert leakage=0 + schema
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
DB = REPO / "backend" / "database" / "galaxy_ai_tools.db"
PE = REPO / "evaluation" / "datasets" / "public_export"
OUT = REPO / "docs" / "20260912_onprem_llm" / "data_pool_v2"

SYS_ROUTING = ("You are BioMate's workflow router. Given a user request, respond with the single "
               "nextflow workflow filename that best fulfills it.")
SYS_PARAM = ("You are BioMate's parameter assistant. Given a request and the target workflow, list "
             "the required input parameters as JSON. Do not invent parameters the workflow lacks.")

MAX_ROUTING_VARIANTS = 3
DEV_FRAC_BUCKET = 0   # hash(filename)%10 == 0 -> dev split (~10%)


def norm(s):
    return re.sub(r"\s+", " ", str(s or "").strip().lower())


def _first_sentence(txt):
    t = re.split(r"(?<=[.!?])\s", str(txt or "").strip())[0]
    return t.strip()[:240]


def _slug_tokens(fn):
    return set(re.split(r"[^a-z0-9]+", str(fn or "").lower())) - {"", "main", "nf", "subworkflows"}


def load_eval_guards():
    """Normalized held-out queries + routing gold slugs to exclude from the generated TRAIN pool."""
    qn, golds = set(), set()
    rp = PE / "cross_domain_routing" / "data.jsonl"
    if rp.is_file():
        for ln in rp.open():
            r = json.loads(ln)
            qn.add(norm(r.get("query")))
            for g in [r.get("correct_workflow")] + list(_lit(r.get("acceptable_alts")) or []):
                if g:
                    golds.add(norm(g))
    pp = PE / "param_prefill" / "data.jsonl"
    if pp.is_file():
        for ln in pp.open():
            qn.add(norm(json.loads(ln).get("user_query")))
    return qn, golds


def _lit(x):
    import ast
    if isinstance(x, (list, dict)):
        return x
    try:
        return json.loads(x)            # JSON first (handles true/false/null)
    except Exception:
        pass
    try:
        return ast.literal_eval(x)      # then Python-literal (single quotes)
    except Exception:
        return {} if str(x).strip().startswith("{") else []


def _eligible(row):
    fn = row["filename"] or ""
    if not fn or "." not in fn:
        return False
    desc = row["annotation_v2"] or row["description"] or ""
    return bool(str(desc).strip()) and desc not in ("null",)


def _gold_leaks(fn, eval_golds):
    """Conservative: skip a workflow if its slug matches / is matched by a held-out routing gold."""
    toks = _slug_tokens(fn)
    for g in eval_golds:
        gt = _slug_tokens(g)
        if gt and (gt <= toks or toks <= gt):   # one slug-token-set contains the other
            return True
    return False


def _dev(fn):
    return int(hashlib.md5(fn.encode()).hexdigest(), 16) % 10 == DEV_FRAC_BUCKET


def routing_queries(row):
    desc = _first_sentence(row["annotation_v2"] or row["description"])
    domain = (row["domain"] or "").replace("_", " ").strip()
    tools = _lit(row["tools_used"]) or []
    tool = (tools[0].split("/")[-1] if tools else "").strip()
    qs = []
    if desc:
        qs.append(desc)
        if domain:
            qs.append(f"I need a {domain} workflow that will {desc[0].lower() + desc[1:]}")
        if tool:
            qs.append(f"{desc} (using {tool})")
    # dedup + cap, keep grounded in real text
    seen, out = set(), []
    for q in qs:
        k = norm(q)
        if k and k not in seen:
            seen.add(k); out.append(q)
        if len(out) >= MAX_ROUTING_VARIANTS:
            break
    return out


def param_target(row, all_param_names):
    import random
    ps = _lit(row["params_schema"])
    if not isinstance(ps, dict):
        return None
    inputs = ps.get("data_inputs") or []
    names = [i.get("name") for i in inputs if isinstance(i, dict) and i.get("name")]
    names = [n for n in names if n]
    if not names:
        return None
    own = set(names)
    rng = random.Random(hashlib.md5((row["filename"] or "").encode()).hexdigest())
    foreign = [n for n in rng.sample(sorted(all_param_names - own),
                                     min(3, len(all_param_names - own)))]
    return names, foreign


def generate(limit=None):
    conn = sqlite3.connect(str(DB))
    conn.row_factory = sqlite3.Row
    eval_q, eval_golds = load_eval_guards()
    rows = conn.execute(
        "SELECT filename,name,domain,description,annotation_v2,tools_used,params_schema,"
        "real_exec_status FROM workflows").fetchall()
    if limit:
        rows = rows[:limit]
    # universe of param names (for must_not_fill distractors)
    all_param_names = set()
    for r in rows:
        ps = _lit(r["params_schema"])
        if isinstance(ps, dict):
            for i in ps.get("data_inputs") or []:
                if isinstance(i, dict) and i.get("name"):
                    all_param_names.add(i["name"])

    out = {k: [] for k in ("routing_sft", "routing_grpo", "param_sft", "param_grpo", "dev")}
    excl = {"ineligible": 0, "gold_leak": 0, "query_leak": 0}
    for r in rows:
        if not _eligible(r):
            excl["ineligible"] += 1
            continue
        fn = r["filename"]
        if _gold_leaks(fn, eval_golds):
            excl["gold_leak"] += 1
            continue
        exec_ok = r["real_exec_status"] in ("ok", "ok_warnings")
        dev = _dev(fn)
        # ROUTING
        for q in routing_queries(r):
            if norm(q) in eval_q:
                excl["query_leak"] += 1
                continue
            sft = {"messages": [{"role": "system", "content": SYS_ROUTING},
                                {"role": "user", "content": q},
                                {"role": "assistant", "content": fn}],
                   "task": "routing", "gold": fn, "exec_ok": exec_ok, "query_synthetic": True}
            grpo = {"prompt": f"{SYS_ROUTING}\n\n{q}", "gold": fn, "scorer": "routing",
                    "task": "routing", "query_synthetic": True}
            (out["dev"] if dev else out["routing_sft"]).append(sft)
            if not dev:
                out["routing_grpo"].append(grpo)
        # PARAM
        pt = param_target(r, all_param_names)
        if pt:
            names, foreign = pt
            desc = _first_sentence(r["annotation_v2"] or r["description"])
            q = f"Set up the inputs for: {desc}" if desc else f"Set up inputs for {r['name']}"
            if norm(q) not in eval_q:
                gold_obj = {"required_params": sorted(names)}
                sft = {"messages": [{"role": "system", "content": SYS_PARAM},
                                    {"role": "user", "content": f"{q}\nWorkflow: {fn}"},
                                    {"role": "assistant", "content": json.dumps(gold_obj)}],
                       "task": "param", "gold": gold_obj, "must_not_fill": foreign,
                       "query_synthetic": True}
                grpo = {"prompt": f"{SYS_PARAM}\n\n{q}\nWorkflow: {fn}",
                        "gold": json.dumps({"required_params": sorted(names), "must_not_fill": foreign}),
                        "scorer": "param_select", "task": "param", "query_synthetic": True}
                if dev:
                    out["dev"].append(sft)
                else:
                    out["param_sft"].append(sft); out["param_grpo"].append(grpo)
    return out, excl, eval_q


def _write(out, excl, eval_q):
    OUT.mkdir(parents=True, exist_ok=True)
    files = {
        "db_generated_routing_sft.jsonl": out["routing_sft"],
        "db_generated_routing_grpo.jsonl": out["routing_grpo"],
        "db_generated_param_sft.jsonl": out["param_sft"],
        "db_generated_param_grpo.jsonl": out["param_grpo"],
        "db_generated_dev.jsonl": out["dev"],
    }
    for name, rows in files.items():
        with (OUT / name).open("w") as f:
            for r in rows:
                f.write(json.dumps(r) + "\n")
    # leakage proof over everything written as TRAIN
    train_qs = [norm(r["messages"][1]["content"].split("\nWorkflow:")[0]) for r in
                out["routing_sft"] + out["param_sft"]]
    leak = sum(1 for q in train_qs if q in eval_q)
    manifest = {
        "generator": "generate_training_data_from_db.py",
        "db": "backend/database/galaxy_ai_tools.db",
        "counts": {k: len(v) for k, v in out.items()},
        "total_train_rows": len(out["routing_sft"]) + len(out["routing_grpo"])
                            + len(out["param_sft"]) + len(out["param_grpo"]),
        "excluded": excl,
        "leakage_proof": {"train_queries_in_heldout_eval": leak,
                          "status": "CLEAN (0 overlap)" if leak == 0 else "LEAK — DO NOT USE"},
        "dev_split": {"rows": len(out["dev"]), "rule": "md5(filename)%10==0 (~10%), held out of train"},
        "CAVEAT": ("TARGETS are REAL catalog entries; QUERIES are SYNTHETIC/templated from real "
                   "metadata. This is a SCALED CANDIDATE POOL — validate ONLY on the REAL held-out "
                   "distribution (cross_domain_routing / param_prefill / decomposition_real), NEVER "
                   "on this generator's own distribution (the decomp_depgraph leaked-win mistake). "
                   "PARAM gold = required param NAMES + must_not_fill (selection+restraint), NOT "
                   "value prediction (DB has no gold values)."),
    }
    with (OUT / "db_generated_manifest.json").open("w") as f:
        json.dump(manifest, f, indent=2)
    return manifest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        out, excl, eval_q = generate(limit=300)
        train_qs = [norm(r["messages"][1]["content"].split("\nWorkflow:")[0])
                    for r in out["routing_sft"] + out["param_sft"]]
        leak = sum(1 for q in train_qs if q in eval_q)
        n = sum(len(v) for k, v in out.items())
        schema_ok = all("messages" in r and len(r["messages"]) == 3
                        for r in out["routing_sft"][:50] + out["param_sft"][:50])
        print(f"selftest: {n} rows from 300 workflows; leakage(train∩eval)={leak}; schema_ok={schema_ok}")
        print("PASS" if leak == 0 and schema_ok else "FAIL")
        return 0 if (leak == 0 and schema_ok) else 1
    out, excl, eval_q = generate()
    m = _write(out, excl, eval_q)
    print("wrote db_generated_* to", OUT)
    print(json.dumps({"counts": m["counts"], "total_train_rows": m["total_train_rows"],
                      "excluded": m["excluded"], "leakage": m["leakage_proof"]}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
