# IND §2.6.1 LLM Narrative + Gemini Migration Completion

**Date:** 2026-04-26  
**Branch:** integration/next-phase  
**Session scope:** Gemini 3 Flash `max_tokens` audit, IND narrative generation, DD-CRO-5 test hardening, tour tip update, Demo 11 recording.

---

## 1. Gemini 3 Flash `max_tokens` Audit

### Problem
`gemini-3-flash-preview` has thinking tokens that consume `max_output_tokens` budget before any visible text is generated. Calls with `maxTokens < 1024` produce truncated output (5–10 words or partial sentences). The previous session completed the Haiku → Gemini migration but left nine call sites with token budgets too small for thinking overhead.

### Fixes applied

| File | Call site | Old | New |
|---|---|---|---|
| `frontend/server/routes.ts` | Error analysis | 500 | 1024 |
| `frontend/server/routes.ts` | Session title generation | 30 | 1024 |
| `frontend/server/routes.ts` | `/api/llm/classify` yes/no | 10 | 1024 |
| `frontend/server/galaxy-assistant.ts` | Inline data extraction | 256 | 1024 |
| `frontend/server/galaxy-assistant.ts` | Domain classifier | 30 | 1024 |
| `frontend/server/galaxy-assistant.ts` | Session summary | 256 | 1024 |
| `frontend/server/galaxy-assistant.ts` | Session memory updater | 600 | 1024 |
| `frontend/server/galaxy-assistant.ts` | Clarification question gen | 200 | 1024 |
| `frontend/server/galaxy-assistant.ts` | Intent coverage checker | 150 | 1024 |

**Rule:** `max_tokens=1024` is the hard minimum for any `callGeminiFlash()` call. Thinking overhead is paid per call regardless of desired output length — there is no cost benefit to using 256.

---

## 2. IND §2.6.1 LLM Narrative Generation

### Architecture

`INDSectionAssembler` in `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py` now injects FDA regulatory prose into five of the six CTD §2.6.1 sub-sections via `_llm_narrative(section_type, data)`.

**System prompt (`_NARRATIVE_SYSTEM`):**
> "You are a regulatory affairs scientist drafting language for an IND application submitted to the FDA. Write in formal ICH/FDA regulatory document style: precise, passive-voice where appropriate, evidence-referenced, and suitably hedged. No markdown — plain prose only. 2-4 sentences maximum per response."

**Sections with LLM narrative:**

| Section | Prompt focus | Data injected |
|---|---|---|
| §2.6.1.1 Overview | Introduce BioMate platform + validated methods | `molecule_name`, `target_name`, `indication` |
| §2.6.1.2 PBPK Qualification | Interpret EMA criterion pass/fail | AFE, AAFE, R², within-2-fold Cmax/AUC, EMA status |
| §2.6.1.3 ADMET Screening | Safety profile narrative | total compounds, pass rate, gate types |
| §2.6.1.4 Prioritization | Justify Bayesian lead selection | top score, compound count |
| §2.6.1.5 Applicability Domain | Explain dual-criterion AD methodology | (static — Tropsha/Roy + Tanimoto) |

§2.6.1.6 Audit Trail is template-only (facts, not narrative).

### Token budget fix
Initial `max_tokens=1024` caused PBPK narrative truncation mid-sentence:
> "with 100% of area under the curve (AUC) and 73."

Raised to `max_tokens=2048` — thinking tokens at this model require ~800–1000 tokens of overhead even for 3-sentence tasks.

### Example output (§2.6.1.2 PBPK, ERB-001/EGFR T790M)
> "The physiologically based pharmacokinetic (PBPK) model performance was evaluated against established European Medicines Agency (EMA) criteria, demonstrating that 100.0% of area under the curve (AUC) and 73.3% of maximum concentration (Cmax) predictions fell within the predefined two-fold error threshold. Although the average fold error (AFE) of 0.611 for Cmax suggests a modest trend toward underprediction, the high coefficient of determination (R² = 0.942) and acceptable absolute average fold error (AAFE = 1.893) support the model's overall predictive capacity. Consequently, the model is considered qualified for its intended regulatory purpose within this Investigational New Drug (IND) application to support clinical pharmacology assessments and the characterization of potential drug-drug interactions."

### Full document output
- 10,600–10,800 chars per campaign (varies by LLM generation)
- `pandoc_available: true` — DOCX generated in all tested environments
- Response includes both `markdown_preview` (first 2000 chars) and `markdown_content` (full document)

---

## 3. API Endpoints

### POST `/{campaign_id}/ind-assembly`
**New:** returns `markdown_content` (full document) in addition to `markdown_preview`.  
**Cache:** stores result in `_ind_cache[campaign_id]` for download endpoint.

### GET `/{campaign_id}/ind-assembly/download?format=md|docx`
Serves from in-memory cache. Returns:
- `format=md` → `text/markdown; charset=utf-8` with `Content-Disposition: attachment`
- `format=docx` → `application/vnd.openxmlformats-officedocument.wordprocessingml.document`

Returns 404 if no assembly has been generated yet for the campaign (cache is in-process, does not survive backend restart).

---

## 4. Frontend Component (`drug-discovery-ind-assembly.tsx`)

Changes made in this session and the previous session:

- `SECTION_TITLES` corrected to match backend ICH M4 computational-CRO variant (not generic ICH titles)
- `AssemblyResult` interface: added `markdown_content: string`
- Generate button: shows confirm-overwrite flow when result already exists (was silently no-op)
- `downloadMarkdown()`: uses `result.markdown_content` from state (full document, not truncated preview)
- `downloadDocx()`: fetches `GET /ind-assembly/download?format=docx`

---

## 5. DD-CRO-5 Test Enhancement

`frontend/e2e/drug-discovery-cro-compliance.e2e.ts` — test now asserts:

1. `result.markdown_content` present and `length ≥ markdown_preview.length`
2. All six section headings (`2.6.1.1`–`2.6.1.6`) appear in full document
3. Regulatory prose markers (`investigational`, `IND`, `computational`, `regulatory`) present
4. Download endpoint (`GET /ind-assembly/download?format=md`) returns HTTP 200 with `length > 100`

**Result:** 1 passed (24 s), full document 10,659 chars, pandoc DOCX confirmed.

---

## 6. CRO Tutorial Tour Update

`frontend/client/src/pages/drug-discovery-cro-demo.tsx` — step 7 ("ind-generate") updated:

**Before:**
> "Fill the campaign details, click Generate IND Package, and we assemble the full §2.6.1 Nonclinical Overview — pulling numbers from the validation report, audit chain, and compound rankings — into a signed Markdown + DOCX bundle."

**After:**
> "Fill campaign details, click **Generate IND Package**. BioMate pulls PBPK metrics, ADMET results, compound rankings, and audit records — then a Gemini-powered regulatory writer drafts 2–4 sentences of FDA-style prose for each section. Download the full §2.6.1 Nonclinical Overview as **Markdown + DOCX**, ready to attach to your IND filing."

Final "done" step bullet list updated to mention the IND download action.

---

## 7. Demo 11 — IND §2.6.1 Assembly

**File:** `frontend/e2e/demo-11-ind-assembly.demo.ts`  
**Video:** `frontend/e2e/demo-videos/demo-11-ind-assembly.webm` (9.2 MB, 1.7 min, 2560×1440)

### Story
Computational CRO uses BioMate to generate the CTD §2.6.1 Nonclinical Overview for an EGFR T790M inhibitor (ERB-001) IND submission.

### Screenshots
| Shot | Content |
|---|---|
| `00_cro_loaded` | CRO workspace open, ERB-001 campaign selected |
| `01_ind_tab_open` | IND tab with form and section checklist |
| `02_form_filled` | ERB-001 / EGFR T790M / NSCLC 2nd line / BioMate Technologies |
| `03_generated` | All 6 sections ✓, MD + DOCX download rows, toast "6 sections · MD + DOCX" |
| `04_markdown_preview` | Preview open, showing `# CTD Section 2.6.1 — Nonclinical Overview` |
| `05_api_verified` | API assertions: 10,700+ chars, §2.6.1.1 narrative confirmed non-empty |
| `06_ind_tab_final` / `done` | Final state |

### Assertions
- HTTP 200 from POST `/ind-assembly`
- All 6 sections present in `result.sections`
- `markdown_content.length ≥ 10,000`
- §2.6.1.1 LLM narrative `length > 50` chars
- Download endpoint HTTP 200 + `length > 1000`

### Added to `run-demos.sh` default list
Default `DEMOS=(01 02 04 05 06 11)` — demo 11 runs as part of full demo suite.

---

## 8. Demo 06 Re-recorded

`frontend/e2e/demo-videos/demo-06-cro-compliance.webm` re-recorded (1.6 MB, 3.0 min, 2560×1440) to capture the updated IND tour tip text and the full IND generation flow (form → generate → download).

---

## Key Files Changed

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/drug_discovery/ind_assembly.py` | `_llm_narrative()` added; `max_tokens` raised to 2048 |
| `backend/lib/galaxy/ai/drug_discovery/api_router.py` | `_ind_cache`; `markdown_content` in response; download endpoint |
| `frontend/client/src/components/drug-discovery-ind-assembly.tsx` | `SECTION_TITLES`, generate button, `markdown_content`, download logic |
| `frontend/client/src/pages/drug-discovery-cro-demo.tsx` | Tour step 7 + done step updated |
| `frontend/server/routes.ts` | 3 × `maxTokens` raised to 1024 |
| `frontend/server/galaxy-assistant.ts` | 6 × `maxTokens` raised to 1024 |
| `frontend/e2e/drug-discovery-cro-compliance.e2e.ts` | DD-CRO-5 enhanced with 4 new assertions |
| `frontend/e2e/demo-11-ind-assembly.demo.ts` | New demo file |
| `frontend/e2e/run-demos.sh` | Demo 11 added to default suite |
