#!/usr/bin/env python3
"""Run a raw LLM as a baseline on the RealBio classification tasks -> predictions.jsonl.

OpenAI-COMPATIBLE by design: works with OpenAI directly (default) or any OpenAI-compatible
endpoint (OpenRouter, Together, Fireworks, DeepSeek, Moonshot/Kimi, DashScope/Qwen) by passing
--base-url and setting the matching API key env var. So the SAME runner produces the full
frontier + open-source leaderboard once keys are available.

Usage:
  python3 run_baseline.py <task> --model gpt-5.3-chat-latest
  python3 run_baseline.py cross_domain_routing --model moonshotai/kimi-k3 \
        --base-url https://openrouter.ai/api/v1 --key-env OPENROUTER_API_KEY

Then score:  python3 score.py <task> results/<model>/<task>.jsonl
"""
import json, os, sys, argparse, re, time

HERE = os.path.dirname(os.path.abspath(__file__))

# label-constrained classification tasks (objective, cheap, parseable)
TASKS = {
    "cross_domain_routing": dict(gt="correct_workflow", inp=lambda r: r["query"],
        instr="Bioinformatics workflows come primarily from three sources: Nextflow/nf-core, Galaxy, and Bioconductor. "
              "Route this request to the single correct WORKFLOW, using its canonical name (e.g. 'nf-core/rnaseq')."),
    "workflow_generation": dict(gt="expected_category", inp=lambda r: r["intent"],
        instr="Select the single analysis CATEGORY this research intent belongs to."),
    "autofix_benchmark": dict(gt="category", inp=lambda r: f"{r.get('description','')}\nERROR LOG:\n{r.get('error_log','')}",
        instr="Classify this pipeline failure into exactly one fix CATEGORY."),
    "protocol_thresholds": dict(gt="expected_correct_action", inp=lambda r: f"Protocol: {r['protocol']}\nQC situation: {r['universal_threshold_problem']}",
        instr="Given the sequencing protocol and the QC situation, decide the correct action: PASS, FAIL, or WARN."),
    "intent_interpretation": dict(gt="intent", inp=lambda r: r["query"],
        instr="Classify this BioMate user request into exactly one INTENT (capability) label from the list."),
}

def labels(task, rows):
    g = TASKS[task]["gt"]
    return sorted({str(r[g]) for r in rows if g in r})

def _extract_json(t):
    import json as J
    m = re.search(r"\{.*\}", t or "", re.S)
    if not m: return {}
    try: return J.loads(m.group())
    except Exception: return {}

# generative (non-label-constrained) tasks — clean, fairly-scorable ones only.
# (boin decision-strings and drug_discovery rank-indices have ambiguous GT semantics -> held until the
#  prompt/GT mapping is nailed down, rather than emit numbers score.py can't fairly grade.)
GEN = {
    "param_prefill": dict(
        # fair (+schema) condition: give the candidate parameter names (schema) — the analog of routing's
        # catalog. Union of the real params and the must-not-fill distractors, so the model must decide from
        # the request which are actually specified (the answer stays hidden). A bare LLM cannot guess a
        # workflow's exact param names, so the no-schema version is ill-posed.
        inp=lambda r: (f"Candidate parameters (fill only those explicitly specified in the request; leave out the rest): "
                       f"{sorted(set((r.get('expected_params') or {}).keys()) | set(r.get('must_not_fill') or []))}\n"
                       f"Request: {r['user_query']}"),
        instr="Extract values for the specified parameters as a flat JSON object {name: value}. "
              "Include a parameter ONLY if its value is clearly stated in the request. "
              "Use canonical/standard values (e.g. official reference-genome assembly identifiers, not organism common names). "
              "Respond with JSON only.",
        parse=_extract_json),
    "pbpk_benchmark": dict(
        inp=lambda r: f"Compound {r.get('name')} (SMILES {r.get('smiles')}), dose {r.get('dose_mg')} mg {r.get('route')}. "
                      f"Task inputs: {r.get('inputs')}. "
                      f"Predict: {r.get('target_endpoint','Cmax')} (peak plasma concentration) in {r.get('target_units','uM')}.",
        instr="Predict the peak plasma concentration Cmax in µM for the compound and dose given, using the "
              "provided PK inputs. Respond with a single number only (no units).",
        parse=lambda t: (re.search(r"[-+]?\d*\.?\d+", t or "") or type("x", (), {"group": lambda s: ""})()).group()),
    # LitQA2 bare baseline (C0): parametric MCQ, NO retrieval. Retrieval systems run via
    # litqa2/run_biomate.py and litqa2/run_paperqa2.py. score.py::score_litqa2 maps the
    # answer to the nearest option, so near-verbatim / short prose is fine.
    "litqa2": dict(
        inp=lambda r: (r["question"] + "\n\nOptions:\n" + "\n".join(f"- {o}" for o in r.get("options", []))),
        instr="Answer this multiple-choice question from your own knowledge (no external retrieval). "
              "Respond with ONLY the exact text of the single best option, copied verbatim. If you cannot "
              "determine it, respond with 'Insufficient information to answer the question.'",
        parse=lambda t: {"answer": (t or "").strip()}),
    "boin_benchmark": dict(
        inp=lambda r: f"Scenario: {r.get('scenario')}. BOIN phase-I dose-finding design inputs: {r.get('inputs')}",
        instr="You are running a BOIN phase-I dose-finding trial with the given dose levels and design. "
              "Determine the recommended maximum tolerated dose (MTD). Respond with a SINGLE number: the MTD "
              "dose in mg — it must be exactly one of the listed dose levels. Number only, no units.",
        parse=lambda t: (re.search(r"[-+]?\d*\.?\d+", t or "") or type("x", (), {"group": lambda s: ""})()).group()),
    "drug_discovery_e2e": dict(
        inp=lambda r: (f"Target {r.get('target')} (PDB {r.get('pdb_id')}, chain {r.get('chain')}). "
                       f"Binding-site residues: {r.get('binding_site_residues')}. "
                       f"Candidate ligands (1-based index order): {r.get('ligands')}"),
        instr="Rank the candidate ligands by predicted binding affinity to the target, STRONGEST first. "
              "Respond with a JSON list of the ligand indices (1-based, matching the input order), "
              "e.g. [3, 2, 1]. JSON list only.",
        parse=lambda t: (lambda m: json.loads(m.group()) if m else [])(re.search(r"\[.*?\]", t or "", re.S))),
    "findings_probe": dict(
        inp=lambda r: f"Run context: {r.get('context')}. Output artifacts produced: {r.get('artifacts')}.",
        instr="Given the outputs this BioMate run produced, state the key finding(s) concisely for the user.",
        parse=lambda t: (t or "").strip()),
    "task_decomposition": dict(
        inp=lambda r: r["query"],
        instr=("Decompose this request into an ordered plan of sub-tasks. Reply ONLY a JSON list of "
               "{\"sub_task\": ..., \"order\": N, \"depends_on\": [prerequisite orders]} — INDEPENDENT "
               "sub-tasks have empty depends_on (they can run in parallel); a sub-task that needs an "
               "earlier one's output lists that order in depends_on."),
        parse=lambda t: (lambda m: json.loads(m.group()) if m else [])(re.search(r"\[.*\]", t or "", re.S))),
}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("task", choices=list(TASKS) + list(GEN))
    ap.add_argument("--model", required=True)
    ap.add_argument("--base-url", default=None)
    ap.add_argument("--key-env", default="OPENAI_API_KEY")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--mode", choices=["bare", "catalog"], default="catalog",
                    help="routing only: 'bare' = from the model's own knowledge (no candidate list); "
                         "'catalog' = give the candidate workflows in-context (RAG-fair). Other tasks always use their label set.")
    ap.add_argument("--catalog-style", choices=["names", "described"], default="names",
                    help="routing catalog only: 'names' = bare workflow names (legacy); 'described' = each "
                         "candidate annotated with its one-line description[:120] from the workflows DB, "
                         "faithful to what the production harness (UnifiedWorkflowSearch) actually shows the LLM.")
    ap.add_argument("--wf-db", default=os.path.join(HERE, "..", "..", "..", "backend", "database", "galaxy_ai_tools.db"),
                    help="SQLite DB with the `workflows` table (for --catalog-style described).")
    ap.add_argument("--price-in", type=float, default=None,
                    help="USD per 1M input tokens (optional; enables per-run $ cost logging).")
    ap.add_argument("--price-out", type=float, default=None,
                    help="USD per 1M output tokens (optional; enables per-run $ cost logging).")
    args = ap.parse_args()

    from openai import OpenAI
    client = OpenAI(base_url=args.base_url, api_key=os.environ[args.key_env])

    # Optional, env-gated decoding controls (default OFF -> behavior unchanged for all existing runs).
    # OR_REASONING_DISABLE=1 passes OpenRouter's {"reasoning":{"enabled":false}} so a *thinking* model
    # answers directly — needed to evaluate reasoning-model families within a bounded token/$ budget and
    # to avoid runaway-reasoning truncation. OR_MAX_TOKENS overrides the 2000 completion cap.
    _extra_body = {}
    if os.environ.get("OR_REASONING_DISABLE") == "1":
        _extra_body["reasoning"] = {"enabled": False}
    _max_tok = int(os.environ.get("OR_MAX_TOKENS", "2000"))

    task = args.task
    is_gen = task in GEN
    spec = GEN[task] if is_gen else TASKS[task]
    rows = [json.loads(l) for l in open(os.path.join(HERE, task, "data.jsonl"))]
    if args.limit: rows = rows[:args.limit]

    if not is_gen:
        labs = labels(task, rows)
        labset = {l.lower(): l for l in labs}
        give_list = not (task == "cross_domain_routing" and args.mode == "bare")

    # Faithful catalog: annotate each candidate name with its production routing description (desc[:120]),
    # exactly as UnifiedWorkflowSearch._browse_catalog_with_llm feeds the LLM. Grounded in the workflows
    # table (real metadata), NOT per-item rules, so it generalizes. Falls back to bare name if no DB row.
    described = (task == "cross_domain_routing" and args.mode == "catalog" and args.catalog_style == "described")
    wf_desc = {}
    if described:
        import sqlite3
        con = sqlite3.connect(args.wf_db)
        # desc, falling back to the grounded `annotation` blob when description is empty — 16 custom
        # BioMate workflows have no description but a rich annotation (the production fix is to backfill
        # description from annotation; this measures that fixed system). annotation is already FTS-indexed.
        for nm, ds in con.execute("SELECT name, COALESCE(NULLIF(TRIM(description),''), annotation, '') FROM workflows "
                                  "WHERE source IN ('nfcore','nfcore_subwf','nextflow','biomni_nextflow','bioconductor',"
                                  "'custom','custom_composer','biomate-ai-tools')"):
            if nm not in wf_desc or (ds and not wf_desc[nm]):
                wf_desc[nm] = ds
        con.close()
        def menu_line(lab):
            d = (wf_desc.get(lab) or "")[:120].replace("\n", " ").strip()
            return f"{lab} — {d}" if d else lab
        menu = "\n".join(menu_line(l) for l in labs)

    suffix = f"_{args.mode}" if task == "cross_domain_routing" else ""
    if described: suffix += "_described"
    # param_prefill: 'catalog' (default, no suffix -> matches existing leaderboard files) gives the
    # candidate param names (the harness's schema layer); 'bare' omits them (no suffix collision) to
    # measure the harness dividend for parameter extraction. A bare LLM cannot know a workflow's exact
    # param keys, so bare F1 is a floor by construction — reported as the dividend's lower anchor.
    param_bare = (task == "param_prefill" and args.mode == "bare")
    if param_bare: suffix = "_bare"
    outdir = os.path.join(HERE, "results", args.model.replace("/", "_"))
    os.makedirs(outdir, exist_ok=True)
    outpath = os.path.join(outdir, f"{task}{suffix}.jsonl")

    def parse_cls(text):
        t = (text or "").strip().lower()
        for l in sorted(labset, key=len, reverse=True):   # longest label first (workflow names contain slashes)
            if l in t: return labset[l]
        return t.split()[0] if t else ""                  # fallback: first token

    n = 0
    # usage/latency accumulators (instrumentation — was previously discarded)
    tot_in = tot_out = 0
    lat_ms = []
    n_usage = 0  # items for which the provider returned a usage block
    with open(outpath, "w") as f:
        for r in rows:
            if param_bare:
                # bare param extraction: request only, no candidate param names (no schema help)
                prompt = ("Extract any analysis parameters explicitly specified in this request as a flat "
                          "JSON object {name: value}. Use canonical/standard values (e.g. official "
                          "reference-genome assembly identifiers, not organism common names). Include a "
                          "parameter ONLY if its value is clearly stated. Respond with JSON only.\n\n"
                          f"INPUT:\nRequest: {r['user_query']}")
            elif is_gen:
                prompt = f"{spec['instr']}\n\nINPUT:\n{spec['inp'](r)}"
            elif described:
                prompt = (f"{spec['instr']}\nEach candidate is 'name — description'. Choose the single best match "
                          f"and respond with EXACTLY its name and nothing else:\n"
                          f"{menu}\n\nINPUT:\n{spec['inp'](r)}")
            elif give_list:
                prompt = (f"{spec['instr']}\nRespond with EXACTLY ONE option from this list and nothing else:\n"
                          f"{', '.join(labs)}\n\nINPUT:\n{spec['inp'](r)}")
            else:  # bare routing: no candidate list — from the model's own knowledge
                prompt = (f"{spec['instr']}\nRespond with ONLY the single canonical workflow name "
                          f"(e.g. 'nf-core/rnaseq') and nothing else.\n\nINPUT:\n{spec['inp'](r)}")
            pred = "" if not is_gen else {}
            in_tok = out_tok = None
            dt_ms = None
            for attempt in range(3):
                try:
                    t0 = time.time()
                    resp = client.chat.completions.create(
                        model=args.model,
                        messages=[{"role": "user", "content": prompt}],
                        max_completion_tokens=_max_tok,
                        extra_body=_extra_body)
                    dt_ms = int((time.time() - t0) * 1000)
                    txt = resp.choices[0].message.content
                    pred = spec["parse"](txt) if is_gen else parse_cls(txt)
                    u = getattr(resp, "usage", None)
                    if u is not None:
                        in_tok = getattr(u, "prompt_tokens", None)
                        out_tok = getattr(u, "completion_tokens", None)
                    break
                except Exception as e:
                    if attempt == 2:
                        sys.stderr.write(f"[{r['id']}] ERR {e}\n")
                    else:
                        time.sleep(2 * (attempt + 1))
            rec = {"id": r["id"], "prediction": pred}
            if in_tok is not None or out_tok is not None:
                rec["prompt_tokens"] = in_tok
                rec["completion_tokens"] = out_tok
                tot_in += in_tok or 0
                tot_out += out_tok or 0
                n_usage += 1
            if dt_ms is not None:
                rec["latency_ms"] = dt_ms
                lat_ms.append(dt_ms)
            f.write(json.dumps(rec) + "\n")
            n += 1
            if n % 25 == 0: sys.stderr.write(f"  {n}/{len(rows)}\n")
    print(f"wrote {n} predictions -> {outpath}")

    # ---- aggregate usage/latency/cost sidecar (the piece the old harness discarded) ----
    def pct(xs, p):
        if not xs: return None
        s = sorted(xs); k = max(0, min(len(s) - 1, int(round((p/100.0) * (len(s) - 1)))))
        return s[k]
    summary = {
        "task": task, "mode": (args.mode if task == "cross_domain_routing" else None),
        "model": args.model, "n": n, "n_with_usage": n_usage,
        "input_tokens_total": tot_in or None, "output_tokens_total": tot_out or None,
        "input_tokens_mean": (tot_in / n_usage) if n_usage else None,
        "output_tokens_mean": (tot_out / n_usage) if n_usage else None,
        "latency_ms_p50": pct(lat_ms, 50), "latency_ms_p95": pct(lat_ms, 95),
        "latency_ms_mean": (sum(lat_ms) / len(lat_ms)) if lat_ms else None,
        "n_with_latency": len(lat_ms),
    }
    if args.price_in is not None and args.price_out is not None and n_usage:
        summary["price_in_per_1m"] = args.price_in
        summary["price_out_per_1m"] = args.price_out
        summary["usd_total"] = round(tot_in/1e6*args.price_in + tot_out/1e6*args.price_out, 6)
        summary["usd_per_item"] = round(summary["usd_total"] / n, 8) if n else None
    else:
        summary["usd_note"] = "pass --price-in/--price-out to log $ cost"
    usage_path = os.path.join(outdir, f"{task}{suffix}.usage.json")
    with open(usage_path, "w") as f:
        json.dump(summary, f, indent=2)
    print(f"wrote usage sidecar -> {usage_path}  "
          f"(in={tot_in} out={tot_out} tok; usage on {n_usage}/{n}; "
          f"lat p50={summary['latency_ms_p50']}ms"
          + (f"; ${summary.get('usd_total')}" if 'usd_total' in summary else "") + ")")

if __name__ == "__main__":
    main()
