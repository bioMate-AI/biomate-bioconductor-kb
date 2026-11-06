"""Convert held-out RealBio routing items into harness_evolve task format {id,prompt,gold,scorer,input}.
Uses BARE routing (no candidates) — the condition where the base is weakest (0.18), so inner-loop skill
evolution has room to lift it WITHOUT weight training (the ScienceBuddy inner-loop test)."""
import json, sys
REPO="/Users/kky/biomate-review"
rb=[json.loads(l) for l in open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/realbio_routing_eval.jsonl") if l.strip()]
INSTR=("Bioinformatics workflows come primarily from three sources: Nextflow/nf-core, Galaxy, and "
       "Bioconductor. Route this request to the single correct WORKFLOW, using its canonical name.")
out=[]
for r in rb:
    q=r["query"]
    out.append({"id":r.get("id"),"input":q,
                "prompt":f"{INSTR}\nRespond with ONLY the single canonical workflow name and nothing else.\n\nINPUT:\n{q}",
                "gold":r["correct_workflow"],"scorer":"contains"})
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/evolve_tasks_routing.jsonl","w").write("\n".join(json.dumps(e) for e in out))
print(f"wrote {len(out)} evolve tasks (bare routing)")
