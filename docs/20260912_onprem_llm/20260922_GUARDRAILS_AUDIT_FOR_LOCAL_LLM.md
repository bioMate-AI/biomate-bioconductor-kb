# BioMate Guardrail Audit — backstopping an on-prem Qwen3-4B (2026-09-22)

**Why:** a 4B local model hallucinates, emits malformed JSON, and picks wrong/non-existent tools far
more than a frontier model. BioMate's design principle (`DESIGN_PRINCIPLES.md`) is **"judgment in
weights, mechanism in harness"** — deterministic guardrails live in the harness precisely so a weaker
model can be swapped in. This audits whether the harness guards are complete for a 4B. **Verdict:**
strong in 3 areas (JSON integrity, param-schema, QC gates), real gaps in 3 (multi-step composition
grounding at runtime, run_code on air-gapped boxes, interpretation/diagnosis over-claiming), plus
enforcement-is-env-var-not-runtime.

## A. Guardrail inventory (by area, with file:line)

**1. LLM output JSON validation (local path = strict reject, no repair)**
- `jsonObjectText()` `frontend/server/local-llm.ts:54-67` — rejects non-object/array/commentary/>1
  fence/partial/**non-finite** (NaN/Inf). AFTER, reject.
- finish_reason guard `local-llm.ts:38-43`; `validateToolInput()` `:103-124` (types/enum/range/required);
  tool-call guard `:152-160` (incomplete/dup/unknown tool).
- Python path `backend/lib/galaxy/ai/local_inference.py:60-72` (dict-only, reject non-finite).
- **Repair** path (`jsonrepair`) exists only on the CLOUD intent classifier
  `galaxy-assistant.ts:~7170-7178` — NOT wired for local.

**2. Parameter extraction validation (rule-first + schema guardrail)**
- `_validate_extracted_params()` `backend/.../api/ai_assistant.py:1476-1564` — drop out-of-schema enums,
  normalize genome/strand aliases (AFTER LLM).
- `_rule_based_param_inference()` `:1567-1936` — deterministic units (ns→n_steps, fs→dt), negations,
  single/paired flags (BEFORE LLM, takes priority).
- SMILES/RDKit validation `backend/lib/galaxy/ai/ai_assistant.py:2954-3113` (reject non-molecules).
- Fix-time: `nextflow_parameter_fixer._validate_parameter()` `:445-481`;
  `llm_parameter_generator._validate_parameters()` `:278-330`.
- Trial: `evaluation/local_trial/schema_guard.py:41-68` (int-vs-fraction, FDR>1→/100).

**3. Tool/workflow grounding (is the workflow real?)**
- `parseActions` lock `galaxy-assistant.ts:7252-7287`; `_applyNamedWorkflowOverridesToDecomposition`
  `:3560-3581`.
- `UnifiedWorkflowSearch` retrieval constrains to ~4,200-wf DB + real candidate list
  (`unified_workflow_search.py`; candidates `ai_assistant.py:3430`).
- `workflow_by_name()` `api/ai_assistant.py:6395-6454` → `workflow_not_found`; `_resolve_nextflow_path()`
  `nextflow_executor.py:1497-1586` → 404 if no `.nf`.
- Trial: `eval_removal.py:106` validity_rate (measures hallucinated/removed picks).

**4. QC gates / auto-loop (deterministic, execution-time, LLM-independent — published-standard constants)**
- hERG `admet_autoloop/qc_evaluator.py:505-532`; DILI/BSEP/mito `:585-711`; Ames ICH-M7 `:713-839`;
  CiPA `:301-389`; PopPK `:391-501`; docking `docking_autoloop/qc_evaluator.py:106-170`; cryo-EM.
- Dispatch `autoloop_bridge.py:352-363` (regulatory=guidance vs risk=deterministic remediation).
- 3-layer threshold governance `qc_trace_monitor.py:27-175,888-1388` (clamp/reject user overrides).

**5. Retrieval grounding + anti-confabulation (research path)**
- Live-DB fact injection `research_agent.py:1741-1980`; `_ground_citations()` `:2417-2455`;
  PMID/DOI verify (≥0.85 title match) `literature_clients.py:794-849`; evidence boundary `:2457-2479`.

**6. Safety / egress / RBAC / prompt governance**
- `localOnly()`/`localOffline()` no-cloud-fallback `local-llm.ts:1-19,29` (env-gated `BIOMATE_LOCAL_ONLY`);
  `textBlocks()` non-text reject `:69-76`; `safety-guardrails.ts:41-217` (PHI/blocklist/injection);
  `execution-intent-guard.ts:10-37`; RBAC `project-routes.ts:81-112`, `output-access.ts:102-126`.
- Prompt registry (SHA256, ~9,600) inventory-only — no runtime digest enforcement.

## B. Coverage map — per 4B failure mode
| Failure mode | Status | Backstop |
|---|---|---|
| Malformed/partial/non-finite JSON | COVERED (strong) | `jsonObjectText` + `local_inference` reject-no-repair |
| Off-schema tool args | COVERED (strong) | `validateToolInput` |
| Hallucinated workflow name | COVERED (strong) | retrieval candidates + `workflow_by_name` + `_resolve_nextflow_path` |
| Out-of-schema params | COVERED (strong) | `_validate_extracted_params` + rule inference + SMILES |
| Wrong intent | COVERED (medium) | `parseActions` lock, clarification gate, exec-intent guard (curated regex/overrides) |
| Confabulation (citations) | COVERED (strong, research only) | `_ground_citations`, PMID verify, evidence boundary |
| **Ungrounded composition (multi-step DAG)** | **GAP** | only in eval harness; no runtime grounding/dataflow/bio-validity gate |
| **run_code on air-gapped box** | **GAP** | `run_code` not gated by `localOnly` |
| **Over-claiming in interpretation/diagnosis** | **GAP** | no verifier/confidence gate (unlike research citations) |
| Unsafe/egress | COVERED (medium) | env-var discipline, not runtime lock |
| Image input to text-only 4B | GAP (partial) | `textBlocks` hard-errors instead of degrading |

## C. Top gaps a 4B exposes (ranked) — where the frontier was doing the guard's job
1. **No production output-VerificationLayer for composition/DAG grounding.** Strong guards fire on
   *single* selections; multi-step DECOMPOSITION (a core target task) has no runtime check that each
   step names a real candidate, dataflow types match, or ordering is bio-valid (e.g. CPM-normalize
   before DESeq2). Logic exists only in eval (`eval_removal.py`, `eval_grounded.py` neg_penalty) — and
   COMMITTEE_AUDIT_V4 shows even that metric needed fixing. **Fix: promote the grounded+neg-penalty
   checks into a runtime gate.** (#1)
2. **run_code not gated on the local/offline path** (`galaxy-assistant.ts:2873`). 4B far likelier to
   emit wrong/egress-capable code; no sandbox/allowlist. **Fix: stub/sandbox run_code when
   `BIOMATE_LOCAL_ONLY=1`.**
3. **Interpretation + error-diagnosis have no anti-confab guard** (citation-grounding is research-only).
   Two of six target tasks produce free-text with no verifier/confidence/"not-demonstrated" fallback.
   **Fix: extend evidence-boundary/confidence pattern, keyed to whether real run artifacts were read.**
4. **Egress + prompt-version enforcement rely on operator env-vars, not runtime locks** (Tier-0
   governance gap; load-bearing once the model can't be trusted to refuse).
5. **Image handling on local path errors instead of degrading** (`textBlocks` throws; low severity).

**Net:** JSON integrity, param-schema conformance, workflow-existence, and the deterministic QC/auto-loop
are production-grade and model-agnostic — they backstop a 4B well. Exposure is concentrated in
**composition grounding, run_code gating, interpretation/diagnosis over-claiming, and runtime
enforcement of egress/prompt governance** — the judgment-heavy surfaces the frontier model was covering.
