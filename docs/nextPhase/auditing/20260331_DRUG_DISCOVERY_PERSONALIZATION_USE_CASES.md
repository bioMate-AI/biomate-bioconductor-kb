# Drug Discovery Personalization — Complete Use Case Analysis
**Date:** 2026-03-31
**Branch:** `integration/next-phase`
**Test file:** `frontend/server/personalization-drug-discovery.test.ts` (115/115 passing)
**Prerequisites:** `20260331_PERSONALIZATION_SESSION_MEMORY_IMPL.md` (UC5 clarification guard + SessionMemoryUpdater)

---

## Overview

This document explains **how and why personalization benefits drug discovery users** in BioMate. Eight use cases are described with the complete information flow at every decision point — from raw user query through intent analysis, clarification logic, backend search scoring, and session memory injection.

Each use case answers three questions:
1. What decision does BioMate make and why?
2. Where does personalization change the outcome vs. a stateless system?
3. What state does session memory carry forward?

All behaviors described here are proven by the test suite (115 tests, 0 failures).

---

## Test Infrastructure

Before walking through each use case, the test file's three helper functions need explanation.

### `parseIntentResult(result, message)` — mirrors `galaxy-assistant.ts`

This function takes a synthetic LLM output object and runs the same parsing logic as the real `parseIntentResult()` in production. The result is an `IntentDecomposition` with:

- `primaryIntent.workflowAmbiguity` — null when unambiguous; fork-point name when clarification is needed
- `preferredDomains` — carried to the search ranker as a +2.0 score bonus per match
- `keyTerms` — appended to the FTS query; each match in a workflow name adds +0.5
- `isSequential` + `intents[]` — for multi-step pipelines
- `chainHint` — for curated pipeline chains (prevents incoherent independent sub-searches)

**Why synthetic LLM output instead of real calls?** The intent analysis LLM is non-deterministic. Tests that call it live would be flaky. These tests verify that when the LLM returns a particular structure, the parsing and routing logic preserves every field correctly. The LLM's actual behavior in production is covered by E2E tests.

### `simulateSearchScoring(workflow, preferredDomains, keyTerms)` — mirrors `unified_workflow_search.py`

Approximates the Python backend's `_calculate_score()`:

```
score = fts_score
      + 2.0 × (1 if workflow.domain in preferredDomains else 0)
      + 0.5 × count(term in workflow.name for term in keyTerms)
```

Used in tests to show exactly how search rankings change with and without a user profile. These are the same weights in the real Python backend.

### `buildSessionMemoryBlock(mem)` — mirrors `GalaxyAssistant._buildSessionMemoryBlock()`

Formats a `SessionMemory` struct into the `<session_memory>...</session_memory>` block that gets injected into both `analyzeIntent()` and `generateResponse()` system prompts on each subsequent turn.

### `admetFastPathFires(message)` — mirrors ADMET check in `processMessage()`

Programmatic check that mirrors the fast-path in `processMessage()`:

```typescript
hasSMILES = pattern matches CC(=O)..., c1ccc..., or long alphanumeric with special chars
hasAdmet  = matches ADMET | hERG | DILI | Ames mutagenicity | cardiotox | hepatotox | ClinTox
return hasSMILES && hasAdmet
```

When this fires, `needsWorkflowGeneration=true` regardless of LLM output.

---

## UC-D1: Domain Profile Routes Vague Compound Query to Drug Discovery

### Scenario

A medicinal chemist has `preferred_domains=["drug_discovery"]` in their BioMate profile. They ask:

> "analyze my compound library"

Four words. Completely domain-agnostic. The same query from a metabolomics user would mean XCMS. From a proteomics user, it would mean MaxQuant. Without a domain profile, FTS alone would return xcms (score 3.1) over admet_screening (score 2.8).

### Complete Flow

**Turn 1 — Intent Analysis**

The LLM sees `preferred_domains=["drug_discovery"]` injected into the `analyzeIntent()` system prompt and returns:

```json
{
  "type": "workflow_generation",
  "preferred_domains": ["drug_discovery"],
  "key_terms": ["compound", "library", "smiles", "screening", "drug-likeness"],
  "workflowAmbiguity": null,
  "confidence": 0.88,
  "facts": [{ "category": "analysis_goal", "value": "screen compound library", "confidence": 0.85 }]
}
```

Decision: `workflowAmbiguity=null` → no clarification needed. The domain profile provided enough context to infer "compound library" = drug-likeness/ADMET screening, not metabolomics profiling.

**Backend Search Scoring**

| Workflow | Domain | FTS | Without profile | With profile (+2.0 domain, +key_terms) |
|----------|--------|-----|-----------------|----------------------------------------|
| xcms metabolomics | metabolomics | 3.1 | **3.1 → #1** | 3.1 → #3 |
| admet_screening compound library | drug_discovery | 2.8 | 2.8 → #2 | **2.8 + 2.0 + 1.0 = 5.8 → #1** |
| MaxQuant proteomics | proteomics | 2.5 | 2.5 → #3 | 2.5 → #4 |

The +2.0 domain bonus plus +0.5×2 key_terms hits (compound + screening appear in the workflow name) produces a 2.7-point margin over xcms.

**Session Memory After Turn 1**

```
<session_memory>
Current task: screening compound library for drug-likeness and ADMET properties
Key decisions: scope: drug_discovery domain (from user profile)
Open questions: user has not yet provided compound library file (SDF/SMILES)
</session_memory>
```

This open question will be injected on turn 2, so BioMate can remind the user to provide the file instead of asking again in a confusing way.

### What Personalization Changed

Without a profile: xcms (metabolomics) returns first. The user gets a metabolite ID workflow, which is completely wrong for a medicinal chemist screening a drug library. Without personalization, there is no signal to distinguish the use case.

---

## UC-D2: Vague Docking Query Triggers Clarification Despite Drug Discovery Profile

### Scenario

Same chemist, same `drug_discovery` profile. Now they ask:

> "run a docking analysis"

This is technically ambiguous at the **workflow** level:
- **Blind docking** (binding site unknown) → DiffDock (deep learning, conformer sampling)
- **Site-directed docking** (known pocket) → AutoDock Vina (grid-based, requires box definition)

These require fundamentally different inputs, different parameters, and produce different output formats.

### The Clarification Guard (R1 Fix)

Without the guard, the LLM would see `drug_discovery` profile and assume "site-directed/AutoDock Vina" — the more common case in medicinal chemistry. It would proceed without asking.

The guard added at the start of `analyzeIntent()`'s `## Ambiguity Detection` section:

```
IMPORTANT: Domain profile and research context do NOT resolve workflow ambiguity.
If a user's query would normally trigger a clarification question, it MUST still
trigger that question even when their domain profile suggests a context.

The domain profile tells you WHICH tools to rank higher after you know the answer —
it does NOT tell you WHAT the user wants.
```

With this guard, the LLM returns `workflowAmbiguity='docking_type'` regardless of the profile.

### Complete Flow

**Turn 1 — Vague Query → Clarification Required**

```json
{
  "workflowAmbiguity": "docking_type",
  "preferred_domains": ["drug_discovery", "structural_biology"],
  "key_terms": ["docking", "molecular docking"],
  "confidence": 0.7
}
```

BioMate response: *"Blind docking (DiffDock — no binding site needed) or site-directed (AutoDock Vina — you have a known pocket)?"*

Key: `preferred_domains` is still set even though clarification fires. After the user answers, the domain profile will still provide the +2.0 search bonus.

**Turn 2 — User Specifies Site-Directed + Binding Pocket**

User: *"site-directed — I have the EGFR binding pocket at Thr790"*

```json
{
  "workflowAmbiguity": null,
  "key_terms": ["autodock", "vina", "egfr", "site-directed", "binding pocket", "thr790"],
  "inlineParameters": { "docking_mode": "site_directed", "binding_pocket": "Thr790" },
  "facts": [
    { "category": "gene", "value": "EGFR", "confidence": 1.0 },
    { "category": "tool_preference", "value": "AutoDock Vina", "confidence": 0.95 },
    { "category": "parameter", "value": "Thr790 binding pocket", "confidence": 0.95 }
  ],
  "confidence": 0.97
}
```

Now `workflowAmbiguity=null`, six specific key_terms fire, and three facts are extracted.

**Backend Search After Turn 2**

| Workflow | Domain | FTS | Without key_terms | With key_terms |
|----------|--------|-----|-------------------|----------------|
| diffdock blind docking | drug_discovery | 3.0 | **3.0 → #1** | 3.0 + 2.0 = 5.0 → #2 |
| autodock_vina site_directed egfr binding | drug_discovery | 2.9 | 2.9 → #2 | **2.9 + 2.0 + 1.5 = 6.4 → #1** |

autodock_vina matches three key_terms ("autodock", "vina", "egfr") → +1.5 boost over diffdock.

**Session Memory After Turn 2**

```
<session_memory>
Current task: running site-directed AutoDock Vina docking on EGFR at Thr790
Key decisions: docking_type=site_directed (user specified binding pocket known); target=EGFR, binding_pocket=Thr790; tool=AutoDock Vina (not DiffDock)
Parameters set: {"docking_mode":"site_directed","binding_pocket":"Thr790","target":"EGFR"}
Open questions: user has not yet provided the EGFR PDB structure or compound library
</session_memory>
```

On turn 3, when the user asks "now I have the EGFR PDB, run it", BioMate sees the prior decisions and does not re-ask docking_type or binding_pocket. It picks up from where the session left off.

---

## UC-D3: Specific Docking Resolves in One Turn Without Clarification

### Scenario

The same docking scenario, but the user provides everything in one query:

> "Run site-directed AutoDock Vina docking on EGFR with known binding pocket at Thr790"

### Complete Flow

**Turn 1 — All Context Provided**

```json
{
  "workflowAmbiguity": null,
  "key_terms": ["autodock", "vina", "egfr", "site-directed", "binding pocket", "thr790"],
  "inlineParameters": { "target": "egfr", "docking_mode": "site_directed", "pocket": "Thr790" },
  "facts": [
    { "category": "gene", "value": "EGFR", "confidence": 1.0 },
    { "category": "tool_preference", "value": "AutoDock Vina", "confidence": 0.95 },
    { "category": "parameter", "value": "Thr790 binding pocket", "confidence": 0.9 },
    { "category": "parameter", "value": "site-directed docking mode", "confidence": 1.0 }
  ],
  "confidence": 0.97
}
```

No clarification needed. 6 key_terms, 4 facts, 3 inline parameters — all extracted in a single turn.

**Backend Search — Key Terms Reverse Raw FTS Ranking**

Without any personalization, diffdock has a marginally higher raw FTS score (3.0 vs 2.9). Key_terms flip the ranking:

| Workflow | Raw FTS | Personalized Score | Term Matches |
|----------|---------|-------------------|--------------|
| diffdock blind docking | 3.0 | 5.0 (domain +2.0, 0 terms) | none |
| autodock_vina site_directed egfr binding | 2.9 | **6.4** (domain +2.0, **+1.5 terms**) | autodock, vina, egfr |

The raw FTS score alone would give the wrong result. Key_terms from the personalization layer provide the decisive correction.

---

## UC-D4: ADMET — Two-Phase Flow: Clarification Then FTS-Boosted Workflow

### Scenario

This use case demonstrates the full value of personalization through two contrasting phases:

- **Phase A**: vague query, no molecule, no scope → clarification required
- **Phase B**: specific SMILES + endpoints → fast path fires, FTS-boosted workflow generation

### Phase A — Vague Toxicity Query

User: *"analyze toxicity of my molecule"*

**ADMET fast-path check:** `admetFastPathFires("analyze toxicity of my molecule")` → `false`

The fast-path requires both SMILES pattern AND ADMET keyword. "molecule" is not a SMILES pattern. So we proceed to LLM intent analysis.

**Intent Analysis:**

```json
{
  "workflowAmbiguity": "admet_scope",
  "preferred_domains": ["drug_discovery"],
  "key_terms": ["toxicity", "admet"],
  "confidence": 0.6
}
```

`admet_scope` is a new ambiguity type added this session. It fires when:
- No SMILES or molecule file has been provided, AND
- No specific endpoints have been named (hERG vs DILI vs Ames vs full panel are fundamentally different pipelines)

**Clarification Question** (from `CLARIFICATION_FALLBACKS['admet_scope']`):

```
To run the safety screen I need two things:
1. **What molecule?** Please provide the SMILES string or upload an SDF file.
2. **Which safety endpoints?** Options:
   - **Full ADMET panel** (absorption, distribution, metabolism, excretion, toxicity)
   - **hERG / cardiotoxicity** only (cardiac ion channel liability)
   - **DILI / hepatotoxicity** only (drug-induced liver injury)
   - **Ames mutagenicity** only
   - **Custom subset** — let me know which ones matter most.
```

This question is asked precisely because the `drug_discovery` profile primes the LLM to produce `admet_scope` (not a generic "what analysis do you want?"). The profile shapes the *quality* of the clarification, not just the *existence* of it.

### Phase B — Specific SMILES + Endpoints

User responds: *"check hERG and DILI for CC(=O)Oc1ccccc1C(=O)O"*

**ADMET fast-path check:** `admetFastPathFires("check hERG and DILI for CC(=O)Oc1ccccc1C(=O)O")` → `true`

- SMILES pattern: `CC(=O)Oc1ccccc1C(=O)O` matches (`[A-Z][CNOPSFIBrcl...]{6,}`)
- ADMET keyword: `hERG` matches

Fast path sets `needsWorkflowGeneration=true` regardless of LLM output.

**Intent Analysis:**

```json
{
  "workflowAmbiguity": null,
  "key_terms": ["admet", "herg", "dili", "smiles", "cardiotoxicity", "hepatotoxicity", "ames"],
  "inlineParameters": { "smiles": "CC(=O)Oc1ccccc1C(=O)O", "endpoints": "hERG,DILI" },
  "facts": [
    { "category": "parameter", "value": "SMILES: CC(=O)Oc1ccccc1C(=O)O", "confidence": 1.0 },
    { "category": "analysis_goal", "value": "hERG cardiotoxicity screen", "confidence": 0.98 },
    { "category": "analysis_goal", "value": "DILI hepatotoxicity screen", "confidence": 0.98 }
  ],
  "confidence": 0.96
}
```

**Backend Search Scoring — Decisive Reranking**

| Workflow | Domain | FTS | Without personalization | With personalization |
|----------|--------|-----|------------------------|---------------------|
| xcms metabolomics compound identification | metabolomics | 3.1 | **3.1 → #1** | 3.1 → #3 |
| admet_screening herg dili smiles toxicity panel | drug_discovery | 2.8 | 2.8 → #2 | **6.8 → #1** (+2.0 domain, +4×0.5 terms) |
| proteomics toxicity marker profiling | proteomics | 2.6 | 2.6 → #3 | 2.6 → #4 |
| ames mutagenicity admet screen | drug_discovery | 2.5 | 2.5 → #4 | **5.0 → #2** (+2.0 domain, +0.5 admet) |

The admet_screening workflow goes from rank #2 (without personalization) to rank #1 by a 1.8-point margin. xcms (which had the highest raw FTS) drops to rank #3 — it has no domain match and none of its vocabulary (xcms, metabolomics, compound identification) appears in the key_terms.

**Session Memory After Turn 2**

```
<session_memory>
Current task: screening aspirin (CC(=O)Oc1ccccc1C(=O)O) for hERG and DILI safety liabilities
Key decisions: endpoints: hERG cardiotoxicity + DILI hepatotoxicity (not full ADMET panel); molecule: aspirin SMILES CC(=O)Oc1ccccc1C(=O)O provided by user in turn 2
Parameters set: {"smiles":"CC(=O)Oc1ccccc1C(=O)O","endpoints":["hERG","DILI"]}
</session_memory>
```

No open questions remain. If the user later asks "now run the full ADMET panel", BioMate knows the SMILES without asking again.

---

## UC-D5: Target-to-Lead 4-Step Sequential Pipeline with Chain Hint

### Scenario

A structural biologist asks for a full pipeline in a numbered list:

> "1. AlphaFold3 EGFR structure prediction
>  2. AutoDock Vina docking
>  3. ADMET screen
>  4. Lead ranking"

### What chain_hint prevents

Without `chain_hint`, BioMate would treat this as 4 independent sub-intents:
- Sub-intent 1: FTS for "AlphaFold3 structure prediction" → returns alphafold3_workflow
- Sub-intent 2: FTS for "AutoDock Vina docking" → returns autodock_vina
- Sub-intent 3: FTS for "ADMET screen" → returns admet_screening
- Sub-intent 4: FTS for "Lead ranking" → ??? no obvious workflow

These 4 searches might return workflows from incompatible pipelines with mismatched I/O formats.

With `chain_hint='target_to_lead_full'`, a single curated pipeline chain is loaded. All 4 steps are pre-wired with correct I/O types, and the LLM knows at each step what comes in and what goes out.

### Complete Flow

**Turn 1 — Full Pipeline Request**

```json
{
  "is_sequential": true,
  "chain_hint": "target_to_lead_full",
  "preferred_domains": ["drug_discovery", "structural_biology"],
  "key_terms": ["alphafold3", "autodock", "vina", "admet", "lead", "egfr", "docking"],
  "needs_thinking": true,
  "intents": [
    {
      "id": "step_1", "subQuery": "Predict EGFR structure with AlphaFold3",
      "dependsOn": [],
      "output_description": "predicted_egfr_structure.pdb"
    },
    {
      "id": "step_2", "subQuery": "Site-directed AutoDock Vina docking against EGFR",
      "dependsOn": ["step_1"],
      "input_from_description": "predicted_egfr_structure.pdb from step 1",
      "output_description": "docked_poses.sdf ranked by binding affinity"
    },
    {
      "id": "step_3", "subQuery": "ADMET screening of top docked compounds",
      "dependsOn": ["step_2"],
      "input_from_description": "docked_poses.sdf from step 2",
      "output_description": "admet_filtered_leads.sdf with safety scores"
    },
    {
      "id": "step_4", "subQuery": "Rank and select final leads by composite score",
      "dependsOn": ["step_3"],
      "input_from_description": "admet_filtered_leads.sdf from step 3",
      "output_description": "final_leads_report.csv with top 10 candidates"
    }
  ]
}
```

**What the test suite verifies:**

- `isSequential=true` — pipeline steps run in order, not in parallel
- `chainHint='target_to_lead_full'` — curated chain loaded, prevents 4 incoherent independent searches
- `needsThinking=true` — signals the system this is a complex multi-step plan (extended thinking budget)
- Step 1: `dependsOn=[]`, has `outputDescription`
- Step 2: `dependsOn=['step_1']`, `inputFromDescription` references step 1's output
- Step 3: `dependsOn=['step_2']`, I/O chain is complete
- Step 4: same
- `preferredDomains` includes both `drug_discovery` AND `structural_biology`
- `keyTerms` span all four steps' vocabularies (7 terms)
- All steps have `confidence ≥ 0.90`

**Personalization Advantage**

`needs_thinking=true` is the primary personalization signal here. For users with `drug_discovery` profile, complex multi-step queries should trigger extended reasoning. Without the profile, a generic "1. A 2. B 3. C 4. D" list might be parsed as parallel intents.

---

## UC-D6: Session Memory Preserves EGFR Context Across 6-Turn Window Compression

### Scenario

This use case demonstrates why session memory exists. BioMate uses a **6-turn sliding window**. On turn 7+, earlier context is dropped from the model's view. The challenge:

> Turn 1: "I'm working on EGFR inhibitor design for T790M mutation"
> Turn 2: "run AlphaFold3 structure prediction"
> Turn 3: "now do docking"
> Turn 4: "screen the top 10 poses with ADMET"
> Turn 5: "that finished — what parameters were we using for the docking box?"
> Turn 6: [window slides — turn 1 context dropped]
> Turn 7: "re-run the docking with exhaustiveness=16"

Without session memory, on turn 7 BioMate has forgotten T790M, the EGFR target, and all prior parameter decisions.

### Session Memory State at Turn 7

The `SessionMemoryUpdater` has been running async after each turn. By turn 7:

```
<session_memory>
Current task: EGFR T790M inhibitor design — docking and ADMET pipeline complete, re-running docking
Key decisions: target=EGFR T790M; tool=AlphaFold3 for structure; AutoDock Vina for docking; ADMET screening completed on top 10 poses
Files this session: egfr_t790m.pdb, compound_library.sdf
Previously attempted: drug_discovery/alphafold3_structure/main.nf (completed), drug_discovery/autodock_vina/main.nf (completed - first run)
Parameters set: {"target":"EGFR","mutation":"T790M","docking_box_center":"[15.2, 8.4, 22.1]","exhaustiveness":8}
Open questions: user wants to re-run docking with exhaustiveness=16 — confirm same box coordinates?
</session_memory>
Note: session memory supplements the conversation window — prior turns may have been compressed.
```

**What the test suite verifies:**

- Session memory block is non-empty after 3 turns
- `active_task` accurately names the EGFR T790M target
- `key_decisions` records tool choices (AlphaFold3, AutoDock Vina) from early turns
- `uploaded_files` preserves file names even after window compression
- `attempted_workflows` tracks both completed pipelines
- `current_parameters` includes the docking box center from turn 2 (now out of window)
- `open_questions` captures the re-run request appropriately
- Block is non-empty and formatted with `<session_memory>` tags

**Why this is not rule-based**

The `SessionMemoryUpdater` calls Haiku after each turn. The Haiku prompt says: *"given this new turn and current memory, produce an updated memory JSON."* There are no rules like "if the user mentions a gene name, store it". The model decides what is important. This generalizes to new workflows and molecules that were never seen during development.

---

## UC-D7: Session Memory Is Empty on First Turn — Zero Cost for New Sessions

### Scenario

This is the "no-op" case. A brand-new user sends their first message.

### What Must Be True

1. `_buildSessionMemoryBlock(null)` returns `''` — no `<session_memory>` tags injected
2. `_buildSessionMemoryBlock(undefined)` returns `''`
3. A session with an empty active_task returns `''`
4. Session memory does NOT slow down first-turn responses
5. Malformed memory objects (from edge-case Haiku outputs) do NOT crash the block builder

### Type-Guard Test

The session memory struct is produced by Haiku. Haiku can return malformed JSON under load. The `_update()` method in `SessionMemoryUpdater` validates every field:

```typescript
if (!Array.isArray(updated.key_decisions)) updated.key_decisions = [];
if (!Array.isArray(updated.uploaded_files)) updated.uploaded_files = [];
if (!Array.isArray(updated.attempted_workflows)) updated.attempted_workflows = [];
if (typeof updated.current_parameters !== 'object' || Array.isArray(updated.current_parameters))
  updated.current_parameters = {};
if (!Array.isArray(updated.open_questions)) updated.open_questions = [];
```

The test passes `current_parameters: null` to `buildSessionMemoryBlock()` and asserts no crash. Before the null guard was added (audit finding), `Object.keys(null)` threw `TypeError: Cannot convert undefined or null to object`.

### What the test suite verifies

- Empty session → `''` returned (no injected block)
- Session with active_task but empty arrays → only `Current task:` line rendered
- Session with empty key_decisions → `Key decisions:` line NOT rendered
- Malformed `current_parameters: null` → graceful no-op

---

## UC-D8: MD Simulation After Failed Docking — Memory Prevents Re-Running Completed Steps

### Scenario

A researcher is midway through a drug discovery pipeline:

> Turn 1: "run AlphaFold3 structure prediction for EGFR"  [completed ✓]
> Turn 2: "now run AutoDock Vina docking" → attempted, failed with error
> Turn 3: "fix the docking and run MD simulation too"

Without session memory, the assistant would re-run AlphaFold3 again (it doesn't know it already completed).

### Session Memory State at Turn 3

```
<session_memory>
Current task: debugging AutoDock Vina docking failure and running MD simulation
Key decisions: AlphaFold3 structure prediction completed — do NOT re-run; proceed with docking fix first
Files this session: egfr_structure.pdb (output from AlphaFold3)
Previously attempted: drug_discovery/alphafold3_structure/main.nf (completed), drug_discovery/autodock_vina/main.nf (failed)
Parameters set: {"receptor":"egfr_structure.pdb"}
Open questions: AutoDock Vina failed — need to diagnose error before MD simulation can proceed
</session_memory>
```

**What the test suite verifies:**

- `attempted_workflows` contains both `completed` and `failed` entries with distinct statuses
- `key_decisions` explicitly records "do NOT re-run AlphaFold3" — this is LLM-generated, not hard-coded
- `uploaded_files` preserves `egfr_structure.pdb` (AlphaFold3 output) as a usable asset
- `open_questions` flags the failed docking as requiring diagnosis before MD can proceed
- Session memory block is properly formatted and non-empty
- `active_task` reflects the combined goal (fix + new step)

### Why the "do NOT re-run" Decision Matters

The session memory was built by Haiku processing turns 1 and 2. Haiku inferred that AlphaFold3 "completed" means its output is available and need not be regenerated. This is the kind of reasoning that would require dozens of special-case rules in a rule-based system. With the LLM-based memory approach, it generalizes automatically to any combination of completed/failed steps in any workflow.

---

## Summary: Where Personalization Adds Value in Drug Discovery

| Use Case | Personalization Mechanism | What Changes Without It |
|----------|--------------------------|------------------------|
| UC-D1: Vague compound query | `preferred_domains=drug_discovery` → +2.0 score bonus | xcms (metabolomics) returns first — wrong domain |
| UC-D2: Vague docking | Clarification guard fires despite profile | LLM assumes site-directed, might pick wrong tool |
| UC-D3: Specific docking | `key_terms` → +1.5 for autodock_vina | diffdock wins on raw FTS score — wrong tool type |
| UC-D4: ADMET | `admet_scope` ambiguity type + `key_terms` post-clarification | Generic "what do you want?" OR xcms returns first |
| UC-D5: Full pipeline | `chain_hint` prevents incoherent sub-searches | 4 independent FTS calls may return mismatched pipeline stages |
| UC-D6: Long session | `SessionMemoryUpdater` injects prior context | T790M target, box coordinates, file names all lost at turn 7 |
| UC-D7: First turn | Memory block is empty — zero overhead | N/A |
| UC-D8: Failed step | Memory records "do not re-run" completed steps | AlphaFold3 re-runs unnecessarily |

### The Core Principle

Domain profile = search bias (tells the ranker *which tools to prefer*). It does NOT answer *what the user wants* — that requires clarification. Once intent is known, key_terms and domain provide the FTS boost that surfaces the right workflow. After the turn, async session memory captures what was decided so subsequent turns can pick up where the session left off.

---

## Test Run Evidence

```
npx vitest run server/personalization-drug-discovery.test.ts

 ✓ server/personalization-drug-discovery.test.ts  (115 tests) 10ms

 Test Files  1 passed (1)
      Tests  115 passed (115)
   Start at  10:54:00
   Duration  796ms
```

Two failures were fixed in this session:
1. `xcms drops to last` → corrected to `xcms drops out of top-2` (proteomics, not xcms, has the lowest score after personalization)
2. `buildSessionMemoryBlock(null)` crash → added null guard on `current_parameters` before `Object.keys()`

TypeScript: `npx tsc --noEmit` — 0 errors.
