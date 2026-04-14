# Sequential Pipeline Architecture Redesign
**Date:** 2026-04-03
**Branch:** integration/next-phase
**Status:** Planning

---

## 1. Problem Statement

### The Core Bug

When a user says *"build a pharmacophore model from ABL1 inhibitors and screen a compound library against it"*, BioMate currently:

1. Classifies the query as `isSequential=true` with 2 intents: `["build model", "screen library"]`
2. Resolves each intent **independently and in parallel** to a Nextflow workflow
3. Both resolve to `pharmacophore_filtering/main.nf` (it handles both internally)
4. Submits a 2-step chain calling the **same workflow twice**
5. First step runs → outputs nothing useful → second step fails with no input

The LLM classification is **semantically correct** — "build X then use X as input to Y" IS sequential. But the resolution is wrong because it doesn't know that `pharmacophore_filtering` is a single workflow that handles both steps internally.

### Why This Generalises

Many multi-step workflow descriptions map to single Nextflow pipelines:

| User describes | Appears sequential | Actually |
|---|---|---|
| "QC reads, then trim adapters, then align to hg38" | 3 steps | `nf-core/rnaseq` (8 internal steps) |
| "Build pharmacophore model then screen library" | 2 steps | `pharmacophore_filtering` (3 internal steps) |
| "Call variants then annotate with VEP" | 2 steps | `nf-core/sarek` + `vep_annotation` (curated chain) |
| "Run ADMET then dock survivors" | 2 steps | `drug_discovery_admet_gated_screening` (curated chain id=7) |
| "QC reads → align → count → DE → pathway" | 5 steps | `bulk_rnaseq_de_analysis` (curated chain id=2) |

The current code has no way to distinguish "this is all one workflow internally" from "these are genuinely separate workflows to chain". It goes straight to dynamic chain decomposition every time.

### Critical Distinction: Three Levels of Granularity

The system conflates three distinct levels, which is the source of the confusion:

| Level | Definition | Example |
|---|---|---|
| **Biological logical step** | A subtask in the scientific process as the user understands it | "build pharmacophore model", "screen library", "call variants" |
| **Workflow** | A complete Nextflow pipeline that implements one OR MORE biological logical steps via tool-functions | `pharmacophore_filtering` (implements both "build model" and "screen library") |
| **Tool-function step** | A single `process` block in Nextflow; calls one tool | `PHARMACOPHORE_GENERATE`, `PHARMACOPHORE_SCREEN`, `PHARMACOPHORE_REPORT` |

The chain level operates at **workflow level** (Level 2), not tool-function level (Level 3).
The user's query describes at **biological logical step level** (Level 1).
The DB `step_count` counts **tool-function steps** (Level 3) — it is NOT the number of biological logical steps.

**Consequence for `step_count`:** A workflow with `step_count=8` (nf-core/rnaseq has 8 tool-functions: FastQC, TrimGalore, STAR, RSEM, Salmon, featureCounts, MultiQC, custom scripts) still covers ONE biological logical step: "align and quantify RNA-seq reads". A workflow with `step_count=3` (pharmacophore_filtering: GENERATE, SCREEN, REPORT) covers TWO biological logical steps: "build model" and "screen library". The `step_count` field is **not usable** to determine how many biological logical steps a workflow covers.

**The right signals for coverage check:**
- `description` — natural language that describes what the workflow achieves at the biological level. This IS comparable to the user's logical steps.
- `input_types` / `output_types` — the data flow boundary. What does the user need to provide? What does the workflow produce? If the input matches what the user has and the output covers what the user wants at the end, the workflow covers the logical task.

**For Tier 3 (greedy chain building):** Each "step" in the chain is one **workflow execution**, which internally contains many tool-function steps. When we match the user's biological logical steps to workflows, we are doing N-logical-steps → M-workflows mapping (M ≤ N typically, since one workflow can cover multiple logical steps).

---

## 2. Design Principles

### Principle 1: Prefer the fewest workflow executions that cover the task

> Single workflow → curated chain → greedy dynamic chain.

This mirrors how an expert bioinformatician thinks:
1. Do I know a single tool that does this end-to-end? Use it.
2. Do I know a pre-validated pipeline that covers exactly this workflow? Use it.
3. Otherwise, build dynamically: start with the best first tool, then find what covers the rest.

### Principle 2: Human is always in the loop — ask when uncertain

The system does not need to make every routing decision autonomously. When the LLM is uncertain about whether a single workflow covers all the user's steps, or uncertain about which chain best fits the request, it should **ask for confirmation** rather than guess wrong.

This is consistent with BioMate's existing clarification pattern (ONE-QUESTION RULE).

**Confidence tiers:**

| LLM coverage confidence | Action |
|---|---|
| High (≥ 0.85) | Auto-route silently — show workflow/chain card directly |
| Medium (0.5–0.85) | Show proposed routing AND ask user to confirm: *"I believe pharmacophore_filtering handles both your model generation and library screening in one run. Does that work, or would you prefer a two-step pipeline?"* |
| Low (< 0.5) | Ask for clarification before generating any workflow card |

**Why this matters:** Incorrect silent routing (e.g., splitting a single-workflow task into a broken chain) is worse UX than asking one clarifying question. The user seeing *"I think this single workflow covers everything — shall I proceed?"* is helpful and transparent. It also lets the user correct BioMate's understanding of the task before any execution happens.

**The LLM should surface its reasoning briefly:** Instead of silently routing, it can say:
> "The `pharmacophore_filtering` workflow handles both steps — it generates the pharmacophore model from your reference compounds AND screens the library in a single run. I'll set it up as one workflow. Does that match what you intended?"

This is especially important for Tier 3 (dynamic chain): the LLM should present the proposed chain plan to the user and ask *"Does this sequence of workflows match your intent?"* before submitting — since dynamic chains are the most likely to be wrong.

---

## 3. Proposed Architecture

### Current Flow

```
analyzeIntent()
  → isSequential=true
  → processSequentialPipeline()
    → resolve all N steps IN PARALLEL via processSubIntent()
    → if all steps → same path: collapse (partial fix, misses multi-workflow cases)
    → else: submit N-step chain
```

### Proposed Flow

```
analyzeIntent()
  → isSequential=true, chainHint=?

  [Tier 1] Full-query single workflow search
    → search workflows with the FULL original message (not sub-queries)
    → LLM coverage check: does this workflow's description cover ALL logical steps?
    → confidence HIGH (≥0.85): return single workflow card directly
    → confidence MEDIUM (0.5–0.85): return single workflow card + ask user to confirm
    → confidence LOW (<0.5): fall through to Tier 2

  [Tier 2] Curated chain lookup
    → chainHint from analyzeIntent → match in workflow_chains table
    → if match found: present WorkflowChainPlan card + brief explanation
    → always show the chain plan before execution (user sees steps)

  [Tier 3] Greedy dynamic chaining
    → resolve steps SEQUENTIALLY (not in parallel)
    → each step: LLM finds workflow covering the most remaining logical steps
    → step N's output_types inform step N+1's search
    → ALWAYS present the proposed chain plan to user and ask confirmation
      before submitting — dynamic chains are most prone to errors
    → only fire if Tier 1 + Tier 2 both miss
```

### Key Change: Workflow-Capability-Driven, Not Message-Structure-Driven

| | Current | Proposed |
|---|---|---|
| Decomposition basis | User's verbal sub-steps (message structure) | Workflow capabilities (`description`, `input_types`, `output_types`) matched by LLM domain knowledge |
| Coverage check | None — assumes 1 intent = 1 workflow | LLM judges whether one workflow covers multiple logical steps using scientific knowledge + workflow description |
| Resolution order | Parallel (all sub-intents at once) | Sequential (greedy): each step informs the next |
| Curated chains | Never consulted in `processSequentialPipeline` | Consulted before dynamic chain |
| Single-workflow match | Only checks if all steps resolve to the same path (post-hoc, brittle) | Checks FIRST via full-query search + LLM coverage judgment |

---

## 4. How Workflow Fields Guide the Decision

The `workflows` table has the following fields. Their usefulness for coverage check varies:

```
step_count     — counts TOOL-FUNCTION steps (process blocks in Nextflow)
                 NOT useful for coverage: step_count=8 may cover 1 biological task;
                 step_count=3 may cover 2 biological tasks. Do NOT use this field
                 to infer how many logical steps a workflow covers.

description    — ✅ PRIMARY SIGNAL. Natural language, biological level.
                 Describes what the workflow achieves end-to-end from the scientist's
                 perspective. Directly comparable to the user's stated logical steps.
                 Example: "Derive consensus pharmacophore model from known active SMILES,
                 then score compound library and emit hits above min_features threshold."

input_types    — ✅ DATA BOUNDARY SIGNAL. What must the user provide?
                 ["smiles"] for pharmacophore_filtering.
                 If the user HAS the required input types, the workflow is executable.

output_types   — ✅ DATA BOUNDARY SIGNAL. What does the workflow produce?
                 ["filtered_hits", "tsv", "json"] for pharmacophore_filtering.
                 Determines whether a downstream workflow can accept this as input (Tier 3).
```

The `workflow_chains` table has:
```
steps           — ordered list of WORKFLOW names (Level 2 units, not tool-functions)
required_inputs — entry-point data types for the chain
expected_outputs — exit data types from the chain
example_queries  — natural language queries that should trigger this chain
description     — ✅ PRIMARY SIGNAL for Tier 2 match
```

### Tier 1 Decision Signal

When `search_nextflow_workflow(full_query)` returns a workflow, use it if:
- Search score ≥ threshold (e.g., 6.0 — indicates semantic match to the full task)
- `description` semantically covers the key biological operations mentioned in the query

**Coverage check is description-based, not step_count-based.**

#### The description field already has biological purpose labels

The `description` column for BioMate-authored Nextflow workflows already stores biological purpose per tool-function step, written in natural language. Example for `pharmacophore_filtering`:

```
Pipeline Steps:
1. PHARMACOPHORE_GENERATE — Derive a consensus pharmacophore model from known active SMILES;
   identifies Donor (D), Acceptor (A), Aromatic (Ar), Hydrophobic (H) features via RDKit.
2. PHARMACOPHORE_SCREEN — Score each compound in a SMILES/SDF library by number of
   pharmacophore features matched; emit compounds satisfying params.min_features.
3. PHARMACOPHORE_REPORT — Write filtered SMILES, per-compound match breakdown TSV, summary JSON.
```

From these descriptions, it is directly inferable that the workflow covers:
- "build/derive pharmacophore model" → PHARMACOPHORE_GENERATE  ✓
- "screen/filter compound library" → PHARMACOPHORE_SCREEN  ✓

The biological purpose labels are already present. The gap is that the routing system never queries the description for coverage matching — it only uses the description for FTS search scoring.

#### Note on BiologicalLogicDetector

`backend/lib/galaxy/ai/biological_logic_detector.py` exists and uses LLM (Gemini) to detect biological logic groups. However, it was designed for **Galaxy `.ga` format workflows** (tool-step JSON format), not for Nextflow workflows whose DB entries store the raw `.nf` file content and a curated description string. For Nextflow workflows, the curated `description` field in the `workflows` table is the practical source of biological logic information.

**Coverage check: LLM domain knowledge + workflow description, NOT keyword matching**

The user's query may not contain any words that appear in the workflow's process descriptions. For example:

```
User says:  "derive binding feature fingerprints from actives and use them to filter a scaffold set"
Process:    PHARMACOPHORE_GENERATE, PHARMACOPHORE_SCREEN

Keyword overlap = 0.  String matching fails completely.
```

An expert bioinformatician reading this query immediately knows:
- "derive binding feature fingerprints from actives" = pharmacophore model generation
- "filter a scaffold set using them" = pharmacophore-based library screening

This reasoning requires **scientific domain knowledge about what operations mean**, not string overlap. The LLM already has this knowledge. The coverage check should therefore be an LLM call:

```
System: You are an expert bioinformatician. Given a workflow's description and a user's
        biological goals, determine whether the workflow covers all the goals in a single run.

Input:
  User's overall goal: "derive binding feature fingerprints from actives and filter a scaffold set"
  User's logical sub-steps: ["derive pharmacophore model from active compounds",
                              "screen compound library against pharmacophore"]
  Candidate workflow name: "pharmacophore_filtering"
  Workflow description: "PHARMACOPHORE_GENERATE — Derive consensus pharmacophore model
                          from active SMILES. PHARMACOPHORE_SCREEN — Score each compound
                          by pharmacophore features matched. PHARMACOPHORE_REPORT — emit
                          filtered hits."

Question: Does this single workflow cover ALL of the user's logical sub-steps in one execution?
          Answer YES or NO. If YES, confirm which sub-steps are covered.
          If NO, list which sub-steps are NOT covered.

LLM answer: YES.
  - Sub-step 1 ("derive pharmacophore model") → PHARMACOPHORE_GENERATE ✓
  - Sub-step 2 ("screen library") → PHARMACOPHORE_SCREEN ✓
  → Coverage = complete → USE single workflow
```

The workflow `description` is shown to the LLM as **supporting evidence** — it tells the LLM what the workflow actually does, process by process. The LLM uses this together with its own domain knowledge to determine whether the described operations satisfy the user's biological intent.

**Why this matters for ambiguous cases:**
- `nf-core/rnaseq` description mentions "STAR alignment, RSEM quantification, MultiQC" but the user asked "align reads and get expression counts" — LLM knows RSEM produces counts even though the user didn't say "RSEM"
- `pocket_detection_druggability` description mentions "fpocket binding-site detection" — LLM knows this covers "identify druggable binding sites" even if user said "find where small molecules can bind"

**Implementation:** Haiku call (cheap, fast), max_tokens=100. Returns `{covered: true/false, uncovered_steps: string[]}`. Called only when full-query search score is ≥ threshold (avoids calling LLM on obviously wrong matches).

Despite having 3 tool-function steps internally, `pharmacophore_filtering` covers both biological logical steps in one execution. This is discovered by the LLM reading the description — `step_count=3` is never consulted.

### Tier 2 Decision Signal

`analyzeIntent` already returns `chainHint` — a curated chain name if the query matches known chains. Currently this field is **never used in `processSequentialPipeline`**.

Example:
```
Query: "Run ADMET profiling on compounds, then dock the survivors"
chainHint: "drug_discovery_admet_gated_screening"  ← already returned by analyzeIntent
```

Chain id=7 (`drug_discovery_admet_gated_screening`) covers exactly this: `pharmacophore_filtering → predict_admet_properties → structure_prediction_docking`.

### Tier 3 (Greedy Dynamic Chain)

Only when Tier 1 + Tier 2 miss. Resolves steps **sequentially**:

```
Step 1: search(full_query) → find best workflow W1
         W1.output_types = ["vcf"]
Step 2: search(remaining_query + "input: vcf") → find W2
         W2.output_types = ["annotated_vcf", "html"]
Step 3: is remaining_query covered by W2's outputs? yes → done
```

This is how a human expert would think: "what's the best first tool? ok, it outputs VCF files. Now what takes VCF and does the next thing?"

---

## 5. Concrete Examples

### Example A: Pharmacophore (S4 bug)

**Query:** "Build a pharmacophore model from 4 ABL1 inhibitors and screen a compound library"

**Current behavior:**
- analyzeIntent → 2 intents, isSequential=true
- Parallel resolve: step1 → pharmacophore_filtering, step2 → pharmacophore_filtering
- Submit 2-step chain → step1 runs pharmacophore_filtering → step2 runs it again with no input → fails

**Proposed behavior:**
- Tier 1: search(full_query) → pharmacophore_filtering, score=8.2, description mentions both generate+screen → USE IT
- Result: single workflow card, `button-run-workflow-panel`, params: `{reference_smiles: [...], library_smiles: [...]}`
- Execute: pharmacophore_filtering runs once, produces filtered_hits.tsv + summary.json

### Example B: RNA-seq DE analysis (existing curated chain)

**Query:** "Align my RNA-seq reads to hg38 and run differential expression for treated vs control"

**Current behavior (acceptable today):**
- analyzeIntent → 2 intents, isSequential=true, chainHint="bulk_rnaseq_de_analysis"
- processSequentialPipeline → parallel resolve → 2 steps: nf-core/rnaseq + nf-core/differentialabundance
- Submit 2-step chain

**Proposed behavior:**
- Tier 1: search(full_query) → nf-core/rnaseq (score=9.1) — but this doesn't cover DE analysis → Tier 1 miss (description doesn't mention DE)
- Tier 2: chainHint="bulk_rnaseq_de_analysis" → chain id=2 found → USE IT (pre-validated)
- Result: WorkflowChainPlan card rendered for the curated chain

### Example C: Novel target → lead optimization (Tier 3)

**Query:** "I have a novel kinase target with unknown binding site. Find druggable pockets, screen compounds, run MD to validate top hits"

**No single workflow covers pocket detection + pharmacophore + ADMET + MD.**

**Proposed behavior:**
- Tier 1: search(full_query) → pocket_detection_druggability score=7.2 — description says "binding site detection and druggability scoring" but doesn't cover MD → ambiguous. Score alone insufficient → Tier 1 miss.
- Tier 2: chainHint="target_to_lead_full" → chain id=8 found! Steps: pocket_detection → pharmacophore_filtering → predict_admet → structure_prediction_docking → GROMACS MD → REINVENT4. Matches query intent exactly → USE IT.
- Result: WorkflowChainPlan card for curated chain id=8.

### Example D: True dynamic chain (no curated match)

**Query:** "Detect somatic mutations in my tumor/normal BAM pair, then run pathway enrichment on the mutated genes"

**No curated chain covers variant calling + pathway enrichment together.**

**Proposed behavior:**
- Tier 1: search(full_query) → sarek (somatic variant calling) doesn't cover pathway enrichment → Tier 1 miss
- Tier 2: chainHint=null, no curated chain → Tier 2 miss
- Tier 3 (greedy):
  - Step 1: search("detect somatic mutations tumor normal BAM") → sarek, output_types=["vcf"]
  - Step 2: search remaining="pathway enrichment on mutated genes", seeded with "input: vcf" → gene_set_enrichment_analysis, input_types includes "vcf/gene_list"
  - 2 steps cover the full query → submit as 2-step dynamic chain

---

## 6. Implementation Plan

### Phase 1: Tier 2 fix (quickest win, no new search logic)

**File:** `frontend/server/galaxy-assistant.ts`

In `processMultiIntent()`, before calling `processSequentialPipeline()`:

```typescript
// Tier 2: check curated chain first
if (decomposition.chainHint) {
  const curatedChainResult = await this.searchCuratedChain(decomposition.chainHint, message, context);
  if (curatedChainResult) return curatedChainResult;
}
```

**Impact:** Catches bulk_rnaseq_de_analysis, drug_discovery_admet_gated_screening, target_to_lead_full, rare_disease_multimodal_workup.

### Phase 2: Tier 1 fix (single-workflow full-query search)

In `processMultiIntent()`, before Tier 2:

```typescript
// Tier 1: try single workflow for full query
if (decomposition.isSequential) {
  const fullQueryResult = await this.tryFullQuerySingleWorkflow(message, decomposition, context);
  if (fullQueryResult) return fullQueryResult;
}
```

`tryFullQuerySingleWorkflow()`:
```typescript
private async tryFullQuerySingleWorkflow(message, decomposition, context) {
  // Use full original message as search query (not sub-queries)
  const result = await this.processSubIntent(
    { ...decomposition.primaryIntent, subQuery: message },
    message, context, [], []
  );
  const wf = result?.generatedWorkflow;
  if (!wf?.nextflow_path) return null;

  // Validate: does this workflow's description cover all steps?
  const coverage = await this.checkWorkflowCoverage(wf, decomposition.intents);
  if (coverage >= 0.7) return result;  // 70% of steps covered by single workflow
  return null;
}
```

`checkWorkflowCoverage(workflowName, workflowDescription, logicalSteps, originalQuery)`:

The user's query phrasing may not keyword-match the workflow description at all. Coverage
must be assessed using **scientific domain knowledge**, not string overlap.

**Implementation — LLM (Haiku) call:**
```typescript
async function checkWorkflowCoverage(
  wfName: string,
  wfDescription: string,
  logicalSteps: DecomposedIntent[],   // from analyzeIntent
  originalQuery: string
): Promise<{ covered: boolean; uncoveredSteps: string[] }> {

  const stepList = logicalSteps.map((s, i) => `${i+1}. ${s.subQuery}`).join('\n');

  const prompt = `You are an expert bioinformatician.

Workflow: "${wfName}"
Workflow description: "${wfDescription.slice(0, 600)}"

User's overall goal: "${originalQuery}"
User's biological sub-steps:
${stepList}

Question: Based on the workflow description AND your scientific knowledge of what
"${wfName}" does, does this single workflow cover ALL of the user's sub-steps
in one execution?

Answer with JSON: {"covered": true/false, "uncovered": ["step text", ...]}
If covered=true, uncovered=[]. Be concise.`;

  // Haiku call, max_tokens=150
  const result = await callHaiku(prompt, 150);
  return parseJSON(result) ?? { covered: false, uncovered: logicalSteps.map(s => s.subQuery) };
}
```

Threshold: `covered=true` → use single workflow. This is a binary LLM judgment, not a
numeric score. The LLM uses the workflow description as supporting evidence but applies its
own domain knowledge when the description is incomplete or uses non-obvious terminology.

**Important:** The coverage check NEVER uses `step_count`. A workflow with 1 tool-function
can cover 3 logical steps; a workflow with 20 tool-functions can cover 1 logical step.
The biological description + LLM domain knowledge are the only reliable signals.

**Also applies in Tier 3 greedy loop:**
```typescript
// checkCoverageCount uses the same LLM approach:
// "How many of these remaining sub-steps does workflow W cover?
//  Return the count and which sub-steps, using your scientific knowledge."
const coveredCount = await checkCoverageCount(wf.name, wf.description, remainingIntents, originalQuery);
```

### Phase 3: Tier 3 sequential greedy resolution

Replace parallel `Promise.all()` in `processSequentialPipeline` with sequential greedy.
Each "step" in the chain is one **workflow** (which may have N tool-function steps internally).
The goal is to find the minimum number of workflows that cover all the user's logical steps.

```typescript
// BEFORE (parallel, blind — resolves per-intent, misses multi-logical-step workflows)
const stepResults = await Promise.all(
  decomposition.intents.map(async (intent, idx) => processSubIntent(intent, ...))
);

// AFTER (sequential, greedy, output-informed)
// Each iteration finds the workflow that covers THE MOST remaining logical steps
const stepResults = [];
let remainingIntents = [...decomposition.intents];
let prevOutputTypes: string[] = [];

while (remainingIntents.length > 0) {
  // Build a query covering ALL remaining logical steps (not just the first)
  const remainingQuery = remainingIntents.map(i => i.subQuery).join(' then ');
  const enrichedQuery = prevOutputTypes.length > 0
    ? `${remainingQuery} [available input types: ${prevOutputTypes.join(', ')}]`
    : remainingQuery;

  const result = await processSubIntent({ subQuery: enrichedQuery, ... }, ...);
  const wf = result?.generatedWorkflow;

  // Determine how many of the remaining logical steps this workflow covers
  const coveredCount = await checkCoverageCount(wf?.description, remainingIntents);
  const coveredIntents = remainingIntents.slice(0, Math.max(1, coveredCount));

  stepResults.push({ intents: coveredIntents, subResult: result });
  remainingIntents = remainingIntents.slice(coveredIntents.length);
  prevOutputTypes = wf?.output_types || [];

  if (stepResults.length > 6) break; // hard limit: max 6 workflow executions in a chain
}
```

This approach naturally collapses the pharmacophore case: the first iteration finds
`pharmacophore_filtering` covering BOTH remaining logical steps → `coveredCount=2` →
`remainingIntents` becomes empty → loop ends → 1 workflow, not 2.

---

## 7. Test Plan

### Unit Tests (jest / vitest)

| Test ID | Input | Expected behavior |
|---|---|---|
| T1 | "Build pharmacophore model from X then screen Y" | Tier 1 fires → single pharmacophore_filtering card |
| T2 | "Align RNA-seq reads then run DE analysis" | Tier 2 fires → curated bulk_rnaseq_de_analysis chain card |
| T3 | "ADMET screen then dock survivors" | Tier 2 fires → curated drug_discovery_admet_gated_screening chain card |
| T4 | "Detect somatic mutations then pathway enrichment" | Tier 3 fires → 2-step dynamic chain (sarek + pathway) |
| T5 | "Run QC and alignment" (single nf-core/rnaseq query) | No sequential path → single workflow card as today |
| T6 | Sequential with no matching workflow at any tier | Tier 3 fires → graceful pipeline card with unresolved steps noted |

### E2E Tests (Playwright)

**File:** `frontend/e2e/drug-discovery-pilot-e2e.e2e.ts`

| Session | Current status | Target after fix |
|---|---|---|
| S4_PHARMA | exec=failed (2-step chain, same workflow twice) | exec=completed (single pharmacophore_filtering card) |

New E2E test file: `frontend/e2e/sequential-pipeline-routing.e2e.ts`

| Test | Query | Assertion |
|---|---|---|
| SP-1 | S4 pharmacophore query | `type=workflow` (not `type=chain`), `exec=completed` |
| SP-2 | Bulk RNA-seq + DE query | `workflow_type=chain` with curated chain name |
| SP-3 | Full ADMET + docking chain | `workflow_type=chain` with curated chain |
| SP-4 | Novel task with no curated chain | Dynamic chain, ≥1 step has resolved nextflow_path |

### Regression Tests

All existing tests must continue to pass:
- `full-workflow-e2e.e2e.ts` — 8/8
- `germline-complete-e2e.e2e.ts` — 6/6
- `drug-discovery-pilot-e2e.e2e.ts` — 6/6

---

## 8. Evaluation Criteria

### Correctness

| Criterion | Metric | Target |
|---|---|---|
| Single-workflow coverage | % of "appears sequential but is single workflow" queries correctly routed to single workflow | ≥ 90% |
| Curated chain hit rate | % of queries matching a curated chain that get routed to it | ≥ 95% |
| Dynamic chain quality | % of dynamic chains where all steps have resolved nextflow_path | ≥ 70% |
| False positive chain rate | % of single-workflow queries incorrectly split into multi-step chain | ≤ 5% |

### Execution quality

| Criterion | Metric | Target |
|---|---|---|
| exec=completed rate | % of sessions where execution reaches terminal completed state | ≥ 80% |
| S4 pharmacophore | exec=completed, output files > 0 | ✅ required |
| Chain step path resolution | For dynamic chains: all steps have non-null nextflow_path | ≥ 80% of steps |

### Performance

| Criterion | Metric | Target |
|---|---|---|
| Time-to-card (Tier 1) | Latency when single workflow found | ≤ current single-workflow latency + 2s |
| Time-to-card (Tier 2) | Latency when curated chain found | ≤ Tier 1 + 1s (chain lookup is DB query) |
| Time-to-card (Tier 3) | Latency for greedy sequential resolution | ≤ current processSequentialPipeline + 10s (sequential adds serial LLM calls) |

---

## 9. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Tier 1 false positives: single workflow matched when chain is correct | Medium | Use coverage threshold (≥70%), not just any match |
| Tier 2 chainHint wrong (LLM guesses wrong chain name) | Low | Fall through to Tier 3 if chain not found in DB |
| Tier 3 greedy gets stuck (step N's output doesn't match any workflow's input) | Medium | Max 6 steps hard limit; unresolved steps still submitted with null path + warning |
| Regression: existing single-intent queries routed to sequential path incorrectly | Low | `isSequential` flag only set by analyzeIntent LLM; single queries won't set it |

---

## 10. Open Questions

1. **`checkWorkflowCoverage` implementation:** LLM call (Haiku). Keyword matching is explicitly rejected — the user's query phrasing cannot be assumed to overlap with workflow process names or description text. The LLM uses its scientific domain knowledge plus the workflow description to judge coverage. The `description` field (which stores biological purpose per process step for BioMate Nextflow workflows) is passed as supporting evidence. The `BiologicalLogicDetector` (Gemini-based) is available for Galaxy `.ga` workflows but is not applicable to Nextflow workflows here.

2. **Curated chain execution UI:** Currently `WorkflowChainPlan` renders curated chains but doesn't have a "Run" button — it's informational only. Should Tier 2 also offer a runnable button? This would require the chain execution endpoint to accept a chain name (not just steps array).

3. **Parameter merging for Tier 1:** When collapsing sequential intents to single workflow, how to merge params from all intents? Current: `Object.assign({}, ...pipelineSteps.map(s => s.params))`. Risk: conflicting keys (e.g., both steps have `outdir`). Resolution: first-step params win for shared keys.

4. **Sequential Tier 3 latency:** Going from parallel to sequential resolution adds serial LLM calls per step. For a 3-step pipeline, this is ~2× the latency. Acceptable for correctness? Mitigation: cache step N results; parallelize non-dependent sub-queries.
