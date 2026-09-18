"""Round-2 joint multi-task SFT in EXACT harness prompt formats + label spaces, BALANCED.
Tasks: routing(catalog+bare), param(+restraint), autofix(10-cat, capped), workflow_gen(17-cat),
protocol(PASS/FAIL/WARN). Emits {messages:[{user},{assistant}]}, assistant-token-only."""
import json,os,random,collections
random.seed(7); D="/Users/kky/biomate-review/docs/20260912_onprem_llm/routing_data_v1"
INSTR_ROUTING=("Bioinformatics workflows come primarily from three sources: Nextflow/nf-core, Galaxy, and Bioconductor. "
  "Route this request to the single correct WORKFLOW, using its canonical name (e.g. 'nf-core/rnaseq').")
INSTR_AUTOFIX="Classify this pipeline failure into exactly one fix CATEGORY."
INSTR_PARAM=("Extract values for the specified parameters as a flat JSON object {name: value}. "
  "Include a parameter ONLY if its value is clearly stated in the request. Use canonical/standard values "
  "(e.g. official reference-genome assembly identifiers, not organism common names). Respond with JSON only.")
INSTR_WFGEN="Select the single analysis CATEGORY this research intent belongs to."
INSTR_PROTO="Given the sequencing protocol and the QC situation, decide the correct action: PASS, FAIL, or WARN."
AUTOFIX_CATS=['cloud_storage_error','container_error','data_format_error','dependency_mismatch','genome_mismatch','missing_input','output_assertion_error','param_scope_error','param_type_error','resource_failure']
WFGEN_CATS=['admet','alphafold','atac_seq','bisulfite_seq','chip_seq','crispr_screen','cryo_em','generative_design','gwas','metagenomics','molecular_docking','molecular_dynamics','rna_seq','scrna_seq','spatial_transcriptomics','variant_calling','wgs']
def cls(instr,labs,inp): return f"{instr}\nRespond with EXACTLY ONE option from this list and nothing else:\n{', '.join(labs)}\n\nINPUT:\n{inp}"
def bare(inp): return f"{INSTR_ROUTING}\nRespond with ONLY the single canonical workflow name (e.g. 'nf-core/rnaseq') and nothing else.\n\nINPUT:\n{inp}"
def gp(instr,inp): return f"{instr}\n\nINPUT:\n{inp}"
def ex(u,g): return {"messages":[{"role":"user","content":u},{"role":"assistant","content":str(g)}]}
def load(f): p=f"{D}/{f}"; return [json.loads(l) for l in open(p) if l.strip()] if os.path.exists(p) else []
out=[]
# routing (cap ~500 total)
alln=list({r["correct_workflow"] for r in load("audited_pass_fullcatalog.jsonl")+load("real_studies_labeled.jsonl")})
rt=load("audited_pass_fullcatalog.jsonl")+load("real_studies_labeled.jsonl"); random.shuffle(rt); rt=rt[:380]
for r in rt:
    q,w=r["query"],r["correct_workflow"]; opts=[w]+random.sample([n for n in alln if n!=w],min(40,len(alln)-1)); random.shuffle(opts)
    out.append(ex(cls(INSTR_ROUTING,opts,q),w))
    if random.random()<0.4: out.append(ex(bare(q),w))
# param (all)
for r in load("param_pass.jsonl"):
    gold=r["gold_params"]; keys=[p["name"] for p in r.get("schema_params",[])]; mnf=[k for k in keys if k not in gold]
    cand=sorted(set(gold.keys())|set(mnf)); inp=f"Candidate parameters (fill only those explicitly specified in the request; leave out the rest): {cand}\nRequest: {r['query']}"
    out.append(ex(gp(INSTR_PARAM,inp),json.dumps(gold)))
# autofix (cap per category to fix skew)
af=load("autofix_harness_clean.jsonl"); random.shuffle(af); cap=collections.Counter(); afn=0
for r in af:
    c=r["category"]
    if cap[c]>=60: continue
    cap[c]+=1; afn+=1
    inp=f"{r.get('description','')}\nERROR LOG:\n{r.get('error_log','')}"; out.append(ex(cls(INSTR_AUTOFIX,AUTOFIX_CATS,inp),c))
# workflow_gen
wf=0
for r in load("wfgen_raw.jsonl"):
    if not r.get("intent"): continue
    out.append(ex(cls(INSTR_WFGEN,WFGEN_CATS,r["intent"]),r["expected_category"])); wf+=1
# protocol
pr=0
for r in load("protocol_raw.jsonl"):
    inp=f"Protocol: {r['protocol']}\nQC situation: {r['universal_threshold_problem']}"; out.append(ex(cls(INSTR_PROTO,['PASS','FAIL','WARN'],inp),r["expected_correct_action"])); pr+=1
# decomposition (already {messages:[user,assistant]} format)
for r in load("decomposition_sft.jsonl"):
    if r.get("messages"): out.append({"messages":r["messages"]})
# conditional/long-param SFT (full-schema RAG context, few-valid restraint)
for r in load("conditional_param_sft.jsonl"):
    if r.get("messages"): out.append({"messages":r["messages"]})
for r in load("interworkflow_decomp_sft.jsonl"):
    if r.get("messages"): out.append({"messages":r["messages"]})
for r in load("clarification_sft.jsonl"):
    if r.get("messages"): out.append({"messages":r["messages"]})
for r in load("diagnosis_fix_sft.jsonl"):
    if r.get("messages"): out.append({"messages":r["messages"]})
for r in load("rag_routing_sft.jsonl"):
    if r.get("messages"): out.append({"messages":r["messages"]})
random.shuffle(out)
open(f"{D}/multitask_sft.jsonl","w").write("\n".join(json.dumps(e) for e in out))
def task_of(u):
    return ("autofix" if "fix CATEGORY" in u else "param" if "flat JSON" in u else "wfgen" if "analysis CATEGORY" in u else "protocol" if "PASS, FAIL, or WARN" in u else "routing")
print(f"BUILT {len(out)} | {dict(collections.Counter(task_of(e['messages'][0]['content']) for e in out))}")
