#!/usr/bin/env python3.11
"""Run REAL Biomni (A1 agent, Opus-5 via OpenRouter) on RealBio tasks -> predictions.jsonl.
Extends the committed pilot runner (S3 biomni_realbio/biomni_realbio.py, which produced the
5-task Biomni pilot) with the 3 new tasks pbpk/boin/drug_discovery_e2e. Same A1 config, same
<solution>-tag extraction, same output format, scored by the same score.py. Identical prompts to
run_baseline.py so the Biomni row is a fair same-item comparison."""
import json, os, sys, re, time, argparse, contextlib, io

# --- classification tasks (label-set constrained) — pilot's 5 (unchanged) ---
TASKS = {
 "cross_domain_routing": dict(inp=lambda r: r["query"],
   instr="Bioinformatics workflows come primarily from three sources: Nextflow/nf-core, Galaxy, and Bioconductor. Route this request to the single correct WORKFLOW, using its canonical name (e.g. 'nf-core/rnaseq')."),
 "autofix_benchmark": dict(inp=lambda r: f"{r.get('description','')}\nERROR LOG:\n{r.get('error_log','')}",
   instr="Classify this pipeline failure into exactly one fix CATEGORY."),
 "protocol_thresholds": dict(inp=lambda r: f"Protocol: {r['protocol']}\nQC situation: {r['universal_threshold_problem']}",
   instr="Given the sequencing protocol and the QC situation, decide the correct action: PASS, FAIL, or WARN."),
 "workflow_generation": dict(inp=lambda r: r["intent"], instr="Select the single analysis CATEGORY this research intent belongs to."),
}
GEN = {
 "param_prefill": dict(
   inp=lambda r: (f"Candidate parameters (fill only those explicitly specified in the request; leave out the rest): "
                  f"{sorted(set((r.get('expected_params') or {}).keys()) | set(r.get('must_not_fill') or []))}\nRequest: {r['user_query']}"),
   instr="Extract values for the specified parameters as a flat JSON object {name: value}. Include a parameter ONLY if its value is clearly stated. Use canonical/standard values (official reference-genome assembly identifiers, not common names). Respond with JSON only."),
}
# --- NEW: numeric / list tasks (parse a single number or a JSON list from <solution>) ---
def _num(t):
    m = re.search(r"[-+]?\d*\.?\d+", t or ""); return m.group() if m else ""
def _list(t):
    m = re.search(r"\[.*?\]", t or "", re.S)
    try: return json.loads(m.group()) if m else []
    except Exception: return []
NUM = {
 "pbpk_benchmark": dict(
   inp=lambda r: f"Compound {r.get('name')} (SMILES {r.get('smiles')}), dose {r.get('dose_mg')} mg {r.get('route')}. Task inputs: {r.get('inputs')}",
   instr="Predict the requested pharmacokinetic value. Respond with a single number only (no units).", parse=_num),
 "boin_benchmark": dict(
   inp=lambda r: f"Scenario: {r.get('scenario')}. BOIN phase-I dose-finding design inputs: {r.get('inputs')}",
   instr="You are running a BOIN phase-I dose-finding trial with the given dose levels and design. Determine the recommended maximum tolerated dose (MTD). Respond with a SINGLE number: the MTD dose in mg — it must be exactly one of the listed dose levels. Number only, no units.", parse=_num),
 "drug_discovery_e2e": dict(
   inp=lambda r: (f"Target {r.get('target')} (PDB {r.get('pdb_id')}, chain {r.get('chain')}). Binding-site residues: {r.get('binding_site_residues')}. Candidate ligands (1-based index order): {r.get('ligands')}"),
   instr="Rank the candidate ligands by predicted binding affinity to the target, STRONGEST first. Respond with a JSON list of the ligand indices (1-based, matching the input order), e.g. [3, 2, 1]. JSON list only.", parse=_list),
}
def labels(task, rows, gt): return sorted({str(r[gt]) for r in rows if gt in r})
GT={"cross_domain_routing":"correct_workflow","autofix_benchmark":"category","protocol_thresholds":"expected_correct_action","workflow_generation":"expected_category"}

def extract_solution(out):
    sol = out[1] if isinstance(out,(tuple,list)) and len(out)>1 else str(out)
    m=re.search(r"<solution>(.*?)</solution>", sol, re.S)
    return (m.group(1) if m else sol).strip()

def _key_usage(key):
    """OpenRouter key spend-so-far (USD) — for per-task cost capture. Returns None on failure."""
    try:
        import urllib.request
        req=urllib.request.Request("https://openrouter.ai/api/v1/key", headers={"Authorization":f"Bearer {key}"})
        d=json.loads(urllib.request.urlopen(req, timeout=15).read()).get("data",{})
        return float(d.get("usage")) if d.get("usage") is not None else None
    except Exception:
        return None

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("task"); ap.add_argument("--mode",default="catalog"); ap.add_argument("--limit",type=int,default=0); ap.add_argument("--tools",action="store_true"); ap.add_argument("--repeats",type=int,default=1)
    # NOTE: claude-opus-5 (the 5-task pilot engine) REJECTS Biomni's assistant-prefill
    # agent loop ("model does not support assistant message prefill") — so it cannot run the
    # multi-turn code-executing tasks (pbpk/boin/dd). Prefill was removed across Claude >=4.6.
    # claude-opus-4.1 is the newest Opus that still supports Biomni's loop -> strongest fair engine.
    ap.add_argument("--model",default="anthropic/claude-opus-4.1")
    ap.add_argument("--skip",type=int,default=0)  # skip first N rows (resume a partial run)
    a=ap.parse_args()
    key=os.environ['OPENROUTER_API_KEY']
    from biomni.agent import A1
    agent=A1(path='/data', llm=a.model, source='Custom',
             base_url='https://openrouter.ai/api/v1', api_key=key,
             use_tool_retriever=a.tools, timeout_seconds=300)
    cost0=_key_usage(key); wall0=time.time()
    task=a.task
    is_num = task in NUM; is_gen = task in GEN
    spec = NUM[task] if is_num else (GEN[task] if is_gen else TASKS[task])
    rows=[json.loads(l) for l in open(f'/data/realbio/{task}/data.jsonl')]
    if a.skip: rows=rows[a.skip:]
    if a.limit: rows=rows[:a.limit]
    if not is_gen and not is_num:
        labs=labels(task,rows,GT[task]); labset={l.lower():l for l in labs}
    def parse_cls(t):
        t=(t or "").strip().lower()
        for l in sorted(labset,key=len,reverse=True):
            if l in t: return labset[l]
        return t.split()[0] if t else ""
    suffix=f"_{a.mode}" if task=="cross_domain_routing" else ""
    od='/data/results_tools' if a.tools else '/data/results'; os.makedirs(od,exist_ok=True); outp=f'{od}/{task}{suffix}.jsonl'
    n=0; lats=[]
    with open(outp,'w') as f:
        # --repeats>1: same items re-run R times (rep in id suffix) -> run-to-run STABILITY axis
        for rep in range(max(1,a.repeats)):
          for r in rows:
            if is_num or is_gen: prompt=f"{spec['instr']}\n\nINPUT:\n{spec['inp'](r)}"
            else: prompt=f"{spec['instr']}\nRespond with EXACTLY ONE option from this list and nothing else:\n{', '.join(labs)}\n\nINPUT:\n{spec['inp'](r)}"
            pred="" if not is_gen else {}; lat=None
            # OpenRouter auto-charge LAGS -> instantaneous balance dips -> Biomni's large-reservation
            # agent calls transiently 402. A 402 fails before spending, so retry with backoff to let
            # auto-charge catch up (cheap + resilient to the oscillation).
            for attempt in range(6):
                try:
                    t0=time.time()
                    with contextlib.redirect_stdout(io.StringIO()):
                        out=agent.go(prompt)
                    lat=int((time.time()-t0)*1000); lats.append(lat); sol=extract_solution(out)
                    if is_num: pred=spec["parse"](sol)
                    elif is_gen:
                        m=re.search(r"\{.*\}",sol,re.S); pred=json.loads(m.group()) if m else {}
                    else: pred=parse_cls(sol)
                    break
                except Exception as e:
                    es=str(e)
                    if ("402" in es or "available credits" in es) and attempt<5:
                        sys.stderr.write(f"[{r['id']}] 402 credit dip — backoff {attempt+1}/6\n"); time.sleep(60); continue
                    sys.stderr.write(f"[{r['id']}] ERR {es[:120]}\n"); break
            rec={"id":r["id"],"prediction":pred,"latency_ms":lat}
            if a.repeats>1: rec["rep"]=rep
            f.write(json.dumps(rec)+"\n"); f.flush()
            n+=1; sys.stderr.write(f"  {n}/{len(rows)*max(1,a.repeats)} id={r['id']} rep={rep} pred={str(pred)[:40]!r}\n")
    # --- multi-dimensional usage sidecar: cost + speed alongside accuracy (score.py) ---
    cost1=_key_usage(key); wall_s=round(time.time()-wall0,1)
    slat=sorted(lats); p50=slat[len(slat)//2] if slat else None
    cost_usd = round(cost1-cost0,4) if (cost0 is not None and cost1 is not None) else None
    usage={"task":task,"model":a.model,"n":n,"wall_s":wall_s,
           "cost_usd":cost_usd,"cost_per_item_usd":(round(cost_usd/n,4) if cost_usd is not None and n else None),
           "mean_latency_ms":(int(sum(lats)/len(lats)) if lats else None),"p50_latency_ms":p50,
           "n_errors":n-len(lats),"repeats":a.repeats}
    with open(f'{od}/{task}{suffix}.usage.json','w') as uf: json.dump(usage,uf,indent=2)
    print(f"wrote {n} -> {outp}"); print("USAGE:", json.dumps(usage))
if __name__=="__main__": main()
