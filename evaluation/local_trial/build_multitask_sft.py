"""Build joint multi-task SFT data in the EXACT RealBio harness prompt formats (so training matches
the metric). Tasks: routing (catalog+bare), param_prefill (+restraint), autofix (harness 10-cat).
Emits {messages:[{user: harness_prompt},{assistant: gold}]} — assistant-token-only."""
import json, os, random
random.seed(7); D="/Users/kky/biomate-review/docs/20260912_onprem_llm/routing_data_v1"
INSTR_ROUTING=("Bioinformatics workflows come primarily from three sources: Nextflow/nf-core, Galaxy, and Bioconductor. "
  "Route this request to the single correct WORKFLOW, using its canonical name (e.g. 'nf-core/rnaseq').")
INSTR_AUTOFIX="Classify this pipeline failure into exactly one fix CATEGORY."
INSTR_PARAM=("Extract values for the specified parameters as a flat JSON object {name: value}. "
  "Include a parameter ONLY if its value is clearly stated in the request. Use canonical/standard values "
  "(e.g. official reference-genome assembly identifiers, not organism common names). Respond with JSON only.")
AUTOFIX_CATS=['cloud_storage_error','container_error','data_format_error','dependency_mismatch','genome_mismatch',
 'missing_input','output_assertion_error','param_scope_error','param_type_error','resource_failure']
def cls_prompt(instr, labs, inp): return f"{instr}\nRespond with EXACTLY ONE option from this list and nothing else:\n{', '.join(labs)}\n\nINPUT:\n{inp}"
def bare_routing_prompt(inp): return f"{INSTR_ROUTING}\nRespond with ONLY the single canonical workflow name (e.g. 'nf-core/rnaseq') and nothing else.\n\nINPUT:\n{inp}"
def gen_prompt(instr, inp): return f"{instr}\n\nINPUT:\n{inp}"
def ex(user, gold): return {"messages":[{"role":"user","content":user},{"role":"assistant","content":str(gold)}]}
def load(f): 
    p=f"{D}/{f}"; return [json.loads(l) for l in open(p) if l.strip()] if os.path.exists(p) else []
out=[]
# --- routing: catalog (large option list incl gold) + bare ---
allnames=list({r["correct_workflow"] for r in load("audited_pass_fullcatalog.jsonl")+load("real_studies_labeled.jsonl")})
rt=load("audited_pass_fullcatalog.jsonl")+load("real_studies_labeled.jsonl"); random.shuffle(rt); rt=rt[:800]
for r in rt:
    q=r["query"]; w=r["correct_workflow"]
    opts=[w]+random.sample([n for n in allnames if n!=w], min(40,len(allnames)-1)); random.shuffle(opts)
    out.append(ex(cls_prompt(INSTR_ROUTING,opts,q), w))           # catalog format
    if random.random()<0.4: out.append(ex(bare_routing_prompt(q), w))  # some bare
# --- param: harness gen format + restraint (must_not_fill distractors) ---
for r in load("param_pass.jsonl"):
    gold=r["gold_params"]; keys=[p["name"] for p in r.get("schema_params",[])]
    mnf=[k for k in keys if k not in gold]
    cand=sorted(set(gold.keys())|set(mnf))
    inp=f"Candidate parameters (fill only those explicitly specified in the request; leave out the rest): {cand}\nRequest: {r['query']}"
    out.append(ex(gen_prompt(INSTR_PARAM,inp), json.dumps(gold)))
# --- autofix: harness 10-cat format ---
for r in load("autofix_harness_raw.jsonl"):
    inp=f"{r.get('description','')}\nERROR LOG:\n{r.get('error_log','')}"
    out.append(ex(cls_prompt(INSTR_AUTOFIX,AUTOFIX_CATS,inp), r["category"]))
random.shuffle(out)
open(f"{D}/multitask_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
import collections
# tag task by heuristic for counts
def task_of(e):
    u=e["messages"][0]["content"]
    return "autofix" if "fix CATEGORY" in u else ("param" if "flat JSON" in u else "routing")
print(f"BUILT multitask_sft.jsonl: {len(out)} examples | {dict(collections.Counter(task_of(e) for e in out))}")
