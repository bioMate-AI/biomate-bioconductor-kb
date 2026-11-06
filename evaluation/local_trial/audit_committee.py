"""Multi-LLM committee AUDIT of the on-prem-LLM data pipeline: code, preprocessing, data quality.
Assembles real code excerpts + real data samples + self-found issues, then asks gpt-5.6 (OpenAI) and
gemini-3.8-flash (Google) to independently critique and find what we missed. Claude's view is added by
the caller. Saves each review under committee_reviews/."""
import os, json, re, urllib.request, time, sys

REPO="/Users/kky/biomate-review"; DV=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"
MC=f"{REPO}/docs/20260912_onprem_llm/midtrain_corpus"

def sample_jsonl(p, n=2, pred=None):
    try: rows=[json.loads(l) for l in open(p) if l.strip()]
    except FileNotFoundError: return []
    if pred: rows=[r for r in rows if pred(r)]
    return rows[:n]

def snippet(path, start, end):
    try: return "".join(open(path).readlines()[start-1:end])
    except Exception: return f"(missing {path})"

# ---- assemble real samples ----
sft=sample_jsonl(f"{DV}/multitask_sft_paraphrased.jsonl", 3)
tools=[d.get("text","")[:600] for d in sample_jsonl(f"{MC}/tools_corpus.jsonl", 2)]
rag=sample_jsonl(f"{DV}/multitask_sft_paraphrased.jsonl", 1, lambda r:"Retrieved candidates:" in r["messages"][0]["content"])

BRIEF=f"""You are auditing the DATA PIPELINE for a private on-prem domain LLM for BioMate (a bioinformatics
workflow assistant). Three stages: (1) domain mid-training corpus, (2) grounded multi-task SFT + paraphrase
diversity, (3) a contrastively-trained routing retriever. Critique CODE, PREPROCESSING, and DATA QUALITY.
Be specific and adversarial — find real defects, not praise.

## PIPELINE
- Mid-train corpus ~44.5M deduped tokens: verbalized tools DB (per-field: rawText prose, help_text/
  scientific_context/parameters are JSON -> verbalized; htmlContent dropped as 99% redundant), code
  (17M), ontologies (GO/ChEBI/HPO/EDAM/SO verbalized), forum/KG. Exact+MinHash dedup.
- SFT: 11 grounded tasks (routing, rag_routing, param, cond_param, wfgen, decompose, interwf_decomp,
  clarify, diag_fix, autofix, protocol). GROUNDED in real artifacts (verified workflows, real param
  schemas, real exec errors) — never paraphrase the target's own description. Then paraphrase-augmented
  3,969 -> 17,265 across a 10-voice persona bank (gold + structured blocks kept verbatim).
- Retriever: BGE fine-tuned with InfoNCE on (query, +gold workflow, -hard negatives mined from a hybrid
  TF-IDF+dense retriever). recall@1 0.233->0.767, recall@5 0.377->0.915 on a RANDOM 15% query holdout.

## ISSUES WE ALREADY FOUND (assess whether our fixes are adequate; find MORE)
1. tools_corpus: help_text & scientific_context are JSON; first pass dumped raw JSON into 97% of docs.
   Fixed by parsing+verbalizing; also stripped leaked Galaxy page HTML.
2. param/cond_param: ~170 golds have integer/count params with FRACTIONAL values (nPerm=0.01, iters=0.01,
   numSections=0.05) because generation mapped "X%"/"top-N" to a decimal WITHOUT schema-type validation.
   NOT yet fixed.
3. paraphrase "bury in irrelevant lab context" persona can drown the actual intent (one case: request
   about cold-room/cage-rotation with gold nf-core/rnaseq). NOT yet fixed.

## KEY CODE
### paraphrase split_request (only the request span is reworded; gold+blocks verbatim)
{snippet(f"{REPO}/evaluation/local_trial/paraphrase_augment.py", 34, 47)}

### contrastive retriever InfoNCE + recall eval (random holdout)
{snippet(f"{REPO}/evaluation/local_trial/train_retriever_contrastive.py", 40, 60)}

### tools_corpus scientific_context verbalizer + quality gate
{snippet(f"{REPO}/evaluation/local_trial/export_tools_corpus.py", 62, 84)}

## REAL DATA SAMPLES
### SFT examples (user -> assistant):
{json.dumps([{"u":r["messages"][0]["content"][:400],"a":r["messages"][1]["content"][:200]} for r in sft], indent=1)}
### rag_routing example:
{json.dumps({"u":rag[0]["messages"][0]["content"][:500],"a":rag[0]["messages"][1]["content"]} if rag else {}, indent=1)}
### tools_corpus docs:
{json.dumps(tools, indent=1)[:1200]}

## ANSWER THESE
1. DATA QUALITY: what defects remain in the SFT and corpus? (grounding, label correctness, leakage,
   noise, distribution). Is the param type-validation gap worse than we think? Other schema-validation gaps?
2. PREPROCESSING: is per-field verbalization + dedup sound? What will still leak or duplicate?
3. METHODOLOGY: the retriever recall gain uses a RANDOM query holdout — is that leakage (same workflow in
   train & test)? Should it be a family/temporal holdout? Any train/test contamination in SFT vs holdout?
4. PARAPHRASE: how to detect+drop degenerate paraphrases that lost the intent, cheaply?
5. What is the SINGLE highest-priority fix before spending GPU on training?
Give concrete, prioritized, actionable findings."""

def call_openai(model="gpt-5.6"):
    body=json.dumps({"model":model,"messages":[{"role":"user","content":BRIEF}],
                     "max_completion_tokens":20000,"reasoning_effort":"medium"}).encode()
    req=urllib.request.Request("https://api.openai.com/v1/chat/completions", data=body,
        headers={"Authorization":f"Bearer {os.environ['OPENAI_API_KEY']}","Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req, timeout=300))["choices"][0]["message"]["content"]

def call_gemini(model="gemini-3.8-flash"):
    url=f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={os.environ['GOOGLE_API_KEY']}"
    body=json.dumps({"contents":[{"parts":[{"text":BRIEF}]}]}).encode()
    req=urllib.request.Request(url, data=body, headers={"Content-Type":"application/json"})
    d=json.load(urllib.request.urlopen(req, timeout=300))
    return d["candidates"][0]["content"]["parts"][0]["text"]

if __name__=="__main__":
    who=sys.argv[1] if len(sys.argv)>1 else "openai"
    os.makedirs(f"{REPO}/docs/20260912_onprem_llm/committee_reviews", exist_ok=True)
    out = call_openai() if who=="openai" else call_gemini()
    fn=f"{REPO}/docs/20260912_onprem_llm/committee_reviews/audit_{who}.md"
    open(fn,"w").write(out); print(f"[{who}] {len(out)} chars -> {fn}\n"); print(out[:3000])
