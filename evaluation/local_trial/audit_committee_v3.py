"""Committee audit v3 — post-training. Reviews DATA, DESIGN, TASKS, OUTPUT (trained-model results),
and ERROR ANALYSIS. FULL accurate numbers (no truncation, per the v1 lesson). gpt-5.6 + gemini-3.8-flash."""
import os, json, urllib.request, sys

BRIEF = """You are auditing a private on-prem domain LLM for BioMate (bioinformatics workflow assistant),
NOW POST-TRAINING. Two models were trained (4B + 27B) and evaluated. Audit DATA, DESIGN, TASKS, OUTPUT,
and ERROR ANALYSIS. Be specific, adversarial, prioritized. All numbers below are exact.

## DATA (v2)
- SFT: 18,597 validated examples across 12 tasks: rag_routing 4253, routing 2526, interwf_decomp 2340,
  clarify 1931, param 1905, decompose 1649, wfgen 1539, cond_param 986, chaining 605, diag_fix 494,
  autofix 211, protocol 158. Grounded in REAL artifacts; paraphrase-diversified; committee-audited +
  validation-gated (fixed: param type errors, request truncation, decompose DAG deps, interwf mislabel,
  genome enums). Distribution: transcriptomics dominates (~44/80 of eval queries).
- Mid-train corpus 44.9M deduped tokens (tools DB verbalized, code, ontologies, WKG). Mid-training was
  SKIPPED for these runs (SFT-first directly on base).
- Workflow Knowledge Graph: 11,412 blocks (4,172 workflows + 7,240 tool-functions), 5,563 data-type
  precede-edges + 70 curated chains. Contrastive retriever: recall@1 0.23->0.77 random split, 0.24->0.40
  honest FAMILY holdout (unseen workflows).

## DESIGN
- Base: Qwen3-4B and Qwen3.8-27B (same family, shared tokenizer) for a controlled capacity comparison.
- Principles: judgment-in-weights vs mechanism-in-harness (0.15 near-tie threshold, disambiguation
  gate, panel full-config stay in harness); clarification as a cross-cutting function; param prefill
  with restraint (panel finishes config); near-ties as CONTRASTIVE signal (DPO hard negatives), not a
  free pass; intended two-model CASCADE (4B attempts, escalate to 27B).

## OUTPUT (trained models)
- 4B: 500 steps, train_loss 0.517 (r16, seq2048).
- 27B: 700 steps, train_loss 0.305 (r32, seq2048). Lower loss = capacity.
- Out-of-catalog removal eval (workflow removed from candidates; reconstruct its phase->step plan;
  step-coverage = LLM-judge fraction of true steps covered), 80 cases:
    gpt-5-mini baseline: coverage 0.54 (composed 1.0, valid 1.0)
    4B:  coverage 0.30 (composed 1.0, valid 0.96)
    27B: coverage 0.40 (composed 0.05 [FORMAT ARTIFACT], valid 1.0)
  27B > 4B; both < frontier 0.54.

## ERROR ANALYSIS (per-case)
- 4B: 26/80 zero-coverage; buckets 0:26, <0.34:25, 0.34-0.66:18, >=0.67:11. By domain (mean cov):
  systems_biology 0.06, metagenomics 0.17, single_cell 0.23, variant_calling 0.24, genomics 0.26,
  transcriptomics 0.31, epigenomics 0.34. 3 invalid picks.
- 27B: 20/80 zero-coverage but BIMODAL: 22 cases >=0.67 AND 20 cases =0. By domain: single_cell 0.25,
  transcriptomics 0.37, epigenomics 0.40, systems_biology 0.41, variant_calling 0.43, metagenomics 0.44,
  genomics 0.53. 0 invalid picks.
- Zero-coverage removed workflows are NICHE/rare-tool ones: rgsea, oncomix, projectr_differential_feature_drivers,
  icnv_ngs_only_cnv_detection, rgadem, magrene, pipecomp, milor_da_contrasts, methylgsa_custom_annotation.
- composed_rate metric is BRITTLE: 27B answers with a concise single pick (it was heavily SFT'd on
  single-workflow routing) rather than the exact {step,workflow_or_action} JSON the regex counts, so
  composed_rate=0.05 despite 0.40 semantic coverage.

## AUDIT — answer each, prioritized & concrete
1. DATA: quality/coverage/distribution problems given the errors? (transcriptomics dominance? niche
   long-tail undertrained? is 18.6k enough across 4,200 workflows/36 domains?)
2. DESIGN: is SFT-first-skip-midtrain defensible, or is the skipped 44.9M corpus why niche tools fail?
   Is the single-workflow-routing SFT suppressing compositional/decomposition behavior in the 27B?
3. TASKS: gaps causing the low out-of-catalog coverage? Is the removal eval itself well-designed?
4. OUTPUT: is coverage 0.30/0.40 vs 0.54 a fair verdict? What confounds it (judge noise, format)?
5. ERROR ANALYSIS: root cause of the NICHE-workflow zero-coverage and the 27B bimodality — data sparsity,
   retriever miss, or generation? What single change most raises coverage?
6. The SINGLE highest-priority fix before v3 compositional training."""

def call_openai(model="gpt-5.6"):
    body=json.dumps({"model":model,"messages":[{"role":"user","content":BRIEF}],
                     "max_completion_tokens":20000,"reasoning_effort":"medium"}).encode()
    req=urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,
        headers={"Authorization":f"Bearer {os.environ['OPENAI_API_KEY']}","Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req,timeout=300))["choices"][0]["message"]["content"]
def call_gemini(model="gemini-3.8-flash"):
    url=f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={os.environ['GOOGLE_API_KEY']}"
    body=json.dumps({"contents":[{"parts":[{"text":BRIEF}]}]}).encode()
    d=json.load(urllib.request.urlopen(urllib.request.Request(url,data=body,headers={"Content-Type":"application/json"}),timeout=300))
    return d["candidates"][0]["content"]["parts"][0]["text"]

if __name__=="__main__":
    who=sys.argv[1] if len(sys.argv)>1 else "openai"
    out=call_openai() if who=="openai" else call_gemini()
    p=f"/Users/kky/biomate-review/docs/20260912_onprem_llm/committee_reviews/audit_v3_{who}.md"
    open(p,"w").write(out); print(f"[{who}] {len(out)} chars\n"); print(out)
