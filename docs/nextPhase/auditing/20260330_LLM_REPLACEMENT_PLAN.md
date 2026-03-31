# LLM Replacement Plan for Rule-Based Methods
**Date:** 2026-03-30
**Status:** Draft — for discussion
**Branch:** `integration/next-phase`
**Companion:** `20260330_RULE_BASED_METHODS_AUDIT.md`

---

## Guiding Principle

The rule-based methods fall into two categories:

1. **Science governance rules** — QC red lines, gold metrics, named profiles. These must remain rule-based because they are cited to publications, have audit trails, and cannot be second-guessed by a language model on a per-query basis.
2. **Routing and understanding rules** — everything else. These exist because building them as rules was faster than using the LLM, but they now create fragility. A new assay type, a new language, or an unexpected phrasing breaks the system silently.

The plan targets category 2. The QC gate (§3) is explicitly out of scope for LLM replacement.

---

## Architecture: Unified Query Understanding (UQU)

The core proposal is a **single structured LLM call** that replaces five separate rule engines. Instead of independently inferring intent type, domain preferences, pipeline format, action routing, and thinking complexity, we ask the LLM once and get a single structured JSON that drives all downstream decisions.

```
User message
     │
     ▼
┌─────────────────────────────────────────────────────────────────┐
│  Unified Query Understanding (UQU) — one Haiku call, cached     │
│                                                                  │
│  Input:  raw message + conversation context + available domains  │
│  Output: UQUResult {                                             │
│    intent_type,        // "workflow_generation" | "research_question" | ...
│    is_sequential,      // bool                                   │
│    pipeline_steps,     // Step[] (if is_sequential)              │
│    preferred_domains,  // string[]                               │
│    penalized_domains,  // string[]                               │
│    key_terms,          // string[] (for FTS boost)               │
│    needs_thinking,     // bool                                   │
│    action_flags,       // {needsWorkflowGeneration, needsToolSearch, ...}
│    chain_hint,         // string | null (e.g. "bulk_rnaseq_de_analysis")
│  }                                                               │
└─────────────────────────────────────────────────────────────────┘
     │
     ├──► FTS query + domain scoring (uses key_terms, domains)
     ├──► Frontend routing (uses action_flags, intent_type)
     ├──► Sequential pipeline builder (uses is_sequential, pipeline_steps)
     ├──► Extended thinking gate (uses needs_thinking)
     └──► Chain search (uses chain_hint, key_terms)
```

This collapses what today are 6 separate rule passes into a single model call that runs once per user message. The existing `_MULTI_TASK_CACHE` caches UQU results by query hash, so repeat or similar queries pay nothing.

---

## Item-by-Item Replacement Plan

### P1 — Sequential Pipeline Detection (Q5 Fix)

**Current state:**
`detectBulletPipeline()` (regex-based, added 2026-03-30) is the pre-LLM bullet parser. User explicitly rejected this as "not satisfying."

**Proposed change:**
Remove `detectBulletPipeline()` entirely. Move this capability into `analyzeIntent()` by improving the system prompt.

`analyzeIntent()` already calls the LLM. The only missing piece is that the prompt is not explicit enough about recognizing list formats. The fix is a targeted system prompt improvement — no new code path needed.

**Prompt improvement (to add to `analyzeIntent` system prompt):**

```
PIPELINE FORMAT RECOGNITION:
Users express multi-step pipelines in many formats. You must recognize ALL of them:

1. Numbered lists:
   "1. FastQC\n2. Trim Galore\n3. STAR alignment"
   → is_sequential: true, pipeline_steps: ["FastQC", "Trim Galore", "STAR alignment"]

2. Bulleted lists (-, *, •):
   "- FastQC\n- Trim Galore\n- STAR"
   → is_sequential: true

3. Prose with connectives:
   "run FastQC then trim adapters then align to hg38"
   → is_sequential: true

4. Labelled steps:
   "Step 1: QC the reads. Step 2: Trim. Step 3: Align."
   → is_sequential: true

5. Paragraph style:
   "I want to first do QC, followed by trimming, and then alignment"
   → is_sequential: true

6. Mixed prose + steps:
   "Please run the following pipeline:\n1. FastQC\n2. BWA-MEM2"
   → is_sequential: true (ignore the introductory sentence)

IMPORTANT: If you detect any of the above, set is_sequential: true and populate
pipeline_steps with the extracted step descriptions in order. Do NOT require the
user to use a specific format. Your job is to recognize intent, not validate syntax.
```

**Why this works:** The LLM call is already happening in `analyzeIntent()`. The current prompt says "detect sequential" but doesn't give examples of different formats. With the above addition, the model handles all cases robustly including edge cases like mixed languages, unusual bullets, or labelled steps — without any regex.

**Migration:** Delete `detectBulletPipeline()` and its call site in `handleUserMessage()`. The LLM path handles everything.

---

### P2 — Unified Query Understanding (Replaces §1.4, §1.5, §1.6, §2.1, §2.2, §1.9 chain hint)

**Current state (backend):**
`_infer_domain_preferences()` — nested token matching, 6 if/elif branches, English-only
`ABBREVIATION_MAP` — 30 static mappings
`_PIPELINE_INTENT_SIGNALS` — 10 English phrases

**Current state (frontend):**
`inferActionsFromType()` — hard lookup table from intent string
`shouldEnableThinking()` — pattern list
`detectBulletPipeline()` — being deleted (see P1)

**Proposed: UQU endpoint**

Add `POST /api/llm/understand` (or integrate into `/api/llm/classify` with a new `mode=understand` param). This is a Haiku call (fast, cheap, cached).

**System prompt structure:**

```
You are the query understanding module for BioMate, a bioinformatics AI platform.
Analyze the user's message and return a structured JSON with these fields:

{
  "intent_type": one of ["workflow_generation", "tool_search", "research_question",
                          "comparison", "error_help", "casual"],
  "is_sequential": bool,  // user is describing a multi-step pipeline
  "pipeline_steps": [],   // list of step descriptions if is_sequential
  "preferred_domains": [], // bioinformatics domains most relevant to this query
                           // from: [genomics, transcriptomics, single_cell, epigenomics,
                           //        proteomics, metabolomics, metagenomics, structural_biology,
                           //        drug_discovery, cryo_em, systems_biology, synthetic_biology,
                           //        bioimaging, lab_automation]
  "penalized_domains": [],  // domains clearly NOT relevant
  "key_terms": [],          // technical terms to boost in workflow search (max 8)
  "needs_thinking": bool,   // true if query requires multi-step reasoning or design
  "chain_hint": null        // if query matches a known workflow chain, its name; else null
                            // known chains: [bulk_rnaseq_de_analysis, chip_seq_peak_calling,
                            //               atac_seq_chromatin, wgs_variant_calling,
                            //               target_to_lead_full, scrnaseq_seurat_full, ...]
}

Rules:
- needs_thinking=true only for: pipeline design, troubleshooting, comparison, mechanism explanation
- needs_thinking=false for: simple workflow requests ("run nf-core/rnaseq"), greetings, yes/no
- pipeline_steps: extract in order, preserve the user's own words for each step
- preferred_domains: include 1-3 most relevant; do not over-specify
- key_terms: include tool names, assay types, organisms; omit generic words like "run", "analyze"
```

**Integration in `galaxy-assistant.ts`:**

Replace the three separate calls:
```typescript
// BEFORE:
const inferredDomains = this._inferDomainWithLLM(intent, workflowText);  // separate call
const thinkingEnabled = this.shouldEnableThinking(message);              // regex
const actions = this.inferActionsFromType(decomposition.type);           // lookup table

// AFTER:
const uqu = await this.unifiedQueryUnderstanding(message, context);      // single call
// uqu.preferred_domains → passed to search
// uqu.needs_thinking → passed to Claude request
// uqu.action_flags derived from uqu.intent_type + uqu.is_sequential
```

The `inferActionsFromType` lookup table shrinks to a thin mapper from `intent_type` to action flags, which is fine to keep — it's the domain inference and complexity assessment that are the fragile parts.

**Integration in `unified_workflow_search.py`:**

Replace `_infer_domain_preferences()` with UQU results passed from the caller:

```python
# BEFORE: called inside search
pref, pen = self._infer_domain_preferences(query)

# AFTER: UQU result passed in from Galaxy API layer
pref = uqu_result.get("preferred_domains", [])
pen = uqu_result.get("penalized_domains", [])
key_terms = uqu_result.get("key_terms", [])  # replaces abbreviation expansion
```

The `ABBREVIATION_MAP` stays as a fast pre-expansion for FTS query building (it's cheap and helps token recall). It moves from being the primary understanding mechanism to being a supplemental FTS helper. The UQU `key_terms` field is the authoritative understanding.

---

### P3 — Workflow Chain Search (Replaces §1.9 Jaccard)

**Current state:**
Jaccard similarity between query tokens and chain keyword sets. Threshold 0.15. Noisy for partial descriptions.

**Proposed:**
Use UQU `chain_hint` field. When `chain_hint` is non-null, skip Jaccard and look up the chain by name directly. The LLM already knows what the user is asking for — asking it to name the chain is a natural part of query understanding.

For the cases where `chain_hint` is null (user doesn't describe a known chain), the Jaccard fallback can remain — it's not being replaced, just demoted to fallback.

```python
def search_chains(query: str, uqu_result: dict = None, min_score=0.15):
    # Try LLM hint first (free if UQU already called)
    if uqu_result and uqu_result.get("chain_hint"):
        hint = uqu_result["chain_hint"]
        chain = self._chains.get(hint)
        if chain:
            return [chain]

    # Fallback: Jaccard (existing logic, unchanged)
    ...
```

The chain names in the UQU system prompt are the keys for direct lookup. The model is given the exact list of available chain names so there's no hallucination risk.

---

### P4 — QC Profile Inference (Replaces §3.4)

**Current state:**
`_infer_qc_profile(nextflow_path)` — keyword matching on path string. Known false positive: `cancer_rnaseq` → somatic profile.

**Proposed:**
Small LLM call (Haiku) given the workflow path, workflow description, and the list of available profile names + one-line descriptions. Model returns one profile name.

```python
_QC_PROFILE_DESCRIPTIONS = {
    "rnaseq_default": "Standard RNA-seq: mRNA libraries, poly-A selected",
    "rnaseq_ffpe": "RNA-seq on FFPE tissue: relaxed thresholds",
    "wgs_30x": "Whole genome sequencing ≥30x coverage",
    "scrnaseq_10x": "10x Chromium single-cell RNA-seq",
    "wgs_somatic": "Somatic variant calling (tumor/normal pairs)",
    "metagenomics_default": "16S or shotgun metagenomics",
    "cryoem_spa": "Cryo-EM single particle analysis",
    "proteomics_dda": "LC-MS/MS data-dependent acquisition proteomics",
    "cheminformatics_default": "Cheminformatics, ADMET, docking workflows",
    "pharmacogenomics_pgx": "Pharmacogenomics and PGx variant analysis",
    # ...
}
```

The call is cached by `(nextflow_path, workflow_description)` hash — each unique workflow is classified once and cached.

**Why this solves the cancer_rnaseq false positive:**
The LLM can read the full workflow description (which says "differential expression of tumor vs normal") and correctly choose `rnaseq_default`, whereas the keyword rule matches `cancer` → somatic.

**What stays rule-based:** The actual thresholds, red lines, and gold metrics. Only the profile *selection* uses LLM.

---

### P5 — Parameter Suggestions Enhancement (Replaces §5)

**Current state:**
Static `_FILE_TYPE_PARAM_SUGGESTIONS` dict: 4 file types, 1-2 suggestions each. Zero workflow specificity.

**Proposed:**
LLM call at preflight time: given the workflow's `nextflow_schema.json` (or the `required_params` list) + the list of uploaded file names (extensions, count), suggest parameter values.

```python
async def _llm_parameter_suggestions(
    workflow_path: str,
    required_params: list[dict],
    input_files: list[str]
) -> list[dict]:
    schema_excerpt = _extract_param_schema(workflow_path, required_params)
    files_summary = _summarize_uploaded_files(input_files)

    prompt = f"""
    Workflow: {workflow_path}
    Parameters: {schema_excerpt}
    Uploaded files: {files_summary}

    For each parameter, if you can infer a likely value from the uploaded files or
    common defaults for this workflow type, provide a suggestion.
    Return JSON: [{{"param_id": ..., "suggested_value": ..., "confidence": "high|medium|low",
                   "rationale": ...}}]
    Only include params where you have good reason to suggest a value.
    """
```

**Why better than current approach:**
Current approach: `fastq` → suggest `strandedness: auto` (always, regardless of workflow).
LLM approach: Given `nf-core/rnaseq` + 4 fastq.gz files → suggests `strandedness: auto`, `input: samplesheet.csv` (needs samplesheet), `genome: hg38` (if file names contain human accessions).

The parameter schema already exists in `nextflow_schema.json` for all nf-core workflows. This is an underpowered asset currently — the LLM can leverage it properly.

---

### P6 — Error Classification (Replaces §4)

**Current state:**
5-case keyword matching. `ANTHROPIC_API_KEY` → LLM takes over. Regex only fires when key is absent.

**No structural change needed.** This is already LLM-first. The only change:

The Ollama fallback (added to `/api/llm/classify` on 2026-03-30) should also be wired to `explain_error`. When Anthropic is unreachable, Ollama provides a richer error summary than the regex.

```python
# In ai_assistant.py explain_error():
# Tier 1: Anthropic (current)
# Tier 2: Ollama via llm_client.py with provider=local_ollama (NEW)
# Tier 3: regex (current fallback)
```

This is a small wiring change, not an architectural one.

---

## What Stays Rule-Based (Intentionally)

| System | Reason |
|--------|--------|
| QC red lines | Cited thresholds (ENCODE, IHEC); must be auditable |
| QC gold metrics | Evidence-graded; LLM shouldn't override published benchmarks |
| QC named profiles | Versioned, citable; each is a manual curation decision |
| Process name → parser routing (§3.5) | Not a "rule" per se — it's a dispatch table. Replace only if nf-core renames break it |
| Doom loop detection (§2.3) | Safety valve; LLM reasoning about itself is unreliable |
| Thinking detector regex (§7) | Pure text parsing of a known XML-like format — correct as-is |
| SOURCE_PRIORITY table (§1.1) | Editorial judgment, not inference — should remain explicit |
| Exact/near name match bonus (§1.7) | User literally typed the workflow name — deserves a strong boost regardless of LLM output |

---

## Migration Strategy

**Phase 1 — Q5 Fix (1 session)**
Delete `detectBulletPipeline()`. Update `analyzeIntent()` system prompt with the format recognition section (P1). Verify with the existing sequential pipeline E2E.

**Phase 2 — UQU on Frontend (1–2 sessions)**
Implement `unifiedQueryUnderstanding()` in `galaxy-assistant.ts`. Route `needs_thinking` and `preferred_domains` from it. Keep `inferActionsFromType()` and `shouldEnableThinking()` as fallbacks if UQU returns null (network timeout, etc.).

**Phase 3 — UQU on Backend (1 session)**
Pass UQU `key_terms` + `preferred_domains` from the frontend to the Galaxy backend workflow search. Replace `_infer_domain_preferences()`. Keep `ABBREVIATION_MAP` for FTS token expansion.

**Phase 4 — Chain Search, QC Profile, Param Suggestions (1–2 sessions each)**
These are independent and can be done in any order.

**Preserved rules throughout:**
Rule-based fallbacks are kept for every replacement. A LLM timeout or failure reverts to the old behavior. No regression in availability.

---

## Performance Budget

All UQU calls use `claude-haiku-4-5` (cheapest, fastest). Caching by message hash means each unique query pays once.

| Call | Tokens (est.) | Latency (est.) | Cache hit rate |
|------|--------------|----------------|----------------|
| UQU (frontend) | 600 in / 150 out | ~300ms | ~40% (conversations repeat patterns) |
| QC profile inference | 300 in / 20 out | ~150ms | ~95% (per workflow, runs once) |
| Parameter suggestions | 800 in / 200 out | ~400ms | ~70% (file names vary) |

UQU runs in the existing `analyzeIntent()` call — no new latency on the critical path. QC profile inference is at workflow generation time (non-blocking). Parameter suggestions are at preflight (already a network round-trip).

---

## Open Questions for Discussion

1. **UQU scope:** Should UQU be a single new call, or should it be the `analyzeIntent()` call with an expanded output schema? The latter requires no new endpoint — the response JSON just gains new fields. Simpler.

2. **Backend vs frontend UQU:** `_infer_domain_preferences()` runs in Python. Should the UQU call happen in the frontend (one call, results passed to backend) or should the backend have its own lightweight version? Currently the Galaxy backend doesn't get a structured "what the user wants" object from the frontend — just the raw query string.

3. **Chain names in UQU prompt:** The chain list needs to stay in sync with `workflow_chain.py`. Should it be auto-populated from the DB at startup? Or manually maintained in the prompt?

4. **Deferred items D5 (C2 param suggestions) and D9 (nf-core subworkflow include):** P5 above addresses the parameter suggestions enhancement (D5). D9 (nf-core subworkflow matching) is orthogonal to LLM replacement — it's a search coverage gap, not a rule fragility issue.
