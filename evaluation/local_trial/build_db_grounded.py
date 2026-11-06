"""Grounded-by-construction SFT seeds generated FROM the full enriched DB (4200 workflows / 12k tools).
Deterministic gold from real fields (name / tools_used / input_types / params_schema / step_metadata) — no
LLM, no weak gold, scales to ~19k. These are (a) directly-usable clean SFT data AND (b) the seed set for
CoT distillation (teacher reasons to a CORRECT gold -> high keep). Usage:
  python build_db_grounded.py --db galaxy_ai_tools.db --out db_grounded_seeds.jsonl --per-task 1800
"""
import argparse, json, sqlite3, random, re, collections
random.seed(13)
SYS = "You are BioMate, an agentic bioinformatics assistant."


def jlist(s):
    try:
        v = json.loads(s)
        return v if isinstance(v, list) else ([v] if v else [])
    except Exception:
        return [x.strip() for x in re.split(r"[;,]", str(s or "")) if x.strip()]


def clean(s, n=400):
    return re.sub(r"\s+", " ", str(s or "")).strip()[:n]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--per-task", type=int, default=1800)
    a = ap.parse_args()
    c = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True); c.row_factory = sqlite3.Row
    wfs = [dict(r) for r in c.execute("select name,domain,description,tools_used,input_types,output_types,"
                                      "params_schema,step_metadata from workflows where name is not null")]
    by_dom = collections.defaultdict(list)
    for w in wfs:
        by_dom[w.get("domain") or "general"].append(w["name"])
    out = []; per = collections.Counter()

    def emit(task, user, gold):
        if per[task] >= a.per_task or not gold:
            return
        per[task] += 1
        out.append({"messages": [{"role": "system", "content": SYS},
                                 {"role": "user", "content": user},
                                 {"role": "assistant", "content": gold}],
                    "task": task, "source": "db_grounded"})

    random.shuffle(wfs)
    for w in wfs:
        name, dom, desc = w["name"], w.get("domain") or "general", clean(w.get("description"), 500)
        if not desc:
            continue
        # workflow_routing (OPEN-BOOK, grounded): request from description + real domain-sibling candidates
        sibs = [n for n in by_dom.get(dom, []) if n != name]
        if sibs:
            cands = [name] + random.sample(sibs, min(6, len(sibs)))
            random.shuffle(cands)
            emit("workflow_routing",
                 "Choose the single best workflow for this request from the candidates. Reply ONLY the exact "
                 f"workflow name.\n\nRequest: I need to {desc.rstrip('.').lower()}.\n\nCandidates:\n"
                 + "\n".join(f"- {x}" for x in cands), name)
        # tool_recommendation: deterministic gold = tools_used
        tools = [t for t in jlist(w.get("tools_used")) if isinstance(t, str) and len(t) > 1]
        if tools:
            emit("tool_recommendation", f"{SYS}\n\nWhat tools/methods are appropriate for this task?\nTask: {desc}",
                 "Suitable tools/methods: " + ", ".join(tools[:12]) + ".")
        # dataset_prerequisite_check: gold = input_types
        inp = [t for t in jlist(w.get("input_types")) if isinstance(t, str)]
        if inp:
            emit("dataset_prerequisite_check", f"What input data is required to {desc[:160].rstrip('.').lower()}?",
                 "Required inputs: " + ", ".join(inp) + ".")
        # parameter_extraction: gold = the real param schema keys
        try:
            ps = json.loads(w.get("params_schema") or "{}")
            keys = list(ps.keys()) if isinstance(ps, dict) else [str(x) for x in ps] if isinstance(ps, list) else []
        except Exception:
            keys = []
        if keys:
            emit("parameter_extraction", f"What are the key parameters to configure for the `{name}` workflow?",
                 "Key parameters: " + ", ".join(str(k) for k in keys[:15]) + ".")
        # task_decomposition: gold = ordered step names
        try:
            sm = json.loads(w.get("step_metadata") or "[]")
            steps = [s.get("step") or s.get("name") or s.get("tool") or s.get("label")
                     for s in sm if isinstance(s, dict)]
            steps = [clean(s, 120) for s in steps if s]
        except Exception:
            steps = []
        if len(steps) >= 2:
            emit("task_decomposition", f"Outline the ordered analysis steps of the `{name}` workflow ({dom}).",
                 " ; ".join(str(s) for s in steps[:12]))
    random.shuffle(out)
    with open(a.out, "w") as f:
        for r in out:
            f.write(json.dumps(r) + "\n")
    print(f"DB-GROUNDED SEEDS: {len(out)} from {len(wfs)} workflows -> {a.out}  by-task={dict(per)}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
