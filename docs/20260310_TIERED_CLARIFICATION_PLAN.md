# Tiered Clarification & Domain Knowledge Activation Plan

**Date:** 2026-03-10  
**Problem:** 70% of `EnhancedToolSearch` scoring logic is dormant because `user_context`
(research_domain, num_samples, num_replicates, expertise_level) is never collected.
The DB contains the requirements; the pipeline to collect them from the user is missing.

**Goal:** Collect the minimum user attributes needed to activate domain knowledge scoring —
without adding friction to the common (unambiguous) case.

---

## Current State

**What works:**
- Tier 1 clarification exists: 14 workflow-type ambiguities detected, one Haiku-generated question asked before workflow generation (`galaxy-assistant.ts`)
- `scientific_context` is read per-tool and put in LLM prompts (NextflowComposer)
- `scientific_rationale` block is built and shown for high/medium-confidence matches

**What is dormant:**
- `EnhancedToolSearch.search_with_context()` has 5 scoring dimensions; 4 are `score += 0` because `user_context = None` everywhere
- `data_requirements.min_samples / min_replicates` are in the DB (e.g., edgeR ≥2, methylKit ≥3) but never checked against the user's data
- `omics_applicability.not_suitable` penalty (-0.40) never fires
- `tool_selection.not_recommended_for` never filters tools

---

## Architecture

The solution is **three tiers of clarification**, each triggered only when relevant:

```
User query
    │
    ▼
Tier 1 (existing): Workflow-type disambiguation          ← already works
    │  e.g. "bulk RNA-seq vs single-cell RNA-seq?"
    │  Triggered: workflowAmbiguity detected in intent analysis
    │
    ▼
Tier 2 (NEW): Data characteristics collection            ← collects user_context
    │  e.g. "Organism? Sample count? Paired-end?"
    │  Triggered: needsWorkflowGeneration=true AND missing_context_fields detected
    │  Asks 1–3 questions in a single structured message
    │
    ▼
Tier 3 (NEW): Pre-generation validation warning          ← uses collected context
    │  e.g. "You have 2 replicates — DESeq2 needs ≥3. Continuing with edgeR instead."
    │  Triggered: collected context violates data_requirements of top-ranked tool
    │
    ▼
Workflow generation with full user_context passed to EnhancedToolSearch
    │  — omics_applicability scoring: 25% active
    │  — task_suitability scoring: 20% active
    │  — data_requirements scoring: 15% active
    │  — expertise_level scoring: 10% active
    │
    ▼
scientific_rationale block personalised to user's data characteristics
```

---

## What to Collect (Tier 2)

The questions are selected dynamically based on: (a) the detected workflow domain,
(b) which `data_requirements` fields are non-null in the top-ranked tools for that domain.

### Always collect (if workflow generation is triggered):

| Attribute | Question | Maps to user_context key |
|-----------|---------|--------------------------|
| **Organism** | "What organism is your data from?" (with common options: Human / Mouse / Other) | `organism` |
| **Sample count per condition** | "How many samples per group/condition?" | `num_samples` |
| **Replicates** | "How many biological replicates per group?" | `num_replicates` |

### Collect only for sequencing workflows (RNA-seq, ChIP-seq, ATAC-seq, WGS, WES):

| Attribute | Question | Maps to user_context key |
|-----------|---------|--------------------------|
| **Read type** | "Paired-end or single-end reads?" | `paired_end` |
| **Read length** | "Read length? (e.g. 75bp, 150bp)" | `read_length` |
| **Sequencing depth** (optional) | "Approximate sequencing depth? (e.g. 30M reads per sample)" | `sequencing_depth` |

### Collect only for variant calling / genome workflows:

| Attribute | Question | Maps to user_context key |
|-----------|---------|--------------------------|
| **Reference genome version** | "Reference genome version? (GRCh38 / GRCh37 / GRCm39 / other)" | `genome_version` |

### Collect only for drug discovery / structural biology:

| Attribute | Question | Maps to user_context key |
|-----------|---------|--------------------------|
| **Input format** | "Are your compounds in SMILES, SDF, or PDB format?" | `compound_format` |

### Always optional (expertise affects explanation depth, not tool selection):

| Attribute | Question | Maps to user_context key |
|-----------|---------|--------------------------|
| **Expertise level** | "Your bioinformatics experience: beginner / intermediate / expert?" | `expertise_level` |

---

## Implementation Plan

### Phase 1: Backend — Context extraction from DB (Week 1)

**File:** `backend/lib/galaxy/ai/unified_tool_search.py`

Add `_infer_required_context_fields(query: str, limit=10) -> List[str]`:
- Runs a quick search for the query (top 10 tools)
- For each tool, reads `scientific_context.data_requirements`
- Returns a list of field names that have non-null values in ≥50% of top results
- Example: for "RNA-seq differential expression" → `['num_replicates', 'organism', 'paired_end']`
- This drives which Tier 2 questions are generated — no hardcoded question lists

```python
def _infer_required_context_fields(self, query: str, limit: int = 10) -> List[str]:
    tools = self.search(query, limit=limit)
    field_counts: Dict[str, int] = {}
    total = len(tools)
    for tool in tools:
        sc = tool.get('scientific_context')
        if not sc:
            continue
        if isinstance(sc, str):
            try: sc = json.loads(sc)
            except: continue
        dr = sc.get('data_requirements') or sc.get('omics_applicability', {}).get('data_requirements', {})
        for field, val in (dr or {}).items():
            if val is not None:
                field_counts[field] = field_counts.get(field, 0) + 1
    # Return fields present in ≥50% of top tools
    return [f for f, count in field_counts.items() if count / max(total, 1) >= 0.5]
```

---

**File:** `backend/lib/galaxy/ai/unified_tool_search.py` — extend `search()` signature

```python
def search(
    self,
    query: str,
    limit: int = 20,
    user_context: Optional[Dict[str, Any]] = None,   # NEW
    filters: Optional[Dict[str, Any]] = None,         # NEW
) -> List[Dict]:
```

Pass `user_context` and `filters` through to `EnhancedToolSearch.search_with_context()`.
This activates the 70% dormant scoring immediately once context is provided.

---

### Phase 2: Backend — Data requirements validation (Week 1)

**File:** `backend/lib/galaxy/ai/ai_assistant.py`

Add `_validate_data_requirements(user_context, tools) -> List[str]`:
- Reads `data_requirements.min_replicates` for top tools
- If `user_context.num_replicates < min_replicates` → generates a warning message
- If a `not_suitable` condition matches the user's organism or design → filters that tool out and selects the next best
- Returns list of warning strings for Tier 3 display

```python
def _validate_data_requirements(
    self,
    user_context: Dict[str, Any],
    search_results: List[Any],
) -> List[str]:
    warnings = []
    num_rep = user_context.get('num_replicates')
    for match in search_results[:3]:
        sc = self._get_scientific_context(match)
        dr = sc.get('data_requirements', {})
        min_rep = dr.get('min_replicates')
        if min_rep and num_rep:
            # Parse "≥3" or "3" from min_replicates
            required = int(re.search(r'\d+', str(min_rep)).group())
            if num_rep < required:
                warnings.append(
                    f"{match.name} requires ≥{required} replicates per group "
                    f"(you have {num_rep}). Considering alternatives."
                )
    return warnings
```

---

### Phase 3: Frontend — Tier 2 question generation (Week 2)

**File:** `frontend/server/galaxy-assistant.ts`

After Tier 1 ambiguity is resolved (or absent), before calling `generateWorkflow()`:
1. Call new backend endpoint `POST /api/ai/required-context` with the query → get list of required field names
2. Check `conversationState` for already-known facts (organism, paired_end, etc. from prior turns)
3. For missing required fields: generate a single structured message with 1–3 questions

```typescript
// After Tier 1 ambiguity check, before workflow generation:
const requiredFields = await this._getRequiredContextFields(message);
const missingFields = requiredFields.filter(f => !this._getContextFact(context, f));

if (missingFields.length > 0 && actions.needsWorkflowGeneration) {
  const questions = this._buildContextQuestions(missingFields, detectedDomain);
  return {
    message: questions,
    awaitingContext: { fields: missingFields },
    // No workflow generated yet
  };
}

// If all context present: pass user_context to workflow generation
const userContext = this._buildUserContext(context);
// userContext = { organism: 'human', num_replicates: 4, paired_end: true, ... }
```

Questions are bundled into a single message, not sequential:

```
To generate the most accurate RNA-seq workflow, I need a few details:

1. **Organism?** Human / Mouse / Other: ___
2. **Biological replicates per group?** (e.g. 3, 4, 6+)
3. **Read type?** Paired-end / Single-end

You can answer all at once, e.g. "Human, 4 replicates, paired-end"
```

---

**File:** `frontend/server/conversation-state.ts`

Add new `FactCategory` values for the new context fields:

```typescript
export type FactCategory =
  | 'sequence' | 'gene' | 'data_type' | 'file_reference' | 'analysis_goal'
  | 'organism'           // NEW
  | 'num_samples'        // NEW
  | 'num_replicates'     // NEW
  | 'paired_end'         // NEW
  | 'read_length'        // NEW
  | 'genome_version'     // NEW
  | 'expertise_level'    // NEW
  | 'compound_format'    // NEW
  | 'other';
```

Extend the fact extraction prompt to parse these from user responses:
"Human, 4 replicates, paired-end" → three extracted facts automatically.

---

### Phase 4: Frontend — Tier 3 warning display (Week 2)

When the backend returns `data_requirement_warnings` in the workflow response:

```typescript
// In workflow-artifact.tsx or chat-message.tsx
if (response.data_requirement_warnings?.length > 0) {
  <Alert variant="warning">
    {warnings.map(w => <p>⚠️ {w}</p>)}
    <p>Proceeding with the best available tool given your data.</p>
  </Alert>
}
```

Example output:
```
⚠️ DESeq2 requires ≥3 biological replicates per group (you have 2).
   Using edgeR instead, which supports 2 replicates (low statistical power — consider adding samples).
```

---

### Phase 5: Context persistence across turns (Week 3)

Context collected in one turn should be remembered for the rest of the session
and used for follow-up queries without re-asking.

**File:** `frontend/server/memory-repository.ts`

Extend `UserPreferences` to store the domain-knowledge context attributes. When a user
says "now do the same analysis for the mouse data", the `organism` fact updates automatically
while `num_replicates` and `paired_end` are inherited.

```typescript
interface UserPreferences {
  // existing ...
  research_organism?: string;
  typical_replicates?: number;
  preferred_read_type?: 'paired' | 'single';
  genome_version?: string;
  expertise_level?: 'beginner' | 'intermediate' | 'expert';
}
```

---

### Phase 6: scientific_rationale personalisation (Week 3)

Currently `_build_scientific_rationale()` returns the same block regardless of the user's data.
With `user_context` available:

- **Filter `when_to_use`** to only show entries matching the user's omics/organism
- **Elevate `common_pitfalls`** that are relevant to the user's replicate count or design
- **Personalise `parameter_hints`** — show the `recommended_value` from `tool_knowledge.recommended_parameters`
  with context: *"For 4 replicates, DESeq2 `minCount = 10` is appropriate"*
- **Flag `do_not_use_when`** entries that match the user's context as active warnings

---

## Summary of Changes Per File

| File | Change | Phase |
|------|--------|-------|
| `backend/lib/galaxy/ai/unified_tool_search.py` | Add `_infer_required_context_fields()`, extend `search()` to accept `user_context` | 1 |
| `backend/lib/galaxy/ai/ai_assistant.py` | Add `_validate_data_requirements()`, pass `user_context` to tool search, add warnings to response | 2 |
| `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | New endpoint `POST /api/ai/required-context` | 2 |
| `frontend/server/galaxy-assistant.ts` | Add Tier 2 question generation between Tier 1 and workflow generation | 3 |
| `frontend/server/conversation-state.ts` | New `FactCategory` values for data characteristics | 3 |
| `frontend/server/routes.ts` | Wire new `/api/ai/required-context` endpoint call | 3 |
| `frontend/client/src/components/chat-message.tsx` | Render `data_requirement_warnings` as Tier 3 alert | 4 |
| `frontend/server/memory-repository.ts` | Persist organism, replicates, read_type across turns | 5 |
| `backend/lib/galaxy/ai/ai_assistant.py` | Personalise `_build_scientific_rationale()` with `user_context` | 6 |

---

## What Gets Unlocked Per Phase

| Phase | Scoring unlocked | User experience |
|-------|-----------------|-----------------|
| 1–2 | Tool search omics (25%) + data_req (15%) | Tools ranked by data compatibility |
| 3 | Task suitability (20%) + expertise (10%) | Questions asked before generation |
| 4 | Data requirement validation | Warning when tools can't handle user's data |
| 5 | Context reuse | No re-asking across turns |
| 6 | Personalised scientific rationale | Pitfalls/hints specific to user's design |

**Total scoring activated: 70% of EnhancedToolSearch (currently 0%).**

---

## Design Principles

1. **Never ask when not needed.** If the query already implies the answer (e.g. "human RNA-seq"), extract it as a fact — don't ask.
2. **Bundle questions, never sequential.** All Tier 2 questions for a workflow are sent in a single message. Users answer in one free-text response.
3. **Parse answers naturally.** "Human, 4 replicates, paired" → three facts extracted by the fact extraction LLM. No form inputs required.
4. **Persist within session, offer to remember across sessions.** After the first workflow, never ask the same question twice for the same user unless the data changes.
5. **Warn, don't block.** If data requirements are violated (insufficient replicates), show a warning and proceed with the best available alternative — never reject the request.
6. **Questions driven by DB content.** The fields we ask about are determined by `data_requirements` in the DB, not hardcoded. As the DB grows, more questions become available automatically.
