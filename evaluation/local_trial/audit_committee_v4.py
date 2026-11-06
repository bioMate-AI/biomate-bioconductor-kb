"""Committee audit v4 — focused on TASK DEFINITION and DATA SETTING, after the 2026-09-21 finding that
the removal-eval gold was broken (0.27 was a metric artifact) and mid-training is a measured wash.
gpt-5.6 + gemini-3.8-flash. Full accurate numbers. Saves to committee_reviews/audit_v4_{who}.md."""
import os, json, urllib.request, sys

FRONTIER = os.environ.get("FRONTIER_FIXEDGOLD", "re-baseline in progress")

BRIEF = f"""You are a review COMMITTEE of two experts in one: (A) a senior BIOINFORMATICS domain expert,
(B) a senior ML EVALUATION / LLM-training expert. Audit ONLY the TASK DEFINITION and DATA SETTING of a
private on-prem domain LLM for BioMate (agentic bioinformatics workflow assistant). Be adversarial,
specific, prioritized. This audit follows a finding that overturned the previous (v3) conclusions.

# What v3 concluded (now partly INVALIDATED)
v3 said: "skipping mid-training was the critical error; 4B out-of-catalog coverage 0.30, 27B 0.40 vs a
0.54 frontier baseline; niche tools fail." Action was: run the 44.9M-token mid-training + rebalance SFT.

# What the 2026-09-21 session found (this changes the picture)
1. The OUT-OF-CATALOG "removal eval" works like this: take a real (query -> gold workflow) pair where the
   workflow has a step decomposition; REMOVE that workflow from the retrieved candidate list; require the
   model to reconstruct an equivalent phase->step plan from remaining candidates (or GENERATE/RUN_CODE);
   score = LLM-judge (gpt-5-mini) fraction of GROUND-TRUTH steps covered by the model's plan.
2. BENCHMARK-DESIGN FLAW discovered: ground_truth_steps were copied VERBATIM from the REMOVED workflow's
   own step_metadata. Of 150 cases: 50 had tautological gold ("Read User Input" / "Execute Documented
   <Tool> Pipeline" / "Write Outputs"); 53 named the removed tool's OWN internal functions (RGSEAfix,
   topGeneQuants, projectionDriveR). So ~57% of cases were STRUCTURALLY UNCOVERABLE by substitutes — the
   model was scored 0 for not naming the tool that was deliberately deleted.
3. This means the v3 "0.30 / 0.40 vs 0.54" was substantially a METRIC ARTIFACT, not model weakness.
4. FIX APPLIED: regenerated ground_truth_steps as TOOL-AGNOSTIC analytical goals derived from the QUERY
   (e.g. edgeR case -> "filter low-count genes / normalize + estimate dispersion / fit a count model with
   batch+sex covariates / compute log2FC + adjusted p / assemble table with per-group means"). 0 residual
   tautological steps.
5. RE-MEASURED on the fixed gold (80 cases, same harness):
     SFT-only  (raw base + SFT LoRA):        micro 0.483, macro 0.527, nonzero-mean 0.508, nonzero-frac 0.95
     full_mix  (mid-trained base + SFT LoRA): micro 0.493, macro 0.513, nonzero-mean 0.518, nonzero-frac 0.95
     frontier gpt-5-mini on the FIXED gold:  {FRONTIER}
   (validity ~0.93-0.98, composed_rate 1.0 for both on-prem models.)
6. Mid-training was therefore a WASH: on BOTH the broken gold (micro 0.271 vs 0.273) AND the fixed
   sensitive gold (0.483 vs 0.493) the delta is within n=80 noise. The mid-training corpus (46.4M tokens:
   tools 16.7M, code 17.2M, ontologies ~8M, gtn, internal workflow/skill text, WKG, workflow-order,
   DB-KG) + 50/75% FineWeb-Edu replay added no measurable out-of-catalog benefit (light dose: MID=800
   steps, seq-1024, effective batch 16).

# DATA SETTING (current)
- Eval set: 150 removal cases; candidates = contrastive-retriever top-10 with the gold workflow removed
  (family-holdout retriever recall 0.40 on unseen workflows). Domain distribution is TRANSCRIPTOMICS-
  DOMINATED (~44 of 80 eval queries). Gold now = tool-agnostic analytical steps from the query.
- SFT set: 18,597 ex across 12 tasks (rag_routing 4253, routing 2526, interwf_decomp 2340, clarify 1931,
  param 1905, decompose 1649, wfgen 1539, cond_param 986, chaining 605, diag_fix 494, autofix 211,
  protocol 158); grounded in real artifacts, paraphrase-diversified, verifier-gated.
- Mid-train corpus as above (46.4M). Catalog = 4,200 workflows + 12,312 tools across 36 domains.

# AUDIT — answer each, prioritized and concrete
1. TASK DEFINITION — Is "reconstruct the removed workflow's plan from substitutes, scored by step-
   coverage vs an LLM-judged gold" a VALID proxy for real out-of-catalog composition ability? What
   validity threats remain even AFTER the tool-agnostic-gold fix? Propose a better task formulation if
   warranted.
2. METRIC — Is LLM-judged fraction-of-steps-covered the right scoring? Confounds (judge variance,
   step granularity, over-crediting generic/boilerplate plans, the QUERY now containing the analytical
   answer so the model may be doing reading-comprehension not composition)? Recommend a more robust,
   less-gameable metric + how to validate it (e.g. human-agreement, ablations).
3. DATA SETTING (eval) — Does deriving gold FROM the query introduce leakage/circularity? Is
   transcriptomics-dominance invalidating the per-domain and aggregate claims? Is n=80/150 adequate for
   the deltas being claimed? How to construct a defensible held-out eval (families, domains, difficulty)?
4. DATA SETTING (train) — Given mid-training is a MEASURED wash, what does that actually prove: wrong
   corpus, wrong DOSE (only ~14% corpus coverage), wrong lever, or task-not-sensitive-to-domain-knowledge?
   How would you DESIGN the experiment to decide (dose sweep? held-out domain-knowledge probe?)?
5. Given the corrected picture (on-prem 4B ~0.5, not 0.27; mid-train wash), what is the CORRECT task
   definition + data setting to actually MOVE and measure out-of-catalog composition?
6. The SINGLE biggest threat to the VALIDITY of the current task+data setup, and the top 3 changes.
Reply in structured markdown with clear, prioritized recommendations."""


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
    p = f"/Users/kky/biomate-review/docs/20260912_onprem_llm/committee_reviews/audit_v4_{who}.md"
    open(p, "w").write(out)
    print(f"[{who}] {len(out)} chars -> {p}\n")
    print(out)
