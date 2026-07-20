# Workflow Retrieval Architecture
**Date:** 2026-07-15  
**Status:** Current implementation after hard-coded routing removal

---

## 1. The Problem This Solved

When a user sends:

> "Design a SARS-CoV-2 spike/ACE2 macrolactam cyclic peptide PPI blocker — benchmark DiffDock or HADDOCK-based docking to PDB 6M0J"

The system must select one workflow from 2,455 options. Previously, the FTS query was manipulated based on pattern-matching against the query text: it extracted "DiffDock" as a "named anchor" and AND-required it in every result, which excluded `cyclic_peptide_design` entirely. Meanwhile the AI text response correctly described cyclic peptide design. Text and panel showed different things.

---

## 2. What Was Removed

Everything that hard-coded routing knowledge in Python code:

| Removed | What it did | Why it was wrong |
|---------|-------------|-----------------|
| Named anchor AND-requirement | Forced a tool name into every FTS result | "DiffDock or HADDOCK" made DiffDock mandatory, excluding the correct workflow |
| `_extract_named_tool_anchor()` | Pattern-matched "using X" / "run X" to extract tool names | Fragile, brittle, caused the UC6 mismatch |
| `_extract_biomni_subworkflow_anchor()` | Hard-routed codon optimization and AutoDock Vina | Encoded specific workflow names in code |
| `_extract_explicit_pipeline_slug()` | Matched "nf-core/X" patterns to force nf-core slug | Dead code depending on above |
| `_resolve_pipeline_slug_conflict()` | Hard-chose epitopeprediction vs mhcquant by keyword lists | Workflow-specific hard-code |
| `_NAMED_ANCHOR_BLOCKLIST` | ~50 words excluded from anchor detection | Symptom of a broken mechanism |
| `_KNOWN_NFCORE_PIPELINE_SLUGS` | 16 nf-core names for special handling | Hard-coded pipeline list |
| `_EPI_TOPE_PREDICTION_SIGNALS` | 13 terms to boost epitopeprediction scoring | Per-workflow score patch |
| `_MHCQUANT_MS_SIGNALS` | 10 terms to boost/penalize mhcquant | Per-workflow score patch |
| `_CODON_MRNA_SIGNALS` | 9 terms to route to codon optimization | Per-workflow score patch |
| `_DOCKING_VINA_SIGNALS` | 8 terms to route to AutoDock Vina | Per-workflow score patch |
| Per-workflow scoring adjustments | +20/-35 score patches for specific pipeline names | Hard-coded domain knowledge in scoring |

None of these encoded knowledge that the LLM couldn't reason about from the workflow descriptions. They were compensations for FTS being the only retrieval signal.

---

## 3. Full Request Flow

```
USER MESSAGE
     │
     ▼
┌─────────────────────────────────────────────────────────┐
│  frontend/server/galaxy-assistant.ts                     │
│  processMessage()                                        │
│                                                          │
│  Step 1: analyzeIntent()                                 │
│    └── Output: intent type, preferredDomains, bioContext │
│                                                          │
│  Step 4: generateWorkflow()                              │
│    └── POST /api/ai_assistant/generate_workflow          │
│         sends: user_intent, key_terms,                   │
│         preferred_domains, top_k=5        ─────────────► GALAXY BACKEND
│    ◄── Returns: workflow_name,                           │ (Section 4)
│                 candidate_workflows[0..4]                │
│                                                          │
│  Step 6: generateResponse()                              │
│    Streams AI text to user.                              │
│    Prompt includes domain routing rules for the          │
│    detected preferredDomains — so the text already       │
│    reflects correct workflow knowledge.                  │
│                                                          │
│  Step 6b: _reselectWorkflow()   ← NEW                    │
│    Input: user message + generated text + candidates     │
│    LLM prompt:                                           │
│      - Lists all 5 candidates with name + description   │
│      - Routing rules for detected domain                 │
│      - Pos/neg examples for explicit tool requests       │
│        POS: "run DiffDock" → DiffDock workflow           │
│        NEG: "benchmark DiffDock or HADDOCK" + AI text   │
│             describes cyclic peptide → pick cyclic peptide│
│    Output: candidate number 1-5 (max_tokens=4)          │
│                                                          │
│    If reselected ≠ FTS result:                           │
│      _lookupWorkflowByName()                             │
│        GET /api/ai_assistant/workflow_by_name?name=      │
│        Direct DB row fetch — no second FTS search        │
│                                                          │
│  Step 7: emit workflow_ready SSE event                   │
└─────────────────────────────────────────────────────────┘
```

---

## 4. Galaxy Backend Retrieval Stack

Three independent signals — all additive. No signal can exclude a workflow.

```
QUERY arrives at UnifiedWorkflowSearch.search()
(backend/lib/galaxy/ai/unified_workflow_search.py)

───────────────────────────────────────────────────────────
SIGNAL A: Pass-0 LLM                    [NOW ACTIVE]
───────────────────────────────────────────────────────────
_browse_catalog_with_llm(query, broad_limit=60, output_limit=10)

Step 1 — broad FTS fetch (relaxed OR query, no anchor requirement)
         Returns up to 60 candidate workflows with name + description

Step 2 — format as: "id. [type] name: description[:120]"

Step 3 — LLM call (cheap/fast model, max_tokens=512, temp=0)
         Prompt instructs LLM to:
           • Prefer complete pipelines over subworkflows
           • Honor explicit tool requests ("run DiffDock" → DiffDock)
           • Ignore alternatives context ("benchmark X or Y" → pick by goal)
           • Provide pos/neg examples for the above two rules
         Returns: JSON array of up to 10 workflow IDs, best-first

Step 4 — rank_map: {id → rank_position}

Scoring effect:
  rank 0 → +3.0    rank 5 → +1.5
  rank 1 → +2.7    rank 6 → +1.2
  rank 2 → +2.4    rank 7 → +0.9
  rank 3 → +2.1    rank 8 → +0.6
  rank 4 → +1.8    rank 9 → +0.3

Pass-0 rescue: any workflow the LLM ranked that FTS missed entirely
  is fetched by ID and added to results. This is the only truly
  FTS-independent path (the broad_limit=60 fetch uses a relaxed FTS
  query, so if a workflow has zero keyword overlap with the query,
  it can still be rescued if the LLM ID is known — but that's rare).

Note: the broad fetch itself uses FTS (relaxed). True FTS independence
  requires Signal C (BGE dense embeddings).

───────────────────────────────────────────────────────────
SIGNAL B: FTS (BM25)
───────────────────────────────────────────────────────────
SQLite FTS5 full-text search over name + description + tags

Query is built from: user_intent + key_terms
No anchor forcing. No AND-requirements. Natural keyword matching.

If user says "DiffDock" in context of comparison, FTS will rank
DiffDock workflows higher (because the word appears in the query),
but they are not forced — cyclic_peptide_design can still outrank
them if its description matches the rest of the query better.

FTS score feeds into final score as the base value.

───────────────────────────────────────────────────────────
SIGNAL C: BGE Dense Embeddings          [auto-builds on warmup]
───────────────────────────────────────────────────────────
_dense_workflow_prefilter(query)

Encodes query using sentence-transformers (all-MiniLM-L6-v2 / BGE)
Computes cosine similarity against embedding matrix of all workflows
Returns {workflow_id: cosine_sim} for top-N above threshold

Truly independent of FTS — finds semantically similar workflows
even when keywords don't match.

Status: code complete; NPZ auto-builds on first worker warmup
when sentence_transformers is installed (dev EC2 Docker has it).
Locally disabled because torch dylib is broken.

───────────────────────────────────────────────────────────
SCORE COMBINATION
───────────────────────────────────────────────────────────
final_score = fts_bm25_score
            + Pass-0 LLM rank bonus    (0 to +3.0)
            + BGE cosine sim bonus     (when available)
            + domain match bonus       (preferred_domains from caller)
            + name match bonus         (exact/prefix/substring)
            + execution status bonus   (real_exec_status = success)
            - domain penalty           (penalized_domains from caller)
            - explicit negation penalty ("not X" → -35)

Results sorted, top-5 returned as candidate_workflows.
Best (highest score) returned as the initial workflow_ga.
```

---

## 5. What the LLM Now Knows (Pos/Neg Examples)

Both the Pass-0 LLM and Step 6b reselection LLM now have explicit guidance:

**Explicit tool request → honor it:**
- "run DiffDock on my protein" → DiffDock workflow should rank #1
- "using HADDOCK for docking" → HADDOCK workflow should rank #1

**Alternatives / comparison context → pick by scientific goal:**
- "benchmark DiffDock or HADDOCK-based docking" → the user is comparing, not requesting DiffDock; pick the workflow that fits the overall goal
- "like DiffDock but for cyclic peptides" → user is describing style, not requesting DiffDock; pick the cyclic peptide workflow

This replaces the entire named-anchor mechanism — no regex, no hard-coded blocklists, no AND-requiring. The LLM reads the query and reasons.

---

## 6. UC6 Trace (Before → After)

**Query:** "Design SARS-CoV-2 spike/ACE2 macrolactam cyclic peptide PPI blocker — benchmark DiffDock or HADDOCK-based docking to PDB 6M0J"

**Before:**
1. Named anchor extracted: `diffdock` (pattern: "DiffDock or HADDOCK" → DiffDock extracted)
2. FTS query: `diffdock AND (macrolactam cyclic peptide PPI)`
3. `cyclic_peptide_design` has no "diffdock" in text → excluded
4. Result: DiffDock workflow ✗ / text says cyclic peptide ✓ → mismatch

**After:**
1. FTS query: `macrolactam cyclic peptide PPI blocker` (no anchor forcing)
2. Pass-0 LLM sees 60 candidates; `cyclic_peptide_design` description says "macrolactam", "PPI targets", "Yudin 2015" → LLM ranks it #1 in the 10-ID list
3. FTS also naturally ranks `cyclic_peptide_design` high (keyword overlap)
4. Step 6b: AI text says "cyclic peptide design" + candidates include `cyclic_peptide_design` → LLM selects it
5. Result: cyclic_peptide_design ✓ / text says cyclic peptide ✓ → in sync

---

## 7. What Remains Hard-Coded

`DOMAIN_ROUTING_RULES` in `frontend/server/galaxy-assistant.ts` — large per-domain narrative strings injected into the Step 6 text generation prompt and Step 6b reselection prompt. These encode things like "for ADMET screening, use predict_admet_properties with smiles_input param."

These are different from what was removed:
- What was removed: Python code that **excluded workflows from FTS results**
- Routing rules: LLM context injection that **helps the LLM choose** between candidates that FTS already returned

The long-term path is to enrich workflow descriptions in the DB so the LLM can reason from them directly, making the routing rules unnecessary. Until then, they remain as LLM context, not as search manipulation. They are scoped to detected domains (`preferredDomains` from intent analysis) so only relevant rules are injected — not all 3,000+ words for every query.
