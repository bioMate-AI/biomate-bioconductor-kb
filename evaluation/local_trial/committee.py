"""Expert committee review: brief frontier models on BioMate, then review the training-data prep.
Members: gpt-5.6 (OpenAI) + gemini-3.1-pro-preview (Google). Claude's view added by the caller."""
import os, json, sys, urllib.request

BRIEF = r"""You are a review COMMITTEE of two experts in ONE person: (A) a senior BIOINFORMATICS domain
expert, and (B) a senior DEEP-LEARNING / LLM-training expert. First read the BioMate context, then
rigorously REVIEW the team's current training-data preparation. Be specific, critical, actionable.

# BioMate context
BioMate is an agentic bioinformatics workflow assistant: 4,200 workflows + 12,312 tools across 36
domains, plus an internal "tool AI DB" that is a domain knowledge graph (tools<->EDAM operations<->
data types<->workflows<->domains, with execution-verified attributes). ~28 LLM-backed tasks; the core
structured ones: intent DECOMPOSITION (query->ordered sub-task DAG), workflow ROUTING (pick from
4,200), schema-grounded PARAMETER extraction, error DIAGNOSIS, results INTERPRETATION.
Goal: a PRIVATE ON-PREM local LLM (data sovereignty; air-gapped). Base = Qwen3.8-27B (natively
multimodal). Empirical findings established:
- On the RealBio benchmark the base 27B is ~on par with the far larger hosted Qwen3.8-Max.
- Fine-tuning gains are PROMPT-FORMAT-SPECIFIC (a LoRA that helped on one prompt format transferred
  nothing to the production format and caused -7pp NEGATIVE TRANSFER on an untuned task).
- Single-task tuning -> negative transfer; format-matched JOINT training -> small real gains
  (routing-bare +10.5pp; param restraint -32% over-fills), no negative transfer.
- The dominant routing lever is RETRIEVAL (hybrid recall@20=0.95), not weights.
Design principle adopted: skill-in-weights, knowledge-in-retrieval (RAG for volatile catalog/DB).

# Current preparation to review
Plan mirrors Periodic Labs + Meditron GAP-Replay: open base -> MID-TRAINING (domain-adaptive
continued pretraining, LoRA) -> SFT (tasks) -> RL (grounded reward); RAG for volatile facts.
MID-TRAINING CORPUS (staged, ~37M tokens, commercial-safe): internal tool/workflow text (9M) +
workflow CODE Nextflow/Bioconductor/workflow_json (17M) + DB-as-KG relational triples (23k docs) +
workflow-order procedures (3k) + ontologies EDAM/GO/SO/HPO/ChEBI + Hetionet KG (34.7k edges) + GTN
tutorials. External bulk scripted for a disk box: peS2o bio (ODC-BY) + PMC oa_comm + Bio-protocol
(CC-BY) + general replay (FineWeb-Edu/The Stack/Wikipedia).
MIX RATIO: 25% domain / 75% general (distributional bridge, anti-forgetting), total run ~2-4B tokens.
SFT SET (1,834 ex, 6 tasks, verifier-gated, exact production prompt format): routing 529, param 384,
decompose 341, wfgen 320, autofix 211, protocol 49. Verifiers: schema/execution checks + independent
auditor + overlap-gate vs held-out.

# Review — answer each, concretely
1. Is 25% domain / 75% general JUSTIFIED for a 27B ALREADY competitive on-domain, or wrong? Recommend
   a ratio + total-token budget, and whether/how to SWEEP it. What decides the optimum?
2. Is the corpus COMPOSITION sound? Over-weighted / under-weighted / missing? (Hetionet relevance,
   ontology value, code proportion, verbalized-KG value.)
3. Given the base is already competitive and gains are format-specific, is MID-TRAINING worth it vs
   going straight to SFT + retrieval + RL? Rank the ROI of mid-train / SFT / RL / retriever.
4. SFT data: will this be GENERALIZABLE (not format-overfit), accurate, scenario-aligned? Gaps?
   (param gen yield ~16%, protocol only 49, decomposition intra-workflow only.)
5. The single biggest risk in this plan, and the top 3 changes you would make.
Reply in structured markdown with clear recommendations."""


def call_openai(model):
    body = json.dumps({"model": model, "messages": [{"role": "user", "content": BRIEF}],
                       "max_completion_tokens": 20000, "reasoning_effort": "medium"}).encode()
    r = urllib.request.Request("https://api.openai.com/v1/chat/completions", data=body,
                               headers={"Authorization": f"Bearer {os.environ['OPENAI_API_KEY']}",
                                        "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(r, timeout=300))["choices"][0]["message"]["content"]


def call_gemini(model):
    body = json.dumps({"contents": [{"parts": [{"text": BRIEF}]}]}).encode()
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={os.environ['GOOGLE_API_KEY']}"
    r = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    d = json.load(urllib.request.urlopen(r, timeout=300))
    return "".join(p.get("text", "") for p in d["candidates"][0]["content"]["parts"])


if __name__ == "__main__":
    who = sys.argv[1]
    print(call_openai("gpt-5.6") if who == "openai" else call_gemini("gemini-3.1-pro-preview"))
