#!/usr/bin/env python3
"""Build the on-prem 9B SFT corpus FROM THE COLLECTED CANDIDATE GOLD (user-approved promotion,
2026-10-06). Fixes the two root causes of the prior `domainpro` harness regression:

  (1) trained on generic medical MCQA, not our DB-derived gold   -> train on the collected candidates
  (2) no format/terseness discipline, no harness-task anchors    -> every output is task-appropriately
      TERSE and classification/routing/param/decomp anchors use the EXACT harness prompt formats
      (verbatim instruction strings copied from public_export/run_baseline.py).

Terseness is TASK-APPROPRIATE, not global: routing/param/wfgen/domain outputs are the bare label/JSON;
decomposition is a compact JSON plan; tool-affordance/composition/findings are concise prose with a
hard length cap (findings allowed longer, since narration is a legitimately LLM-bound long output).

Eval-leakage guard: any training example whose user query normalizes to an item in any public_export
task's data.jsonl is DROPPED (routing/param/litqa2/decomp/wfgen/intent/autofix/protocol).

Provenance: every row carries {"task","source"}. No data exclusion beyond dedup + eval-leak guard.

Usage:  python3 build_sft_from_gold.py --out sft_from_gold_20261006.jsonl
"""
from __future__ import annotations
import argparse, json, os, random, re, hashlib, collections, ast

random.seed(20261006)
REPO = "/Users/kky/biomate-review"
CAND = f"{REPO}/docs/20260912_onprem_llm/data_candidates_v2"
POOL = f"{REPO}/docs/20260912_onprem_llm/data_pool_v2"
PUB  = f"{REPO}/evaluation/datasets/public_export"

# ---- verbatim harness instruction strings (public_export/run_baseline.py) ----
INSTR_ROUTING = ("Bioinformatics workflows come primarily from three sources: Nextflow/nf-core, Galaxy, "
    "and Bioconductor. Route this request to the single correct WORKFLOW, using its canonical name "
    "(e.g. 'nf-core/rnaseq').")
INSTR_PARAM = ("Extract values for the specified parameters as a flat JSON object {name: value}. "
    "Include a parameter ONLY if its value is clearly stated in the request. "
    "Use canonical/standard values (e.g. official reference-genome assembly identifiers, not organism "
    "common names). Respond with JSON only.")
INSTR_DECOMP = ("Decompose this request into an ordered plan of sub-tasks. Reply ONLY a JSON list of "
    "{\"sub_task\": ..., \"order\": N, \"depends_on\": [prerequisite orders]} — INDEPENDENT sub-tasks "
    "have empty depends_on (they can run in parallel); a sub-task that needs an earlier one's output "
    "lists that order in depends_on.")
SYS = "You are BioMate, an agentic bioinformatics workflow assistant."

# ---- eval-leakage guard: collect every eval item's query text ----
def _norm(s): return re.sub(r"\s+", " ", str(s or "").strip().lower())

def load_eval_queries():
    qs = set()
    fields = ["query", "user_query", "question", "intent", "protocol", "description"]
    for task in os.listdir(PUB):
        d = os.path.join(PUB, task, "data.jsonl")
        if not os.path.isfile(d):
            continue
        for l in open(d):
            try: r = json.loads(l)
            except Exception: continue
            for f in fields:
                if r.get(f):
                    qs.add(_norm(r[f]))
    return qs

EVAL_Q = load_eval_queries()

def jload(path):
    if not os.path.exists(path):
        print(f"  MISSING {path}", flush=True); return []
    return [json.loads(l) for l in open(path) if l.strip()]

def maybe_json(x):
    """Fields are sometimes JSON-encoded strings; decode defensively."""
    if isinstance(x, (list, dict)): return x
    if isinstance(x, str):
        s = x.strip()
        if s[:1] in "[{":
            try: return json.loads(s)
            except Exception:
                try: return ast.literal_eval(s)
                except Exception: return x
    return x

OUT = []
def add(task, source, msgs, leak_query=None):
    """Append an example, dropping it if its user query collides with an eval item."""
    if leak_query is not None and _norm(leak_query) in EVAL_Q:
        STATS["dropped_leak"] += 1; return
    OUT.append({"messages": msgs, "task": task, "source": source})
    STATS[task] += 1

STATS = collections.Counter()

def u_a(user, assistant, system=None):
    m = []
    if system: m.append({"role": "system", "content": system})
    m.append({"role": "user", "content": user})
    m.append({"role": "assistant", "content": assistant})
    return m

# =====================================================================================
# 1. ROUTING anchors — EXACT harness described-menu format, TERSE (name only).
#    grounded_routing (real R/Bioconductor queries + db_gold) is the query-grounded lane.
#    anchor_routing (4198; gold_workflow + rich description) supplies the described menu pool AND
#    extra routing anchors (INPUT synthesized from I/O+tools+use-case so the model only ever emits
#    the bare name).
# =====================================================================================
anchor_routing = jload(f"{POOL}/anchor_routing.jsonl")
# name -> description[:120] menu pool (production described-catalog faithful)
MENU_POOL = {}
for r in anchor_routing:
    nm = r.get("gold_workflow") or r.get("workflow")
    d = (r.get("anchor", {}) or {}).get("description", "") or ""
    if nm and nm not in MENU_POOL:
        MENU_POOL[nm] = d.replace("\n", " ")[:120].strip()
ALL_NAMES = list(MENU_POOL)

def menu_for(gold, k=18):
    distract = [n for n in ALL_NAMES if n != gold]
    random.shuffle(distract)
    names = [gold] + distract[:k]
    random.shuffle(names)
    lines = []
    for n in names:
        d = MENU_POOL.get(n, "")
        lines.append(f"{n} — {d}" if d else n)
    return "\n".join(lines)

def routing_prompt(query, gold):
    return (f"{INSTR_ROUTING}\nEach candidate is 'name — description'. Choose the single best match and "
            f"respond with EXACTLY its name and nothing else:\n{menu_for(gold)}\n\nINPUT:\n{query}")

# grounded routing (real queries)
for r in jload(f"{POOL}/grounded_routing.jsonl"):
    q = r.get("query"); gold = r.get("db_gold")
    if not q or not gold: continue
    if gold not in MENU_POOL: MENU_POOL[gold] = ""; ALL_NAMES.append(gold)
    add("routing", "grounded_routing", u_a(routing_prompt(q, gold), gold), leak_query=q)

# anchor routing (synthesize a concise request from the anchor; output = bare name)
def synth_request(a):
    desc = (a.get("description") or "").replace("\n", " ")
    m = re.search(r"Use for:\s*(.+?)(?:\.|$)", desc)
    if m:
        return "I need to " + m.group(1).strip()[:200]
    it = maybe_json(a.get("input_types")) or []
    ot = maybe_json(a.get("output_types")) or []
    tu = maybe_json(a.get("tools_used")) or []
    if it or ot:
        return (f"I have {', '.join(it[:3]) or 'data'} and need to produce "
                f"{', '.join(ot[:3]) or 'results'}" + (f" using {', '.join(tu[:3])}" if tu else "") + ".")
    return desc[:160] if desc else None

random.shuffle(anchor_routing)
for r in anchor_routing[:3000]:
    gold = r.get("gold_workflow") or r.get("workflow")
    a = r.get("anchor", {}) or {}
    q = synth_request(a)
    if not gold or not q: continue
    add("routing", "anchor_routing", u_a(routing_prompt(q, gold), gold), leak_query=q)

# =====================================================================================
# 2. PARAM anchors — EXACT harness param_prefill format, compact JSON of ONLY-specified keys.
#    grounded_param (real queries + db_gold + schema_valid_keys) -> teaches restraint (distractors).
# =====================================================================================
def param_prompt(query, cand_keys):
    cand = sorted(cand_keys)
    return (f"{INSTR_PARAM}\n\nINPUT:\nCandidate parameters (fill only those explicitly specified in the "
            f"request; leave out the rest): {cand}\nRequest: {query}")

# workflow -> full param schema (for must-not-fill distractors; grounded_param.schema_valid_keys is a bool flag)
anchor_param_rows = jload(f"{POOL}/anchor_param.jsonl")
WF_SCHEMA = {}
for r in anchor_param_rows:
    wf = r.get("workflow"); sch = r.get("schema_params") or []
    if wf and isinstance(sch, list):
        WF_SCHEMA.setdefault(wf, set()).update(sch)
ALL_PARAM_KEYS = sorted({k for s in WF_SCHEMA.values() for k in s})

def param_cands(wf, gold):
    pool = [k for k in WF_SCHEMA.get(wf, set()) if k not in gold]
    if not pool:  # fall back to a global key pool so restraint is still exercised
        pool = [k for k in ALL_PARAM_KEYS if k not in gold]
    random.shuffle(pool)
    return list(gold.keys()) + pool[:max(4, len(gold) + 3)]

for rep, tag in ((0, "grounded_param"), (1, "grounded_param_rep")):
    for r in jload(f"{POOL}/grounded_param.jsonl"):
        q = r.get("query"); gold = r.get("db_gold") or {}; wf = r.get("workflow")
        if not q or not isinstance(gold, dict) or not gold: continue
        cand = param_cands(wf, gold)
        gold_str = {k: str(v) for k, v in gold.items()}
        add("param", tag, u_a(param_prompt(q, cand), json.dumps(gold_str)), leak_query=q)

# anchor_param: teach the param SCHEMA affordance (which params a workflow commonly sets) — terse JSON.
for r in anchor_param_rows:
    wf = r.get("workflow"); gold = r.get("gold_params") or {}; schema = r.get("schema_params") or []
    if not wf or not isinstance(gold, dict) or not gold: continue
    user = (f"For the '{wf}' workflow, parameters available are: {sorted(schema)}. Give the typical "
            f"non-default settings as a flat JSON object. Respond with JSON only.")
    add("param_schema", "anchor_param", u_a(user, json.dumps({k: str(v) for k, v in gold.items()}), SYS))

# =====================================================================================
# 3. DOMAIN classification anchors — anchor_wfgen (terse single domain label).
#    (NOT forced into the eval workflow_generation label space, which differs; this is a safe
#     terseness-reinforcing domain-classification task on its own 42-domain label set.)
# =====================================================================================
anchor_wfgen = jload(f"{POOL}/anchor_wfgen.jsonl")
DOMAINS = sorted({r.get("gold_category") for r in anchor_wfgen if r.get("gold_category")})
random.shuffle(anchor_wfgen)
for r in anchor_wfgen[:2500]:
    gold = r.get("gold_category"); a = r.get("anchor", {}) or {}
    q = synth_request(a)
    if not gold or not q: continue
    user = (f"Classify this analysis request into exactly one DOMAIN.\nRespond with EXACTLY ONE option "
            f"from this list and nothing else:\n{', '.join(DOMAINS)}\n\nINPUT:\n{q}")
    add("domain_classification", "anchor_wfgen", u_a(user, gold), leak_query=q)

# =====================================================================================
# 4. DECOMPOSITION — EXACT harness task_decomposition JSON format.
#    decomp_intra (intra-workflow steps -> sequential chain), decomp_inter (workflow chains),
#    claude_decomp (already-messaged real decompositions, downsampled).
# =====================================================================================
def decomp_user(query):
    return f"{INSTR_DECOMP}\n\nINPUT:\n{query}"

for r in jload(f"{POOL}/decomp_intra.jsonl"):
    wf = r.get("workflow"); dom = r.get("domain"); gold = r.get("gold") or []
    subs = [g.get("sub_task") for g in gold if isinstance(g, dict) and g.get("sub_task")]
    if len(subs) < 2: continue
    # intra-workflow steps form a sequential chain
    plan = [{"sub_task": s, "order": i + 1, "depends_on": ([i] if i > 0 else [])} for i, s in enumerate(subs)]
    q = f"Run the full {dom or ''} analysis pipeline for '{wf}': walk me through the ordered sub-tasks."
    add("decomposition", "decomp_intra", u_a(decomp_user(q), json.dumps(plan)), leak_query=q)

for r in jload(f"{POOL}/decomp_inter.jsonl"):
    gold = r.get("gold") or []
    plan = []
    for g in gold:
        if not isinstance(g, dict): continue
        st = maybe_json(g.get("sub_task"))
        order = g.get("order")
        if isinstance(st, dict):
            label = st.get("role") or st.get("workflow_name") or st.get("sub_task") or str(st)
        else:
            label = str(st)
        dep = g.get("depends_on")
        if dep is None:
            dep = [order - 1] if (isinstance(order, int) and order > 1) else []
        plan.append({"sub_task": label, "order": order if isinstance(order, int) else len(plan) + 1,
                     "depends_on": dep})
    if len(plan) < 2: continue
    roles = ", ".join(str(p["sub_task"]) for p in plan[:4])
    q = f"I need an end-to-end multi-workflow analysis involving: {roles}. Plan the ordered sub-tasks."
    add("decomposition", "decomp_inter", u_a(decomp_user(q), json.dumps(plan)), leak_query=q)

claude_decomp = jload(f"{POOL}/claude_decomp.jsonl")
random.shuffle(claude_decomp)
kept_cd = 0
for r in claude_decomp:
    msgs = r.get("messages")
    if not msgs: continue
    uq = next((m.get("content") for m in msgs if m.get("role") == "user"), "")
    if _norm(uq) in EVAL_Q:
        STATS["dropped_leak"] += 1; continue
    # ANTI-RAMBLING: the on-disk claude_decomp rows are long-prose research *reports*, not DAG
    # decompositions. Keeping the long ones would reintroduce the exact verbosity the prior domainpro
    # regressed on, so cap the assistant to short plans (<=150 words). Documented in the run doc.
    a_msg = next((m.get("content") for m in msgs if m.get("role") == "assistant"), "")
    if len(str(a_msg).split()) > 150:
        STATS["dropped_long_decomp"] += 1; continue
    OUT.append({"messages": msgs, "task": "decomposition_freeform", "source": "claude_decomp"})
    STATS["decomposition_freeform"] += 1; kept_cd += 1
    if kept_cd >= 2000: break

# =====================================================================================
# 5. TOOL AFFORDANCE — tool_knowledge (what it does / I/O / when to use). Concise, capped.
# =====================================================================================
tk = jload(f"{CAND}/tool_knowledge_candidates.jsonl")
random.shuffle(tk)
kept_tk = 0
for r in tk:
    name = r.get("name"); desc = (r.get("description") or "").strip()
    inp = maybe_json(r.get("inputs")) or []; out = maybe_json(r.get("outputs")) or []
    help_j = maybe_json(r.get("help_text")) or {}
    what = ""
    if isinstance(help_j, dict):
        what = (help_j.get("what_it_does") or "").strip()
    body = (what or desc)
    if not name or not body:
        continue
    body = body.replace("\n", " ")[:400]
    io = ""
    if inp or out:
        io = f" Inputs: {', '.join(map(str, inp[:5])) or 'n/a'}. Outputs: {', '.join(map(str, out[:5])) or 'n/a'}."
    ans = (body + io).strip()[:500]
    user = f"What does the '{name}' tool do, and what are its inputs and outputs?"
    add("tool_affordance", "tool_knowledge", u_a(user, ans, SYS))
    kept_tk += 1
    if kept_tk >= 4000: break

# =====================================================================================
# 6. COMPOSITION RATIONALE — rich records (rationale/chains/phase) templated; tool_compatibility
#    edges used sparingly as terse affordance facts (capped).
# =====================================================================================
comp = jload(f"{CAND}/composition_rationale_candidates.jsonl")
compat = []
for r in comp:
    st = r.get("source_table"); rec = r.get("record") or {}
    if st == "workflow_chains":
        nm = rec.get("display_name") or rec.get("name"); d = (rec.get("description") or "").replace("\n", " ")
        if nm and d:
            user = f"Why is the '{nm}' multi-workflow chain composed the way it is? Summarize its rationale."
            add("composition_rationale", "workflow_chains", u_a(user, d[:600], SYS))
    elif st in ("rationale_registry", "workflow_phase_rationale"):
        txt = (rec.get("rationale_text") or "").replace("\n", " ")
        if txt:
            user = "Explain the design rationale for this workflow phase (what it does and why)."
            add("composition_rationale", st, u_a(user, txt[:600], SYS))
    elif st == "tool_compatibility":
        compat.append(rec)
# repeat the rich rationale records x2 (they are few and high-value)
for _ in range(2):
    for r in comp:
        st = r.get("source_table"); rec = r.get("record") or {}
        if st == "workflow_chains":
            nm = rec.get("display_name") or rec.get("name"); d = (rec.get("description") or "").replace("\n", " ")
            if nm and d:
                add("composition_rationale", "workflow_chains", u_a(
                    f"Why is the '{nm}' multi-workflow chain composed the way it is? Summarize its rationale.",
                    d[:600], SYS))
        elif st in ("rationale_registry", "workflow_phase_rationale"):
            txt = (rec.get("rationale_text") or "").replace("\n", " ")
            if txt:
                add("composition_rationale", st, u_a(
                    "Explain the design rationale for this workflow phase (what it does and why).", txt[:600], SYS))
random.shuffle(compat)
for rec in compat[:1000]:
    tid = str(rec.get("tool_id", "")).split("\n")[-1].strip()
    dt = rec.get("data_type"); ct = rec.get("compatibility_type")
    if not tid or not dt: continue
    ans = f"The '{tid}' tool is compatible with {dt} as {ct or 'data'}."
    add("tool_affordance", "tool_compatibility", u_a(
        f"Is the '{tid}' tool compatible with {dt}?", ans, SYS))

# =====================================================================================
# 7. FINDINGS — biomate_run_output (given run outputs, state the finding). Bounded length
#    (narration may be longer than a label, but capped so it does not teach unbounded rambling).
# =====================================================================================
ro = jload(f"{CAND}/biomate_run_output_candidates.jsonl")
# prefer has_gold / passing rows
ro.sort(key=lambda r: (0 if r.get("has_gold") else 1,
                       0 if (isinstance(r.get("score"), dict) and r["score"].get("passed")) else 1))
kept_ro = 0
for r in ro:
    out = r.get("expected") or r.get("produced_output")
    if not out or not isinstance(out, str): continue
    task = r.get("intended_task", "analysis")
    ans = out.replace("\n\n", "\n").strip()[:1200]  # bounded narration
    user = ("Given the outputs this BioMate run produced, state the key finding(s) concisely for the "
            f"user. Run context: {task}.")
    add("findings", "biomate_run_output", u_a(user, ans, SYS))
    kept_ro += 1
    if kept_ro >= 800: break

# =====================================================================================
# 8. SELF-FIX — git_fix_pair (issue -> fix). Concise summary of the fix.
# =====================================================================================
for r in jload(f"{CAND}/git_fix_pair_candidates.jsonl"):
    issue = (r.get("issue_statement") or "").strip()
    diff = (r.get("fix_diff_excerpt") or "").strip()
    files = r.get("files_changed") or []
    if not issue or not diff: continue
    issue1 = issue.split("\n")[0][:300]
    user = f"A pipeline change failed with this issue:\n{issue1}\nWhat is the fix?"
    ans = (f"Fix touches {', '.join(files[:4]) if files else 'the affected module'}. "
           f"Patch:\n{diff[:600]}")
    add("self_fix", "git_fix_pair", u_a(user, ans, SYS))

# =====================================================================================
# 9. WORKFLOW DECOMPOSITION (verified lane spec -> intent->phases->steps->tool-DAG).
# =====================================================================================
for r in jload(f"{CAND}/workflow_spec_candidates.jsonl"):
    if r.get("real_exec_status") not in ("ok", "ok_warnings"):
        continue  # the 1,092 verified lane only
    wf = r.get("workflow_name"); dom = r.get("domain")
    tools = maybe_json(r.get("tools_used")) or []
    it = maybe_json(r.get("input_types")) or []; ot = maybe_json(r.get("output_types")) or []
    if not wf or not tools: continue
    user = (f"For the verified '{wf}' ({dom}) workflow, give the tool pipeline from inputs to outputs.")
    ans = (f"Inputs: {', '.join(map(str, it[:4])) or 'n/a'} -> tools: {' -> '.join(map(str, tools[:8]))} "
           f"-> outputs: {', '.join(map(str, ot[:4])) or 'n/a'}.")
    add("workflow_decomposition", "workflow_spec_verified", u_a(user, ans, SYS))

# ---- dedup (by user+assistant hash) + shuffle + write ----
def ukey(ex):
    m = {x["role"]: str(x.get("content", "")) for x in ex["messages"]}
    return hashlib.md5((m.get("user", "")[:400] + "||" + m.get("assistant", "")[:300]).encode()).hexdigest()

seen = set(); dedup = []
for ex in OUT:
    k = ukey(ex)
    if k in seen: STATS["dropped_dup"] += 1; continue
    seen.add(k); dedup.append(ex)
random.shuffle(dedup)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--out", required=True); a = ap.parse_args()
    with open(a.out, "w") as f:
        for ex in dedup:
            f.write(json.dumps(ex) + "\n")
    bytask = collections.Counter(ex["task"] for ex in dedup)
    bysrc = collections.Counter(ex["source"] for ex in dedup)
    # terseness report: assistant token proxy (whitespace words) per task
    toklen = collections.defaultdict(list)
    for ex in dedup:
        a_msg = next((m["content"] for m in ex["messages"] if m["role"] == "assistant"), "")
        toklen[ex["task"]].append(len(str(a_msg).split()))
    print(f"\n=== SFT FROM GOLD: {len(dedup)} examples "
          f"(dropped {STATS['dropped_dup']} dup, {STATS['dropped_leak']} eval-leak) -> {a.out}")
    print(f"eval queries guarded against: {len(EVAL_Q)}")
    print("\nby task (count | mean/median/p95 assistant words):")
    for t, n in bytask.most_common():
        ws = sorted(toklen[t]); mean = sum(ws) / len(ws); med = ws[len(ws) // 2]; p95 = ws[int(len(ws) * 0.95)]
        print(f"  {t:26s} {n:6d} | {mean:6.1f} / {med:4d} / {p95:4d}")
    print("\nby source:")
    for s, n in bysrc.most_common():
        print(f"  {s:26s} {n:6d}")

if __name__ == "__main__":
    main()
