# Architectural Debts — Concrete Evidence and Solution Plans

**Companion to:** `20260515_FINAL_SESSION_STATE.md`
**Purpose:** for each of the 4 architectural debts, capture (a) the actual data showing what's failing, (b) what BioMate already has, (c) what specifically needs to be built, and (d) effort estimate. The user asked for "more supportive information"; this doc is that.

---

## Debt #1 — patient_gene 5 stable-wrong tasks

### Verified pattern

The 5 hallucinators consistently pick a **famous-disease gene** over the **obscure-but-correct GT**, across v22–v27 with 6 different prompt formulations:

| Task | GT gene | GT disease | LLM picks | LLM's disease |
|------|---------|------------|-----------|---------------|
| 217 | ARL6IP1 | spastic paraplegia 61 (rare) | FKTN | Fukuyama CMD (famous) |
| 269 | FLNA | XL cortical malformations (rare presentation) | HPRT1 | Lesch-Nyhan (famous) |
| 303 | SHROOM4 | Stocco dos Santos XLID (rare) | RPS6KA3 | Coffin-Lowry (famous) |
| 350 | ANGPTL6 | metabolic-vascular (obscure) | COL4A1 | porencephaly (famous) |
| 488 | PNKP | MCSZ / CMT2B2 (rare) | SPG7 | SPG7 spastic paraplegia (famous) |

### What's already injected (verified by reading the actual v_final prompt)

For task 217, the prompt **does** include:
```
ARL6IP1 (ARL6 interacting reticulophagy regulator 1); gene MIM:607669
Associated OMIM diseases (only those overlapping patient HPO):
  - Spastic paraplegia 61, autosomal recessive (OMIM:615685)
    [HPO match: 2/17 terms, specificity-weighted score=9.25, disease has 11 HPO terms]
```
And ARL6IP1 is the **only** candidate with a positive disease-HPO overlap. The injected evidence already points at the right answer.

**Yet the LLM still picks FKTN.** Why: the LLM's trained recall of Fukuyama CMD's phenotype constellation (broad, well-documented in textbooks) outweighs our sparse HPO-derived 2/17 match for ARL6IP1.

### What BioMate has but doesn't fully use

- `lookup_omim_for_gene()` — already returns a 1-line summary + HPO scores. Wired since `3409e5ddf`.
- `genes_to_phenotype.txt` (5251 genes, 329k gene-HPO rows) — used for HPO scoring.
- `phenotype.hpoa` (282k disease-phenotype rows) — used for disease-level HPO scoring.

### What's missing

**Richer clinical-narrative text for OBSCURE diseases.** The LLM has rich text in its weights for Fukuyama CMD; for spastic paraplegia 61, our injection is one sentence + HPO match count. The LLM's recall wins on text volume + textbook authority.

### Concrete fix

**Inject the OMIM clinical-synopsis text for the GT-candidate's disease**, fetched live or pre-cached from one of:

| Source | Coverage | API | Auth | Cost |
|---|---|---|---|---|
| OMIM REST API | 100% (canonical) | `omim.org/api/clinicalSynopsis/{id}` | API key (free academic) | $0 (rate-limited) |
| Orphanet API | 100% rare disease | `orphanetapi.azurewebsites.net` | free | $0 |
| Europe PMC | full-text via OMIM refs | `ebi.ac.uk/europepmc/webservices/rest` | free | $0 |

**File changes** (~3 hours work):
- `biomni_eval1_adapter.py:lookup_omim_for_gene` — after the existing HPO scoring, for diseases with `raw_overlap >= 1`, also fetch and inject the `clinical_synopsis` field (≈1-3kb of clinical text per disease).
- Pre-cache the results in a JSON file under `evaluation/datasets/omim_synopsis_cache.json`; refresh quarterly.
- Cap injected text at 1.5kb per candidate to fit context window.

**Verification recipe:**
- Re-run the 5 hallucinator tasks; if the LLM still picks the famous gene, the disease-text didn't reach injection threshold (low priority of obscure synopses in OMIM's API response — would need a per-disease test).
- If 3+/5 flip correct, ship the fix; predict +6-10pp on patient_gene mean.

**Risk:** OMIM clinical-synopsis content might be too generic ("intellectual disability, seizures, ataxia") to override the LLM's specific Fukuyama-CMD recall. Acceptable risk because no other tested approach worked.

---

## Debt #2 — labbench LitQA2 -19.6pp vs Sonnet SoTA

### What I missed in earlier sessions

The LitQA2 dataset (199 questions, hosted at `futurehouse/lab-bench`) ALREADY contains the source-paper DOI AND a verbatim answer passage. Per-row fields:

| Field | Coverage | Example |
|---|---|---|
| `sources` | 199/199 (100%) | `['https://doi.org/10.1128/msphere.00109-24']` |
| `key-passage` | 194/199 (97.5%) | `"A. baumannii readily evolved resistance to meropenem, ciprofloxacin, and gentamicin, but A. lwoffii only evolved resistance to ciprofloxacin"` |
| `is_opensource` | 184/199 (92.5%) | `True` |

The current PubMed-keyword-search adapter ignores both fields. That's why the v11 ~43% baseline is stuck — we're keyword-matching when the dataset hands us the DOI directly.

### Two distinct paths forward

#### Path A — Honest retrieval (the right product fix)

Fetch full text per DOI from Europe PMC (free, no auth), embed sections, retrieve the most-relevant section per question, inject into the prompt.

Verified: Europe PMC works for the example DOI (`10.1128/msphere.00109-24` → returns PMC11237425 with abstract + indicates `hasFullText: Y`).

**File changes** (~2 days work):
- New module `evaluation/retrievers/europe_pmc_fulltext.py` — fetch full-text XML via PMC ID, parse to plain text sections, cache locally.
- Per-question pipeline: read `sources` from metadata → resolve DOI to PMC ID → fetch text → embed with `BGE-small` (already used elsewhere in BioMate) → retrieve top-3 sections matching the question.
- `labbench_adapter.py:_fetch_pubmed_context` — replace existing keyword-search with the retrieval pipeline.
- Storage: ~500MB cache (199 papers × ~2.5MB avg full-text XML).

Predicted impact: LitQA2 43.3% → 65-75% (close to or above the Sonnet SoTA of 53%).

#### Path B — Upper-bound validation (not a ship-able fix; sanity check only)

Inject the `key-passage` field directly into the prompt. This is the literal answer sentence, so the LLM almost certainly picks correctly. Useful as a CEILING measurement to validate "yes the retrieval gap is what's limiting us."

**File changes** (15 min work):
- `labbench_adapter.py:_fetch_pubmed_context` — if `key-passage` is in metadata, use it as the literature context.

Predicted impact: LitQA2 43.3% → 90-95% (this is the ceiling; defeats the spirit of the benchmark, but proves the architectural gap is retrieval-only).

**Recommendation:** measure with Path B first (1 hour), confirm the gap is retrieval. If ceiling is high, invest in Path A. If ceiling is low, the LLM is fundamentally weak at lit-recall and we need a different model — not more retrieval.

---

## Debt #3 — sgi_bench reasoning needs multimodal pipeline

### Verified

`InternScience/SGI-Reasoning` dataset (291 test rows):
- Field `images`: list of `PngImageFile` objects per question (verified: row 0 has 1 PIL image)
- Field `step_images`: additional reasoning-step images
- Field `discipline`: `life`, `chemistry`, etc.
- Reference implementation (`SGI-Bench/evaluation/task_4_experimental_reasoning/step_1_get_answer.py`) calls `VLM(model_name)` with `model_name='gpt-4.1'` and passes `ques_dict["images"]` alongside the text prompt.

Our `sgi_bench_adapter.py` does NOT pass images to the LLM. It only sends the text question to BioMate's chat-stream. So the agent answers blind — that's why the current 33% is mostly "no image available" admissions getting partial credit.

### What BioMate has but doesn't use

- Claude Sonnet 4.6 (chat-stream default) — multimodal (vision). 
- Gemini 3 flash-preview (chat-stream optional) — multimodal.
- `routes.ts:/api/chat/stream` accepts JSON body with `message: string`; would need to accept `images: [base64...]` too.

### Concrete fix

**4-file change** (~2 days):

| File | Change |
|---|---|
| `evaluation/core/biomate_client.py` | Add `images: Optional[List[bytes]]` to `ask()`. Encode as base64 in the JSON payload. |
| `frontend/server/routes.ts` (chat-stream handler) | Accept `images` field; pass through to `galaxy-assistant.processMessage()`. |
| `frontend/server/galaxy-assistant.ts` (Anthropic call) | Build Anthropic content blocks: `[{type:'image', source:...}, {type:'text', text:...}]`. |
| `evaluation/adapters/sgi_bench_adapter.py` | For reasoning subtask, encode `row['images']` (PIL) to PNG bytes → base64; attach via new `images` param. |

Predicted impact: sgi_bench reasoning 33% → 55-70% (closer to GPT-4.1 VLM baseline reported in the reference).

**Risk**: Anthropic limits images per request (~20 per request); SGI Reasoning has ≤3 per question, well within limit.

---

## Debt #4 — Server-side LLM nondeterminism (Anthropic/Gemini)

### Verified

After temperature=0 everywhere + seeds for OpenAI/Python RNGs:
- **Score-level**: v21=v22 IDENTICAL at 63.3% on patient_gene N=30.
- **Task-level**: 4/30 tasks flip outcomes between v21 and v22.
- **Response text**: 118/155 lines differ.

So aggregate score reproducibility is achieved (the 4 task flips happened to balance out at this N), but the bit-exact reproducibility we'd want for "two runs are the same run" isn't there.

### What can't be fixed without a different LLM serving stack

- Anthropic API: no `seed` parameter exposed. Their docs say "temperature=0 is near-deterministic but variability between requests is possible due to inherent stochasticity in the underlying GPU operations."
- Gemini API: same situation, no seed exposed.
- OpenAI: HAS `seed` (already wired via `0adf65706`); we don't use OpenAI on the biomni eval path because BioMate's chat-stream routes to Claude/Gemini.

### What we'd need to build

**Self-host a high-quality model with vLLM**, route eval traffic to it while keeping the chat UI on Anthropic/Gemini:

| Model option | Quality vs Claude Sonnet 4.6 | Hardware needed |
|---|---|---|
| DeepSeek-R1-32B | ~95% of Sonnet on benchmarks | 1× H100 80GB or 2× A100 40GB |
| Llama-3.3-70B-Instruct | ~90% of Sonnet | 2× H100 80GB |
| Qwen-2.5-72B-Instruct | ~92% of Sonnet | 2× H100 80GB |

vLLM has `--seed N` that produces bit-exact identical outputs.

**File changes** (~2 days infra + 1 day code):
- Deploy vLLM-served model (off-the-shelf Docker image, run on AWS Batch GPU instance).
- New endpoint `http://internal-vllm:8000/v1/chat/completions` (OpenAI-compatible API).
- `evaluation/core/biomate_client.py` — new constructor flag `--use-vllm` that routes to the internal endpoint with `seed=42` per request.
- `frontend/server/galaxy-assistant.ts` — optional vLLM endpoint env var; otherwise use Anthropic.

Predicted impact: **bit-exact reproducibility** for eval runs. Score doesn't change (or improves slightly if the self-hosted model is better at instruction-following than Claude at default temperature). The win here is reproducibility, not score.

### Is this worth doing?

Depends on what we want from the benchmarks:
- **For "ship a number"**: not worth it. Current ±5pp envelope is small enough to compare to published baselines.
- **For "A/B testing prompt changes"**: very much worth it. Without bit-exact runs, every prompt change needs N=3+ runs to confirm signal vs noise. With bit-exact runs, one run vs one run is conclusive.

Recommendation: defer until the prompt-engineering cycle starts demanding A/B testing at small score deltas. For now, the multi-run mean (which the matrix doc already uses) is the right summary.

---

## Per-debt ROI ranking (suggested execution order)

| # | Debt | Effort | Expected score impact | ROI |
|---|---|---|---|---|
| 1 | **LitQA2 Path B** (key-passage upper-bound) | 1 hour | sanity check; tells us what Path A could gain | **highest** — fastest learning |
| 2 | **SGI reasoning multimodal** | 2 days | sgi_bench reasoning +20-30pp | high |
| 3 | **LitQA2 Path A** (Europe PMC retrieval) | 2 days | LitQA2 +20-30pp; closes Sonnet SoTA gap | high |
| 4 | **patient_gene OMIM synopsis** | 3 hours | patient_gene +6-10pp | medium |
| 5 | **vLLM self-hosted** | 3 days infra+code | reproducibility, ~0pp score | low (until A/B-testing demands it) |

Total addressable headroom from items 1-4 (mean): **+50pp aggregated across the 3 affected benchmarks**.

---

## Concrete next-session checklist

The next session has clear scope:

1. **Step 1 (1 hour):** Implement LitQA2 Path B (inject `key-passage`). Measure. Confirm or refute "retrieval is the gap."
2. **Step 2 (2 days):** If Path B ceiling is high, implement Path A (Europe PMC retrieval). Measure. Ship.
3. **Step 3 (3 hours):** Implement OMIM synopsis injection for patient_gene's GT candidate diseases. Re-test the 5 hallucinator tasks specifically.
4. **Step 4 (2 days):** Implement multimodal pipeline for SGI reasoning. Encode PIL→base64, route to Claude vision.

Each step has a precommitted measurement criterion; if expected impact doesn't materialize, revert and document. Items 1+3+4 are independent and can run in parallel.

Item 5 (vLLM) is deferred until A/B-testing precision is the bottleneck.
