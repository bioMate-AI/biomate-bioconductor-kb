# Cryo-EM Knowledge Architecture — Design Analysis

**Date:** 2026-04-14  
**Question:** What does text RAG contribute that the structured DB can't? Should these be unified?

---

## Current State: Fragmentation

BioMate has **three overlapping cryo-EM knowledge stores** that cover the same facts in different formats:

| Store | Location | Contents | Consumer |
|---|---|---|---|
| **Structured DB** | `cryo_em_protocols`, `cryo_em_parameters`, `cryo_em_tools` | 6 protocols × JSON fields, 58 MW params, 12 tools | `retriever.py` → system prompt |
| **Expert JSON** | `expert_knowledge_bioimaging.json` | Per-workflow topic entries, best_practices, qc_thresholds, references | `_build_knowledge_highlights()` → user-facing panel |
| **RAG chunks** | `cryo_em_chunks` (150 rows) | Free-text chunks from 9 publications | `retriever.semantic_search()` → system prompt |

The same publication-derived facts (e.g. "saposin nanodisc 1:10:200 molar ratio") appear in all three. This creates:
- Duplication (maintain facts in 3 places)
- Divergence (expert JSON now has different values than protocols table)
- Inconsistency (knowledge_highlights queries JSON; system prompt queries DB + RAG; neither knows about the other)

---

## What the DB Already Has

`cryo_em_protocols` is already the right schema. Each of the 6 sample class rows holds:

```
key_principles   TEXT JSON   — array of learnable rules (e.g. "Saposin outperforms MSP for <60 kDa")
qc_gates         TEXT JSON   — [{name, criterion, action_if_fail}]
reference_papers TEXT JSON   — [{title, journal, year, doi}]
collection_params  TEXT JSON — pixel_size, defocus, dose, box_size
reconstitution_params TEXT JSON — lipid_mix, molar_ratio, stabilizer
picking_strategy TEXT JSON   — tool cascade, box_size, training needed
refinement_strategy TEXT JSON — symmetry, ctf_refine, local_refine
```

And `cryo_em_parameters` holds 58 MW-context rows (pixel_size, defocus, dose, box_size) indexed on `(context, parameter)`.

**The structured DB can serve best_practices, qc_thresholds, and literature directly** — it already has all three fields. The expert JSON is fully redundant for cryo-EM.

---

## What Text RAG Uniquely Contributes

Honest audit of the 150 chunks by type:

| Chunk type | Count | Can DB replace? | Reasoning |
|---|---|---|---|
| `general` | 48 | Partially | Decision trees can become DB lookup tables; framework narrative → `rationale` TEXT columns |
| `processing` | 38 | Mostly | Step-by-step protocols → structured `refinement_strategy`, `picking_strategy` JSON fields already exist |
| `study_design` | 20 | No | Hypothesis→design→findings narrative is free-form; no fixed schema can capture it |
| `gap_analysis` | 17 | Mostly | Tool gaps → `cryo_em_tools.biomate_gap_notes` already exists |
| `decision_tree` | 12 | Yes | Trees can become `sample_class_rules` table or parameterized JSON |
| `key_principle` | 4 | Yes | Already in `cryo_em_protocols.key_principles` JSON field |
| `reconstitution` | 4 | Yes | Already in `cryo_em_protocols.reconstitution_params` |
| `qc_gate` | 2 | Yes | Already in `cryo_em_protocols.qc_gates` |
| `failure_mode` | 1 | Partially | Can add `failure_modes` JSON array to protocols table |
| `model_building` | 4 | Mostly | Add `model_building` JSON field to protocols table |

**RAG irreplaceable portion: ~20 chunks** (study_design narrative, cross-publication comparisons, edge-case protocol variants)  
**DB can handle: ~130 chunks** if protocol table is complete

### The three genuine RAG contributions

**1. Narrative rationale** — *why* a protocol works, not just *what* the values are.  
Example: "Saposin A wraps tightly around the protein, minimizes empty lipid area, reduces nanodisc flexibility. Preferred over MSP for proteins < 60 kDa because…"  
→ A DB field stores the value `saposin`. The narrative explaining *why* requires text.

**2. Cross-publication synthesis** — a finding from paper 05 (μOR) validated by paper 06 (D1R), both using MSP1D1ΔH5 + apyrase, suggesting this is a class-level rule, not a one-off.  
→ DB stores facts per-protocol; RAG retrieves thematically across papers.

**3. Novel query phrasing** — user asks "my particles have preferred orientation on the grid" → no DB column captures "preferred orientation failure mode" as a key, but a chunk of type `failure_mode` does.  
→ This is the residual value of semantic search. Even a well-structured DB has fixed schema; user language is unbounded.

---

## The Right Architecture

### Principle: DB is the source of truth; RAG is a last-resort fallback

```
User query → classify intent
     │
     ├─ Can be answered by DB? (structured lookup)
     │   ├─ sample class known + MW known → cryo_em_protocols + cryo_em_parameters
     │   ├─ tool query → cryo_em_tools
     │   └─ QC threshold query → cryo_em_protocols.qc_gates
     │
     └─ Cannot be answered by DB? (semantic fallback)
         ├─ Cross-paper synthesis needed
         ├─ Narrative rationale needed
         └─ Failure mode / edge case
```

`knowledge_highlights` for cryo-EM should **query the DB directly**, not the expert JSON:

```python
def _build_knowledge_highlights_cryo_em(self, domain, workflow_name, tools):
    sample_class = self._infer_sample_class(workflow_name, tools)
    retriever = get_retriever()
    
    protocol = retriever.get_protocol(sample_class)  # cryo_em_protocols row
    qc_gates = json.loads(protocol['qc_gates'])
    key_principles = json.loads(protocol['key_principles'])
    refs = json.loads(protocol['reference_papers'])
    
    return {
        'best_practices': key_principles[:3],
        'qc_thresholds': [
            {'metric': g['name'], 'threshold': g['criterion'],
             'context': g.get('action_if_fail', ''),
             'source': refs[0]['doi'] if refs else ''}
            for g in qc_gates[:5]
        ],
        'literature_guidance': [
            {'url': r['doi'], 'context': r['title'][:60]} for r in refs[:3]
        ]
    }
```

RAG chunks become the **semantic fallback only**: queried when sample class can't be determined or when the user asks a question that doesn't map to any protocol key.

---

## What Needs Extracting from Publications into DB

The structured DB is already populated for 6 sample classes, but the extraction is incomplete. These fields are either empty, generic, or missing from the 9 publications:

### Per-protocol gaps (add to `cryo_em_protocols`)

**From publications → into existing JSON fields:**

| Field | Currently | Should be |
|---|---|---|
| `reconstitution_params.molar_ratio` | Missing for most | 1:10:200 (saposin:lipid:protein) from MFSD2B/VMAT2 papers |
| `reconstitution_params.lipid_mix` | Generic | POPC:POPE:POPG 3:1:1 (saposin); DOPC:DOPE:CL 4:3:1 (liposome) |
| `reconstitution_params.assembly_order` | Missing | 5-step GPCR: nanodiscs first, apyrase 0.02 U/mL, G protein, scFv16 last |
| `qc_gates` | Generic threshold values | Publication-specific pass/fail criteria with citations |
| `key_principles` | 1–3 generic rules | 4–8 rules per class from each paper's "BioMate Learnable Principles" section |
| `reference_papers` | Empty or placeholder | Actual DOIs from the 9 indexed publications |

**New JSON fields to add to `cryo_em_protocols`:**

```sql
-- Add to existing table
ALTER TABLE cryo_em_protocols ADD COLUMN failure_modes TEXT JSON;
-- [{symptom, cause, fix, source_paper}]

ALTER TABLE cryo_em_protocols ADD COLUMN heterogeneity_strategy TEXT JSON;
-- {classification_rounds, 3dva_used, expected_states, mask_strategy}

ALTER TABLE cryo_em_protocols ADD COLUMN local_refinement_recipe TEXT JSON;
-- [{region, mask_type, dilation_A, expected_improvement_A}]

ALTER TABLE cryo_em_protocols ADD COLUMN collection_notes TEXT;
-- Free text: special conditions (ice thickness, grid type rationale, stage tilt)
```

**New `cryo_em_benchmarks` table:**

```sql
CREATE TABLE cryo_em_benchmarks (
    id              INTEGER PRIMARY KEY,
    sample_class    TEXT REFERENCES cryo_em_protocols(sample_class),
    doi             TEXT,
    protein_name    TEXT,
    mw_kda          REAL,
    num_movies      INTEGER,
    num_particles_initial  INTEGER,
    num_particles_final    INTEGER,
    yield_percent   REAL,            -- particles_final / particles_initial
    final_resolution_A  REAL,
    ctf_strategy    TEXT,
    symmetry        TEXT,
    pixel_size      REAL
);
```

This replaces RAG chunks of type `processing` and `study_design` with queryable rows.

---

## Migration Plan

### Phase 1 — Wire `knowledge_highlights` to DB (stop using expert JSON for cryo-EM)

**File:** `backend/lib/galaxy/ai/ai_assistant.py`  
**Change:** Add cryo-EM branch in `_build_knowledge_highlights()`:

```python
if domain in ('cryo_em', 'cryo_et', 'bioimaging'):
    return self._build_cryo_em_highlights_from_db(workflow_name, tools)
else:
    # existing JSON path for all other domains
    return self._build_highlights_from_json(domain, workflow_name, tools)
```

This eliminates the expert JSON → scoring → extract loop for cryo-EM and replaces it with a direct DB lookup. The expert JSON becomes the cryo-EM fallback only when the DB has no matching protocol.

### Phase 2 — Complete protocol table population

Run a script that reads the 9 skill documents and populates:
- `cryo_em_protocols.key_principles` — from "BioMate Learnable Principles" sections
- `cryo_em_protocols.reference_papers` — from paper headers in each document
- `cryo_em_protocols.reconstitution_params` — molar ratios, lipid mixes
- `cryo_em_protocols.qc_gates` — publication-specific thresholds
- New `cryo_em_benchmarks` table — from Step 3 tables (particle counts, resolution)
- New `cryo_em_protocols.failure_modes` — from Gap Analysis sections

This extraction is **deterministic** — the values are already identified in the 9 markdown documents. It's a one-time populate script, not an LLM extraction job.

### Phase 3 — Narrow RAG scope

After Phase 1 and 2, RAG chunks are only needed for:
1. `study_design` chunks (~20) — narrative hypothesis→findings
2. Cross-publication comparisons
3. Queries involving failure modes and unusual edge cases

The 130 redundant chunks can be kept for backward compatibility but should no longer be the primary knowledge path.

---

## What Remains Different Between Cryo-EM and Other Domains

Other domains (genomics, drug_discovery, proteomics) have **no structured DB tables at all** — they use only the expert JSON files. Cryo-EM is the only domain with a proper retriever class and structured DB.

The right answer is not to make cryo-EM look like other domains — it's to make other domains look like cryo-EM:
- Each domain should have a `{domain}_protocols` table
- Each domain should have a retriever class with `get_protocol()`, `get_parameter()`
- The expert JSON files become the migration source, not the permanent home

For now, the priority is to stop the cryo-EM duplication (Phase 1) and complete the cryo-EM protocol table (Phase 2). The same pattern can then be applied to genomics, drug_discovery, etc. in subsequent sessions.

---

## Summary

| Question | Answer |
|---|---|
| What does RAG contribute that DB can't? | ~20/150 chunks: narrative rationale, cross-paper synthesis, failure mode / edge case queries |
| Is expert JSON redundant for cryo-EM? | Yes. `cryo_em_protocols` already has key_principles, qc_gates, reference_papers |
| Should knowledge_highlights query DB directly? | Yes — add cryo-EM branch that calls `retriever.get_protocol(sample_class)` |
| What's the unique value of two systems? | Nothing. One source of truth (DB) with text fallback (RAG) for unstructured queries |
| What needs extracting from publications? | Specific molar ratios, failure modes, benchmarks, local refinement recipes — into existing table columns |
| Is cryo-EM special vs other domains? | No — it's *ahead* of other domains. Other domains need the same DB structure |
