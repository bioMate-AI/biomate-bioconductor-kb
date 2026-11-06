"""Real end-to-end use-case test of the LOCAL model (served OpenAI-compatible endpoint).
Drives realistic BioMate scenarios through the actual agentic steps — intent -> routing (with
candidates) -> parameter extraction -> (failure) diagnosis — using production/harness prompt formats.
Prints the model's real outputs + a pass mark where gold is determinable. Run vs base or sft."""
import argparse, json, os, re, urllib.request
def call(cfg, prompt, mx=200):
    body=json.dumps({"model":cfg["model"],"messages":[{"role":"user","content":prompt}],"max_tokens":mx,"temperature":0}).encode()
    r=urllib.request.Request(cfg["base_url"].rstrip("/")+"/chat/completions",data=body,
        headers={"Content-Type":"application/json","Authorization":f"Bearer {os.environ.get(cfg.get('key_env','X'),'x')}"})
    return json.load(urllib.request.urlopen(r,timeout=120))["choices"][0]["message"]["content"].strip()
def norm(s): return re.sub(r"[^a-z0-9]+"," ",str(s).lower()).strip()
INTENTS=["workflow_generation","data_analysis","troubleshooting","database_lookup","parameter_help","general_question"]
ROUTES=["nf-core/rnaseq","nf-core/scrnaseq","nf-core/sarek","nf-core/chipseq","nf-core/atacseq","admet_screening","nf-core/differentialabundance","alphafold2"]
AUTOFIX=['cloud_storage_error','container_error','data_format_error','dependency_mismatch','genome_mismatch','missing_input','output_assertion_error','param_scope_error','param_type_error','resource_failure']
# realistic, fresh scenarios (not from RealBio test set)
SCEN=[
 {"name":"Bulk RNA-seq (mouse)","query":"I have paired-end FASTQ files from a mouse liver experiment, 6 treated vs 6 control, and I want differential gene expression.",
  "intent":"workflow_generation","route":"nf-core/rnaseq",
  "params":{"cands":["genome","strandedness","single_end","aligner"],"gold":{"genome":"GRCm39","single_end":"false"}}},
 {"name":"Single-cell","query":"10x Genomics single-cell RNA-seq from human PBMCs, I need clustering and cell-type annotation.",
  "intent":"workflow_generation","route":"nf-core/scrnaseq","params":{"cands":["genome","protocol","aligner"],"gold":{"genome":"GRCh38"}}},
 {"name":"Somatic variants","query":"Tumor/normal whole-genome sequencing BAMs, human, I want somatic SNV and indel calls.",
  "intent":"workflow_generation","route":"nf-core/sarek","params":{"cands":["genome","wes","tools"],"gold":{"genome":"GRCh38"}}},
 {"name":"ADMET","query":"Here are 20 candidate compounds as SMILES; screen them for hERG liability and oral bioavailability.",
  "intent":"workflow_generation","route":"admet_screening","params":{"cands":["endpoints","input_format"],"gold":{}}},
 {"name":"Failed run","query":None,"intent":None,"route":None,
  "diag":{"log":"Error: reference genome index not found for GRCh37 but BAM header shows GRCh38. Execution halted","gold":"genome_mismatch"}},
]
def run(cfg):
    ok=tot=0
    for s in SCEN:
        print("\n=== SCENARIO:",s["name"],"===")
        if s.get("query"):
            print("USER:",s["query"])
            # 1) intent
            ip=f"Classify the user request into exactly one intent.\nRespond with EXACTLY ONE option from this list and nothing else:\n{', '.join(INTENTS)}\n\nINPUT:\n{s['query']}"
            io=call(cfg,ip,30); m="intent: %s"%io.strip()[:40]
            if s.get("intent"): tot+=1; hit=norm(s["intent"]) in norm(io); ok+=hit; m+=f"  [{'OK' if hit else 'x'} want {s['intent']}]"
            print(" ",m)
            # 2) route (with candidates)
            rp=(f"Route this request to the single correct WORKFLOW using its canonical name.\nRespond with EXACTLY ONE option from this list and nothing else:\n{', '.join(ROUTES)}\n\nINPUT:\n{s['query']}")
            ro=call(cfg,rp,30)
            if s.get("route"): tot+=1; hit=norm(s["route"]) in norm(ro); ok+=hit; print(f"  route: {ro.strip()[:40]}  [{'OK' if hit else 'x'} want {s['route']}]")
            # 3) params
            if s.get("params"):
                pp=(f"Extract values for the specified parameters as a flat JSON object. Include a parameter ONLY if clearly implied. Use canonical values (e.g. GRCh38/GRCm39). Respond with JSON only.\nCandidate parameters: {s['params']['cands']}\n\nINPUT:\n{s['query']}")
                po=call(cfg,pp,120); print("  params:",po.strip()[:120])
                for k,v in s["params"]["gold"].items():
                    tot+=1; hit=v.lower() in po.lower(); ok+=hit; print(f"     want {k}={v}: {'OK' if hit else 'x'}")
        if s.get("diag"):
            dp=(f"A pipeline run failed. Classify into exactly one fix category.\nRespond with EXACTLY ONE option from this list and nothing else:\n{', '.join(AUTOFIX)}\n\nINPUT:\nERROR LOG:\n{s['diag']['log']}")
            do=call(cfg,dp,30); tot+=1; hit=norm(s["diag"]["gold"]) in norm(do); ok+=hit
            print("USER: [failed run]\n  diagnosis:",do.strip()[:40],f" [{'OK' if hit else 'x'} want {s['diag']['gold']}]")
    print(f"\n=== REAL-USE-CASE SCORE: {ok}/{tot} checks passed ===")
if __name__=="__main__":
    ap=argparse.ArgumentParser(); ap.add_argument("--base-url",required=True); ap.add_argument("--model",default="base"); ap.add_argument("--key-env",default="DUMMY_KEY")
    a=ap.parse_args(); run({"base_url":a.base_url,"model":a.model,"key_env":a.key_env})
