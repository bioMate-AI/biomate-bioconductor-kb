"""Committee DATA audit — gpt-5.6 + gemini-3.8-flash audit the rebuilt data pools (graph anchors +
committee distillation + self-mining) for quality, usability, leakage, and correct labeling BEFORE we
train on them. Real stats + samples embedded. Saves committee_reviews/data_audit_{who}.md."""
import os, json, urllib.request, sys

BRIEF = r"""You are a review COMMITTEE of two experts in one: (A) senior BIOINFORMATICS domain expert,
(B) senior ML data/eval expert. Audit the QUALITY and USABILITY of a freshly rebuilt training-data pool
for an on-prem BioMate model (4,200-workflow catalog, 12k tools, tasks: routing / param-extraction /
autofix / decomposition / workflow-gen). The pool was built from THREE sources to escape templated
self-generation. Be specific, adversarial, prioritized.

# POOL COMPOSITION (data_pool_v2)
Graph anchors (DETERMINISTIC gold from the DB): routing 4198, wfgen 4198, autofix 1719, param 902,
decompose intra 2010 + inter 1385. Self-mining: docs QA 1996 (from 500 docs), commit fixes 377 (from
600 fix commits). Committee distillation (gpt-5.6 + gemini as BioMate teachers): routing 496, wfgen 494,
param 460, autofix 496 (+decompose in progress).

# COMMITTEE-DISTILLATION QUALITY SIGNALS (this is the concern)
teacher-teacher consensus: routing 0.49, wfgen 0.41, autofix 0.36, param 0.30.
teacher-vs-DB-gold agreement (exact-ish string): routing 0.27, wfgen 0.30 (param/autofix: no pre-label).

# REAL SAMPLES (committee distillation)
routing: Q="run gene set enrichment on my ranked gene list" -> DB_gold="clusterprofiler_gene_set_enrichment_analysis",
  gpt-5.6="Gene Set Enrichment Analysis (GSEA)", gemini="Gene Set Enrichment Analysis" -> agree_db=False, consensus=True
routing: Q="compare this signature against a reference..." -> DB_gold="signaturesearch",
  gpt="Connectivity Map Signature Analysis", gemini="Connectivity Map Analysis" -> agree_db=False, consensus=False
routing: Q="omics multivariate analysis on my count matrix..." -> DB_gold="omicade4",
  gpt="Principal Component Analysis (PCA)", gemini="Omics Multivariate Analysis" -> agree_db=False, consensus=False
param: Q="Wilcoxon GO enrichment on ranked human genes" -> DB_gold={"organismDb":"Homo.sapiens"},
  gpt="analysis_method: Wilcoxon...\nontology: Gene Ontology\ninput: ..." (free-form, not schema keys)
autofix: gpt="Missing input data" / gemini="Missing Input" (consensus); gpt="Compilation error"/gemini="Dependency" (no consensus)

# REAL SAMPLES (self-mining — appear high quality)
docs QA: [20260529_WORKFLOW_INPUT_RECIPE.md] Q="how many workflows implement params.mock_mode?" A="Only 1 ... 23 have required-inputs"
commit fix: problem="Export-to-CRO button does nothing" fix="wire button to existing GET /api/drug-discovery/:id/export endpoint"

# GRAPH ANCHOR sample (deterministic gold)
decompose: workflow=a4 gold_steps=["Add gene annotation","Unsupervised exploration","Filter genes by variance","Detect differential expression"]

# AUDIT — answer each, prioritized & concrete
1. COMMITTEE DISTILLATION: teachers answer at CONCEPT level ("GSEA", "PCA") not catalog SLUGS
   ("clusterprofiler_gene_set_enrichment_analysis") because they were NOT given the candidate list /
   param schema. Is the low DB-gold agreement (0.27) therefore a labeling-context bug (fixable by
   supplying candidates/schema, i.e. run teachers the way BioMate actually runs — retrieval-grounded),
   or a real teacher-quality problem? What is the RIGHT way to use teachers here, and is any of the
   current committee-distillation output usable as-is (e.g. autofix categories, or as query-paraphrase
   augmentation) vs must-regenerate?
2. GOLD VALIDITY: for routing, is "one DB slug = the only correct answer" even valid, given many
   workflows can serve a query (GSEA≡clusterProfiler≡fgsea)? How should routing gold be defined +
   scored (accept-set / equivalence classes)? Same question for param (schema-key vs concept).
3. SELF-MINING: are docs-QA and commit-fix pairs trustworthy for training (hallucination risk,
   staleness of incident docs, over-fitting to internal jargon)? What filtering/verification is needed?
4. GRAPH ANCHORS: are DB step_metadata DAGs and enum/default param golds clean enough to be gold, or do
   they need validation (e.g. step_metadata quality, subworkflow module extraction)?
5. LEAKAGE: split is by workflow-name-prefix family hash (~15% eval). Is prefix-family sufficient, or
   will near-duplicate workflows / shared queries leak train->eval? What split is defensible?
6. The SINGLE biggest data-quality risk, and the top 3 fixes BEFORE training on this pool.
Reply in structured markdown, prioritized."""


def call_openai(model="gpt-5.6"):
    body = json.dumps({"model": model, "messages": [{"role": "user", "content": BRIEF}],
                       "max_completion_tokens": 20000, "reasoning_effort": "medium"}).encode()
    req = urllib.request.Request("https://api.openai.com/v1/chat/completions", data=body,
        headers={"Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}", "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=300))["choices"][0]["message"]["content"]


def call_gemini(model="gemini-3.8-flash"):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={os.environ['GOOGLE_API_KEY']}"
    body = json.dumps({"contents": [{"parts": [{"text": BRIEF}]}]}).encode()
    d = json.load(urllib.request.urlopen(urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"}), timeout=300))
    return "".join(p.get("text", "") for p in d["candidates"][0]["content"]["parts"])


if __name__ == "__main__":
    who = sys.argv[1] if len(sys.argv) > 1 else "openai"
    out = call_openai() if who == "openai" else call_gemini()
    p = f"/Users/kky/biomate-review/docs/20260912_onprem_llm/committee_reviews/data_audit_{who}.md"
    open(p, "w").write(out); print(f"[{who}] {len(out)} chars -> {p}\n"); print(out)
