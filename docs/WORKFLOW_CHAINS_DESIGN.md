# Workflow Chains — Design Document

**Date**: 2026-03-10  
**Status**: Implemented (v1 — curated, keyword-scored lookup)

---

## Problem

BioMate's `workflows` table stores individual pipelines and subworkflows as flat rows.
When a user submits a project-level query ("run a rare disease workup on this patient's
WGS and RNA-seq"), the LLM had to:

1. Retrieve potentially relevant individual workflows via FTS search.
2. Decide which ones to run.
3. Figure out the order and data-flow connections between them.
4. Assemble a Nextflow composite on the fly.

This was slow, fragile, and inconsistent — the LLM could legally omit steps or connect
outputs to the wrong inputs on every call.

---

## Solution: `workflow_chains` table

A new SQLite table in `galaxy_ai_tools.db` stores **named, ordered compositions** of
workflows that naturally belong together for a research project type.

### When a chain is used

```
User query
    │
    ▼
search_chains(query)          ← keyword + tag scoring, threshold 0.15
    │  match found?
    ├─ YES → load chain → return ordered steps + data-flow connections
    │         (no LLM assembly needed)
    └─ NO  → fall back to per-step FTS search → LLM assembles plan
```

The chain is the preferred path. It encodes expert knowledge about which workflows
must run in sequence and exactly how outputs feed into the next step's inputs.

### Schema

```sql
CREATE TABLE IF NOT EXISTS workflow_chains (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    name             TEXT NOT NULL UNIQUE,       -- stable identifier
    display_name     TEXT NOT NULL,
    domain           TEXT NOT NULL,
    description      TEXT,

    steps            TEXT NOT NULL DEFAULT '[]', -- JSON [{order, workflow_name, role, params_template}]
    connections      TEXT NOT NULL DEFAULT '[]', -- JSON [{from_step, from_output, to_step, to_input}]
    required_inputs  TEXT NOT NULL DEFAULT '[]', -- JSON [{name, type, description}]
    expected_outputs TEXT NOT NULL DEFAULT '[]', -- JSON [{name, type, description}]
    example_queries  TEXT NOT NULL DEFAULT '[]', -- JSON [string, …]
    tags             TEXT NOT NULL DEFAULT '[]', -- JSON [string, …]

    source           TEXT NOT NULL DEFAULT 'curated', -- curated | learned | user_defined
    usage_count      INTEGER NOT NULL DEFAULT 0,
    success_rate     REAL    NOT NULL DEFAULT 0.0,    -- EMA α=0.1
    created_at       TEXT,
    updated_at       TEXT
);
```

### Key design decisions

| Decision | Rationale |
|---|---|
| Steps reference `workflow_name` not `workflow.id` | Names are stable across re-indexes; IDs are not |
| `connections` is explicit, not inferred | The LLM cannot reliably guess output→input wiring for multi-step chains |
| `source = 'curated' / 'learned' / 'user_defined'` | Curated chains are authoritative; learned chains degrade gracefully if wrong; user-defined chains enable team customization |
| `success_rate` updated by `record_chain_run()` | Enables future automatic deprecation of chains that consistently fail |
| Threshold 0.15 for chain match | Low enough to catch paraphrases; high enough to avoid spurious matches on short queries |

---

## Seeded chains (v1)

| Chain | Domain | Steps |
|---|---|---|
| `rare_disease_multimodal_workup` | rare_disease | 5 (sarek → VEP → rnaseq → DROP → case report) |
| `bulk_rnaseq_de_analysis` | transcriptomics | 3 (rnaseq → differentialabundance → GSEA) |
| `single_cell_multimodal_analysis` | single_cell | 5 (QC → integration → annotation → trajectory → DA) |
| `cutandtag_chromatin_analysis` | epigenomics | 3 (alignment+spike-in → SEACR → differential binding) |
| `alternative_polyadenylation_analysis` | transcriptomics | 2 (rnaseq → PolyAMiner-Bulk) |
| `drug_discovery_screening` | drug_discovery | 3 (ADMET → docking → binding affinity) |

> **Note on gaps**: Several steps in these chains reference workflows that are not yet
> in the BioMate codebase (e.g. `nf-core/drop`, `seacr_peak_calling`, `polyaminer_bulk`).
> These are pre-study engineering targets documented in
> `business/BioMate_ZhandongLiu_Opportunity_Analysis.md`.  The chain definition is
> committed now so the rest of the system can be built against a stable contract.

---

## API surface (`UnifiedWorkflowSearch`)

```python
# Find chains matching a free-text query
chains = search.search_chains("run a rare disease workup on WGS + RNA-seq", limit=3)

# Fetch by stable name
chain = search.get_chain("rare_disease_multimodal_workup")

# Record execution outcome (updates usage_count + rolling success_rate)
search.record_chain_run("rare_disease_multimodal_workup", success=True)

# List all chains, optionally filtered by domain
all_chains = search.list_chains(domain="transcriptomics")
```

---

## How the workflow generator should use chains

```python
from lib.galaxy.ai.unified_workflow_search import get_workflow_search

search = get_workflow_search()

# 1. Check for a chain match first
chains = search.search_chains(user_query, limit=1)
if chains:
    chain = chains[0]
    # Chain already encodes: step order, data-flow connections,
    # required inputs, and expected outputs.
    # Hand to NextflowComposer as a pre-built plan.
    plan = chain.to_dict()
else:
    # Fall back to FTS individual workflow search + LLM assembly
    workflows = search.search(user_query, limit=10)
    plan = llm_assemble(workflows, user_query)
```

---

## Future work

| Item | Priority | Notes |
|---|---|---|
| Add remaining gap workflows as steps (DROP, SEACR, PolyAMiner-Bulk) | High | Blocks rare disease, CUT&Tag, APA chains from running end-to-end |
| `learned` source: persist successful LLM-assembled chains automatically | Medium | Needs post-run evaluation hook |
| `user_defined` source: REST endpoint for team to add/edit chains | Medium | Enables domain-expert curation without code changes |
| FTS virtual table for `example_queries` text | Medium | Would make search O(log n) instead of O(n) for large chain sets |
| Vector embedding of chains for semantic similarity | Low | Overkill until chain count exceeds ~100 |
