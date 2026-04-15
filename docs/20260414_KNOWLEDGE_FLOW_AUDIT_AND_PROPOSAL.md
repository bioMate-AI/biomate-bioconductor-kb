# BioMate Knowledge Flow Audit & Utilization Proposal

**Date:** 2026-04-14  
**Trigger:** User concern that collected DB knowledge does not fully contribute to BioMate's intelligence

---

## Part 1 — What Exists in the DB

| Table | Rows | Content |
|---|---|---|
| `cryo_em_protocols` | 6 | key_principles, qc_gates, reference_papers, reconstitution_params, picking/refinement strategy — per sample class |
| `cryo_em_parameters` | 58 | MW-context pixel_size, defocus, dose, box_size lookup table |
| `cryo_em_tools` | 12 | use_when (JSON), key_parameters, biomate_status, alternatives, gap_notes — per cryo-EM tool |
| `cryo_em_chunks` | 150 | BGE-embedded RAG chunks from 9 publications |
| `tool_knowledge` | 4,117 | use_cases, limitations, recommended_parameters, primary_citation, benchmark_papers — per tool |
| `tools` | 10,229 | scientific_context (best_for, not_suitable, key_parameters, pitfalls, assumptions), structured_citations |
| `workflows` | 2,449 | Full workflow metadata + FTS index |
| `workflow_chains` | 8 | Multi-step pipeline definitions |
| `user_domain_profiles` | 42 | Per-user domain/topic preferences |
| `learned_domain_keywords` | 0 | Schema built, never populated |
| `routing_cache` | 0 | Schema built, never used |
| `tool_usage_patterns` | 0 | Schema built, never written to |
| `workflow_embeddings` | 0 | Schema built, embeddings never generated |

---

## Part 2 — The Actual Information Flow (Corrected Audit)

### Turn Lifecycle

```
User message
    │
    ├─ [galaxy-assistant.ts] processMessage()
    │       ├─ _buildSessionMemoryBlock()       → <session_memory> in system prompt
    │       ├─ _buildCrossSessionContextBlock() → <long_term_memory> in system prompt
    │       ├─ _buildDomainProfileContext()     → domain bias prefix in system prompt
    │       ├─ extractInlineDataWithLLM()       → <pre_satisfied_parameters> in system prompt
    │       ├─ _fetchCryoEmContext()            → <cryo_em_knowledge> in system prompt  [cryo-EM only]
    │       ├─ buildDomainSpecialistBlock()     → <domain_specialist> in system prompt
    │       ├─ buildDomainCatalogBlock()        → <domain_catalog> in system prompt
    │       └─ generateWorkflow() → ai_assistant.py
    │
    ├─ [ai_assistant.py] generate_workflow_unified()
    │       ├─ search_nextflow_workflow()       ← queries workflows + FTS + embeddings
    │       ├─ _build_scientific_rationale()   ← queries tool_knowledge + tools.scientific_context
    │       │       └─ parameter_hints[]        → returned in response dict
    │       ├─ _apply_parameter_hints()         ← uses tool_knowledge.recommended_parameters
    │       │       └─ fills req/opt params     → returned as required_params / optional_params
    │       ├─ _infer_params_from_intent_llm()  → Haiku call, LLM-suggested param values
    │       ├─ _build_knowledge_highlights()    ← queries cryo_em_protocols + tool_knowledge + tools
    │       │       └─ {best_practices, qc_thresholds, literature_guidance}  ← RETURNED BUT NOT USED
    │       ├─ _build_workflow_citations()      ← queries tool_knowledge + hardcoded domain landmarks
    │       │       └─ citations[]              → returned in response dict
    │       └─ _collect_workflow_hardware_requirements() ← queries tools.execution_info
    │               └─ hardware_requirements{}  → returned in response dict
    │
    ├─ [galaxy-assistant.ts] generateResponse()
    │       └─ Claude LLM call with system prompt (blocks above) + user message
    │               → natural language response text
    │
    └─ [frontend] chat-interface.tsx + nextflow-workflow-viewer.tsx
            ├─ scientific_rationale.parameter_hints → rendered as rationale text on each param input  ✅
            ├─ citations                            → rendered in post-execution AI analysis panel  ✅ (partial)
            ├─ prerequisitesValidation              → renders prereq checklist before run  ✅
            ├─ qcDefaults (from /api/qc/profiles)  → QC threshold box with rationale text  ✅ (just fixed)
            └─ knowledge_highlights                 → returned in response, SILENTLY DROPPED  ❌
```

---

## Part 3 — What Is and Is NOT Reaching the LLM

### Confirmed Active (reaches Claude)

| Knowledge Source | Mechanism | Stage |
|---|---|---|
| `cryo_em_protocols` + `cryo_em_parameters` + `cryo_em_chunks` | `/api/cryo_em/context` → `_fetchCryoEmContext()` | System prompt (cryo-EM domain only) |
| `user_domain_profiles` | `_buildDomainProfileContext()` | System prompt prefix |
| Past sessions (chat_messages) | `_buildCrossSessionContextBlock()` | System prompt |
| Inline data in user message | `extractInlineDataWithLLM()` | System prompt |
| `tool_knowledge.recommended_parameters` | `_apply_parameter_hints()` → fills param defaults | Response (param values, not shown to LLM) |
| `tool_knowledge.use_cases` + `tools.scientific_context` | `_build_scientific_rationale()` → parameter_hints | Response → frontend param rationale display |
| Workflow catalog (hardcoded domain blocks) | `buildDomainCatalogBlock()` | System prompt |

### Confirmed Dead (computed but never consumed)

| Knowledge Source | Where Computed | Why It Dies |
|---|---|---|
| `cryo_em_protocols.key_principles` | `_build_knowledge_highlights()` path 1 | Returned in `knowledge_highlights` field; frontend never reads it |
| `cryo_em_protocols.qc_gates` | `_build_knowledge_highlights()` path 1 | Same — silently dropped |
| `cryo_em_tools.use_when` | `_build_knowledge_highlights()` path 2c | Same — silently dropped |
| `tool_knowledge.use_cases` (via kh) | `_build_knowledge_highlights()` path 2a | Same (note: also used correctly via `_build_scientific_rationale`) |
| `tools.scientific_context.best_for` (via kh) | `_build_knowledge_highlights()` path 2b | Same — silently dropped |
| `tool_knowledge.primary_citation` (via kh) | `_build_knowledge_highlights()` path 2a | Same — `citations` return field exists, not rendered pre-execution |
| `tools.execution_info` | `_collect_workflow_hardware_requirements()` | Returned in response; frontend never renders or uses it |
| `learned_domain_keywords` | Never written | 0 rows |
| `routing_cache` | Never written | 0 rows |
| `workflow_embeddings` | Never populated | 0 rows |

### Partially Active

| Knowledge Source | Active Use | Missing Use |
|---|---|---|
| `tool_knowledge` | `_build_scientific_rationale()` → parameter rationale on param inputs | `use_cases` / `limitations` from `knowledge_highlights` never surface |
| `citations` (workflow) | Post-execution AI analysis panel | Pre-execution (after workflow match) citations are returned but never shown |
| `QC_RED_LINES.rationale` | Now shown as small text under threshold values (today's fix) | Previously tooltip-only |

---

## Part 4 — What Is Shocking

**1. The cryo-EM DB path is domain-gated and bypassed for general chat.**  
`_fetchCryoEmContext()` only fires when `isCryoEmDomain=true`. This flag is set based on frontend domain detection. If the user asks a cryo-EM question in a general chat turn where the domain wasn't detected, `cryo_em_protocols` never reaches the LLM.

**2. `_build_knowledge_highlights()` is called on every workflow match but its output goes nowhere.**  
It runs three DB queries (cryo_em_protocols, tool_knowledge, tools), builds a structured response, and it is returned in the API payload. The frontend receives it and discards it. Every call is wasted compute.

**3. `_collect_workflow_hardware_requirements()` is similarly orphaned.**  
`tools.execution_info` is queried, a hardware requirements dict is built, it is returned — and never read by the frontend or used for execution gating.

**4. `cryo_em_tools` (12 rows of tool-specific guidance) has never reached the LLM or UI.**  
It is populated (`use_when`, `key_parameters`, `biomate_status`) and queried by `_build_knowledge_highlights()` path 2c, but the output dies in the same dead field.

**5. The domain-specialist block in the system prompt is hardcoded text, not DB-sourced.**  
`buildDomainSpecialistBlock()` and `buildDomainCatalogBlock()` are static strings written inline in `galaxy-assistant.ts`. They have no connection to the 4,117 rows of structured tool knowledge or the 10,229 rows of scientific context in the DB. They duplicate effort and drift out of sync as the DB grows.

**6. Workflow citations exist pre-execution but are never shown.**  
`_build_workflow_citations()` correctly queries `tool_knowledge` for APA citations. These are returned in the `citations` field. The frontend only renders citations from the *post-execution* AI analysis panel — not from the initial workflow match. A user who doesn't run the workflow never sees the citations.

---

## Part 5 — Proposal: Where Each Knowledge Piece Should Be Injected

### Principle: Match the knowledge to the decision moment

Knowledge has maximum value when it reaches the decision-maker (LLM or user) at the moment it is relevant — not in a panel that appears after the decision is made or in a response field that is silently dropped.

```
Decision moments in a BioMate session:

1. Domain routing       — which domain/workflow family to suggest?
2. Workflow matching     — which specific workflow to return?
3. Parameter filling     — what values to pre-fill?
4. Pre-execution review  — should the user run this? What to check?
5. Execution gating      — should the run proceed given input data quality?
6. Post-execution        — what do the outputs mean?
```

### Injection Map

#### Moment 1: Domain Routing → System Prompt
**Gap:** Domain-specialist block is hardcoded text; DB knowledge not used.  
**Fix:** Replace/augment `buildDomainSpecialistBlock()` with a DB-sourced compact block.  
For each inferred domain, pull top 3 `tool_knowledge.use_cases` for the 2–3 anchor tools of that domain. This keeps the block current as the DB grows.  
**Source:** `tool_knowledge.use_cases` (already has 4,117 rows)  
**Target:** `galaxy-assistant.ts` system prompt, replacing static text  
**Size budget:** ~200 tokens per domain block

#### Moment 2: Workflow Matching → Already Partially Done
**Active:** `_apply_parameter_hints()` uses `tool_knowledge.recommended_parameters` to fill param defaults.  
**Active:** `_build_scientific_rationale()` produces `parameter_hints` shown in UI.  
**Gap:** For non-cryo-EM domains, no equivalent of `_fetchCryoEmContext()` feeds the LLM during the match conversation.  
**Fix:** Build a `_fetchDomainToolContext()` function parallel to `_fetchCryoEmContext()`. For the matched workflow's tools, pull: top use case, top limitation, top parameter hint, primary citation. Inject as `<domain_tool_context>` block before the LLM response. Max 300 tokens.  
**Source:** `tool_knowledge` rows for workflow's `tools_used`  
**Target:** `galaxy-assistant.ts` system prompt (parallel to `cryoEmContextBlock`)

#### Moment 3: Parameter Filling → Already Working
**Active:** `_apply_parameter_hints()` ✅  
**Active:** `scientific_rationale.parameter_hints` rendered in frontend ✅  
**Enhancement:** `tools.scientific_context.key_parameters` — already read in `_build_scientific_rationale()` via `scientific_context.common_errors` and `scientific_assumptions`. No gap here.

#### Moment 4: Pre-Execution Review → Citations Already in Text
**Note:** Pre-execution citations are already in Claude's natural language response — the LLM mentions relevant tools and methods. A separate citations panel duplicates the text reply. No action needed.

For cryo-EM: `cryo_em_protocols.key_principles` are already shown via `/api/cryo_em/context` → LLM. When the LLM writes its response, it has these principles as context and can include them naturally in text. No additional UI panel needed.

#### Moment 5: Execution Gating → QC Thresholds Panel
**Active:** `QC_RED_LINES` rationale now shown as small text under each threshold ✅ (today's fix)  
**Gap:** `cryo_em_protocols.qc_gates` contains domain-specific qualitative gates (NS-EM check, SEC purity) that are not in `QC_RED_LINES`. For cryo-EM workflows, these complement the numeric thresholds.  
**Fix (if desired):** When domain=cryo_em and sample class detected, inject cryo_em_protocols.qc_gates as a read-only "Protocol gates" subsection below the numeric thresholds. These are qualitative checkpoints, not editable numbers.  
**Source:** `cryo_em_protocols.qc_gates`  
**Target:** `nextflow-workflow-viewer.tsx` — below QC threshold inputs, cryo-EM only

#### Moment 6: Post-Execution → Already Working
**Active:** Post-execution AI analysis panel renders citations from AI analysis ✅  
**Enhancement:** `cryo_em_protocols.reference_papers` are already in the LLM's context (via cryoEmContextBlock). The LLM cites them naturally.

---

## Part 6 — Priority Order

| Priority | Gap | Effort | Impact | Status |
|---|---|---|---|---|
| ~~P1~~ | ~~Wire pre-execution citations into panel~~ | — | Citations already in Claude's text reply | Dropped |
| ~~P1~~ | ~~`_fetchDomainToolContext()` for non-cryo-EM~~ | — | Mainstream tools covered by pretraining; cryo-EM injection valuable precisely because protocol specifics are not in pretraining | Dropped |
| P2 | Replace `buildDomainCatalogBlock()` with DB-sourced workflow list | Medium | Catalog stays current as `workflows` table grows; specialist framing (expert decision trees) stays hardcoded — that's editorial, not data | Open |
| P2 | cryo-EM protocol gates as read-only UI subsection | Low | Sample-class-specific qualitative QC visible alongside numeric thresholds | Open |
| P3 | Remove `_build_knowledge_highlights()` dead calls | Low | Done — 3 call sites removed | **Done** |
| P3 | Remove `_collect_workflow_hardware_requirements()` or wire it | Low | Computes hardware hints nobody reads | Open |
| P4 | Populate `workflow_embeddings` for semantic routing | High | Better workflow recall on paraphrase queries | Open |
| P4 | Begin writing `learned_domain_keywords` at runtime | Medium | Self-improving routing over time | Open |

---

## Part 7 — What NOT to Do

- **Do not add a `knowledge_highlights` panel** to the frontend. User explicitly rejected displaying best_practices, qc_thresholds, literature_guidance as a separate panel.
- **Do not inject all DB knowledge into every system prompt.** Context budget matters. Each domain injection should be ≤300 tokens and scoped to matched tools.
- **Do not duplicate what the LLM already knows.** Tools like DESeq2, GATK, Seurat are covered by Claude's pretraining. DB knowledge is most valuable for domain-specific configuration (molar ratios, pixel sizes, GPCR assembly order) that LLMs get wrong or hallucinate.
- **Do not try to fill `learned_domain_keywords` or `routing_cache` proactively.** These should accumulate from real usage. Seed data would be artificial.
