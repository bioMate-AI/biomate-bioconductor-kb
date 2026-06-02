# Chain Mis-route Fix: `bioc_reactive` Classification & Tightened `chain_hint` Prompt
**Date**: 2026-06-02  
**Branch**: integration/next-phase  
**Status**: Implemented and committed

---

## Problem Diagnosed

The existing `chain_hint` mechanism in `galaxy-assistant.ts` was causing mis-routes: simple single-step requests (e.g. "run RNA-seq on my FASTQ files") were being escalated to full multi-step chain pipelines by the intent classifier LLM.

### Root causes

1. **All 35 chains fed into the intent classifier** — `_getChainHintNames()` fetched every chain from `GET /api/workflow-chains` and injected all names into the LLM prompt. The 6 new `bioc_*_v2` chains (added for post-completion suggestions) appeared alongside the curated drug-discovery chains, creating 35 names the LLM could match against.

2. **Overly permissive `chain_hint` instruction** — The prompt said "if the query clearly maps to one of these curated workflow chains, return its name." An LLM example showed `chain_hint: "bulk_rnaseq_de_analysis"` for the query "Run RNA-seq differential expression analysis on my samples SRR1518169" — teaching the model to escalate a single-step RNA-seq request into a full DE chain.

3. **Sequential pipeline example also mis-taught** — The `is_sequential` example in the prompt also had `chain_hint: "bulk_rnaseq_de_analysis"` for a FastQC → STAR alignment request, which has nothing to do with the DE analysis chain.

4. **Tier 2 is a full bypass** — When `chain_hint` fires, Tier 2 in the routing code completely replaces the Tier 1 single-workflow lookup with a multi-step chain, even if the user only asked for one step.

---

## Changes Made

### 1. `bioc_chain_templates.py` — Mark as `bioc_reactive`

Changed the `source` value for all 6 Bioconductor chain templates from `'curated'` to `'bioc_reactive'` at registration time:

```python
# Before
VALUES (?,?,?,?,?,?,?,?,?,?, 'curated', 0, 0.0, ?,?)

# After  
VALUES (?,?,?,?,?,?,?,?,?,?, 'bioc_reactive', 0, 0.0, ?,?)
```

These chains (`bioc_bulk_rnaseq_de_v2`, `bioc_scrna_cluster_v2`, `bioc_chipseq_annotation_v2`, `bioc_variant_annotation_v2`, `bioc_methylation_dm_v2`, `bioc_proteomics_de_v2`) are **post-completion suggestions only** — they should be surfaced after a run finishes via `/api/v2/bioc/chain-suggest`, not by the upfront intent classifier.

The DB was also updated directly: `UPDATE workflow_chains SET source='bioc_reactive' WHERE name LIKE 'bioc_%_v2'`.

### 2. `workflow_chain.py` — Add `intent_hint` filter to `/api/workflow-chains`

Added `intent_hint: bool = False` query parameter to `GET /api/workflow-chains`:

```python
async def list_workflow_chains(
    domain: Optional[str] = None,
    intent_hint: bool = False,
) -> Dict[str, Any]:
    ...
    if intent_hint:
        clauses.append("source != 'bioc_reactive'")
```

When `intent_hint=true`, excludes `bioc_reactive` chains. Result: the intent classifier sees 29 chains (the curated drug-discovery pipelines), not 35.

The `_fetchCuratedChain()` call (used by Tier 2 to look up a named chain) still uses the unfiltered endpoint so it can resolve any chain including reactive ones if the user explicitly names them.

### 3. `galaxy-assistant.ts` — Tighter `chain_hint` prompt and correct examples

**`_getChainHintNames()`** — Updated URL to use `?intent_hint=true`:
```typescript
const res = await fetch(`${galaxyUrl}/api/workflow-chains?intent_hint=true`, { ... });
```

**`chain_hint` instruction** — Replaced the permissive "if the query clearly maps" with an explicit gate:
```
chain_hint: ONLY set if the user explicitly requests a named multi-step pipeline that spans ALL
  the steps in that chain (e.g. "run the full drug discovery pipeline", "target-to-lead", "rare
  disease multi-modal workup"). NEVER set if the user asks for a single analysis type (RNA-seq,
  differential expression, ADMET screening) even if that step is part of a chain — a partial
  request should go through normal workflow search (Tier 1), not chain escalation. Set null when
  in doubt.
```

**Single-intent example** — Fixed the RNA-seq DE example to return `chain_hint: null` with a note explaining why:
```json
"chain_hint": null
```
> Note: chain_hint is null here even though this involves RNA-seq + DE, because the user did not explicitly ask for a named multi-step pipeline. BioMate will route this to the best single workflow (nf-core/rnaseq). Chain suggestions for downstream DE analysis come reactively after the run completes.

**Sequential pipeline example** — Fixed to also return `chain_hint: null` with a clarifying note:
```
chain_hint should still be null unless the user's full request explicitly names one of the known pipeline names
```

---

## Architecture Clarification (Two Chain Paths)

| Path | When | Mechanism | Chains included |
|---|---|---|---|
| **Proactive** (Tier 2) | User explicitly requests a named pipeline | `chain_hint` → `_fetchCuratedChain` → Tier 2 routing | `source='curated'` only (29 chains) |
| **Reactive** (post-completion) | Run finishes; user asks "what next?" | `POST /api/v2/bioc/chain-suggest` | `BIOC_CHAIN_TEMPLATES` (6 bioc_*_v2) |

The two paths are now clearly separated. The proactive path is narrowed; the reactive path is the correct entry point for Bioconductor downstream suggestions.

---

## Files Changed

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/bioc_chain_templates.py` | source `'curated'` → `'bioc_reactive'` |
| `backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py` | `intent_hint` filter on `/api/workflow-chains` |
| `frontend/server/galaxy-assistant.ts` | `?intent_hint=true` URL; tighter chain_hint prompt; correct null examples |
| `backend/database/galaxy_ai_tools.db` | 6 bioc_*_v2 rows updated to `source='bioc_reactive'` |

---

## What This Does NOT Change

- The existing curated drug-discovery chains (`bulk_rnaseq_de_analysis`, `target_to_lead_full`, `drug_discovery_admet_gated_screening`, etc.) continue to work exactly as before via `chain_hint` + Tier 2.
- The `bioc_*_v2` chains are still fully executable — they remain in the DB and are available via both `GET /api/workflow-chains` (unfiltered) and `POST /api/workflows/chain`.
- The chain executor (`workflow_chain.py`) is unchanged.
- The `propose_chain` flow (Gap 2 from the Bioc connection plan) is scaffolded but not yet wired end-to-end — that remains Phase 3 work.
