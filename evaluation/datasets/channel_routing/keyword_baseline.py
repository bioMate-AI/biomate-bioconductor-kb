#!/usr/bin/env python3
"""Non-LLM keyword baseline for channel routing — a fair surface-cue classifier.
Shows how much of the task is solvable by lexical triggers alone (vs. requiring intent understanding).
Not tuned per item; one modest trigger set per channel, first-strongest-match wins, else the plurality
channel (workflow). Reports overall + drug-discovery-subset accuracy, comparable to the model runs."""
import json, os, re
ROWS = [json.loads(l) for l in open(os.path.join(os.path.dirname(__file__), "data.jsonl"))]
TRIG = {  # channel -> trigger regexes (surface cues a keyword router would plausibly use)
  "workflow": r"\b(run|pipeline|dock(ing)?|screen|rbfe|fep|rna-?seq|variant calling|assemble|align|quantif|simulat|campaign|batch of|process these)\b",
  "tool_search": r"\b(which tool|what tool|recommend|compare|vs\.?|better|add a|replace|method (to|for)|best (tool|method|approach))\b",
  "database_lookup": r"\b(chembl|drugbank|open targets|pdb|uniprot|omim|clinvar|ensembl|faers|gwas|look ?up|what('?s| is) the .*(ic50|ki|affinity|id)|retrieve the)\b",
  "literature_research": r"\b(literature|papers?|published|state[- ]of[- ]the[- ]art|review|mechanism|prior art|evidence|resistance mechanism|what is known)\b",
  "code_execution": r"\b(calculate|compute|convert|parse|fit a|statistical test|similarity|tanimoto|p-?value|regress|count the)\b",
  "knowledge_answer": r"\b(what is|what are|define|explain|rule of five|why (does|is)|how does .* work)\b",
  "dataset_discovery": r"\b(dataset|accession|geo|sra|pride|download .* (data|benchmark)|find (a|an|the) .*(dataset|benchmark|cohort)|tdc|pdbbind)\b",
}
PRIORITY = ["database_lookup","dataset_discovery","literature_research","code_execution","tool_search","knowledge_answer","workflow"]
def classify(q):
    ql = q.lower(); hits = [c for c in PRIORITY if re.search(TRIG[c], ql)]
    return hits[0] if hits else "workflow"
def main():
    ok = okd = n = nd = 0
    for r in ROWS:
        pred = classify(r["query"]); gold = r["correct_channel"]; alts = r.get("acceptable_alts") or []
        hit = pred == gold or pred in alts
        n += 1; ok += hit
        if r.get("domain") == "drug_discovery": nd += 1; okd += hit
    print(f"keyword baseline: overall {ok}/{n} = {ok/n:.3f} | drug-discovery subset {okd}/{nd} = {okd/nd:.3f}")
    json.dump({"overall_accuracy": round(ok/n,4), "drug_discovery_accuracy": round(okd/nd,4), "n": n},
              open(os.path.join(os.path.dirname(__file__),"results","_keyword_baseline.json"),"w"), indent=2)
if __name__ == "__main__": main()
