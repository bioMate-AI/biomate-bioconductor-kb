# Workflow Chain Extension Plan
**Date:** 2026-06-23  
**Status:** Approved for implementation  
**Tracks:** 3 parallel (A, B, C)

---

## Background

BioMate has a 3-tier workflow chain system:
- **Tier 0** curated chains (36 in DB, embedding + LLM search)
- **Bioconductor reactive chains** (6 in `bioc_chain_templates.py`, trigger on run completion)
- **Chain planner** prototype (`chain_planner.py`, not yet wired to production)

Three concrete gaps block production usefulness:

| Gap | Root cause | Impact |
|-----|-----------|--------|
| `suggest_chains_for_run()` never called | Dead code — function exists, zero call sites | Post-run "what next?" suggestions never fire |
| No context propagation between chain steps | `connections[]` has port names but no runtime param inheritance | rnaseq→DESeq2 chain doesn't know which aligner was used |
| Zero cryo-EM chains | 23 individual cryo-EM workflows, 0 chains | Users can't discover the standard SPA→refinement→validation pipeline |

---

## Use Cases

### UC-1: Bulk RNA-seq → DE (the canonical two-step)
**User:** "Run nf-core/rnaseq on my samples"  
**Current:** BioMate runs rnaseq, shows count matrix output. Silent on next steps.  
**Target:** After rnaseq completes, BioMate proactively suggests:
> "Your rnaseq run produced `salmon.merged.gene_counts.tsv`. Ready to run differential expression?  
> → **Bulk RNA-seq → DE → Pathway Enrichment** (DESeq2 + clusterProfiler, 3 steps)"

Context propagation: the DESeq2 step pre-fills `counts_file` with the actual output path and `organism` with the genome param used in rnaseq.

---

### UC-2: Ambiguous "I already have counts"
**User:** "Run differential expression on my count matrix"  
**Current:** Routing might select `bulk_rnaseq_de_analysis` (starts from FASTQ) OR `bioc_bulk_rnaseq_de_v2` (starts from counts matrix) — no disambiguation.  
**Target:** Router detects no FASTQ mentioned → selects `bioc_bulk_rnaseq_de_v2` directly, pre-fills `count_matrix` param with the uploaded file.

---

### UC-3: ChIP-seq post-peak annotation
**User:** Runs `nf-core/chipseq`  
**Target:** After completion, BioMate suggests:
> "Your ChIP-seq produced `*.broadPeak` files. Annotate peaks to genes and run GO enrichment?  
> → **ChIP-seq Peaks → Gene Annotation → Pathway Enrichment** (ChIPseeker + clusterProfiler)"

---

### UC-4: Cryo-EM standard refinement pipeline
**User:** "I finished my cryoSPARC SPA run, what should I do next?"  
**Current:** BioMate can run individual atomic steps (3D classification, focused refinement, etc.) but has no chain to sequence them.  
**Target:** BioMate suggests:
> "**Standard Cryo-EM Refinement Pipeline** (5 steps):  
> 3D Classification → Focused Refinement → Local Refinement → CTF Refinement → DeepEMhancer map sharpening"  
> Required inputs: `.cs` particle stack + `.mrc` reference map

---

### UC-5: Cryo-EM conformational heterogeneity
**User:** "My protein has multiple conformational states — analyze the heterogeneity"  
**Target:**
> "**Cryo-EM Conformational Heterogeneity Pipeline** (3 steps):  
> 3D Variability Analysis → cryoDRGN latent space → Conformational landscape visualization"  
> Required: `.cs` particles from cryoSPARC SPA

---

### UC-6: Cryo-EM model building and validation
**User:** "I have a refined map at 3.2Å, build and validate the atomic model"  
**Target:**
> "**Cryo-EM Model Building & Validation** (3 steps):  
> Phenix AutoBuild → MolProbity validation → ISOLDE/Coot refinement"  
> Required: `.mrc` sharpened map + sequence FASTA

---

### UC-7: Variant calling → functional annotation
**User:** Runs `nf-core/sarek`  
**Target:** After VCF output, suggest:
> "**Variant Functional Annotation** (2 steps):  
> VariantAnnotation (VCF → gene assignment) → clusterProfiler (hit gene pathway enrichment)"

---

## Architecture

### Track A — Cryo-EM chains

**New file:** `backend/lib/galaxy/ai/cryoem_chain_templates.py`  
Mirror structure of `bioc_chain_templates.py`. Three chains:

```
cryoem_standard_refinement:
  steps: [3d_classification, focused_refinement, local_refinement,
          global_ctf_refinement, deepemhancer_post_processing]
  trigger_on_workflows: [cryosparc_standard_spa, relion, cistem]
  trigger_on_output_extensions: [cs, mrc, mrcs, star]

cryoem_conformational_heterogeneity:
  steps: [3d_variability_pipeline, cryodrgn]
  trigger_on_workflows: [cryosparc_standard_spa, 3d_variability_analysis]
  trigger_on_output_extensions: [cs, star]

cryoem_model_building:
  steps: [phenix_autobuild, molprobity_validation, coot_refinement]
  trigger_on_workflows: [deepemhancer_post_processing, local_refinement,
                         focused_refinement_pipeline]
  trigger_on_output_extensions: [mrc, map]
```

**DB registration:** call `register_cryoem_chains()` alongside `register_bioc_chains()` in Galaxy startup (`ai_assistant.py` `__init__` or `startup_tasks`).

**Workflow name resolution:** The `steps[].workflow_name` must match entries in `workflows` table. Mapping:

| Chain step name | DB workflow name |
|----------------|-----------------|
| `3d_variability_pipeline` | `3D Variability Pipeline` |
| `deepemhancer_post_processing` | `DeepEMhancer Post-Processing` |
| `cryosparc_standard_spa` | `CryoSPARC Standard Single-Particle Analysis` |
| `focused_refinement_pipeline` | `Focused Refinement Pipeline` |
| `local_refinement` | `Local Refinement` |
| `global_ctf_refinement` | `Global Ctf Refinement` |
| `cryodrgn` | `Cryo-EM Conformational Heterogeneity (cryoDRGN)` |
| `relion_multi_body_refinement` | `RELION Multi-Body Refinement` |

---

### Track B — Post-completion chain suggestion wiring

**Hook point:** `nextflow_executor.py:3485`
```python
# EXISTING
if final_status == "completed" or returncode == 0:
    _narrate_chat(_inv_id, "workflow.completed", {...})

# ADD AFTER
if final_status == "completed" and _inv_id:
    _fire_chain_suggestions(run_id, workflow_name, _inv_id)
```

**New function `_fire_chain_suggestions()`:**
```python
def _fire_chain_suggestions(run_id, workflow_name, invocation_id):
    # 1. Collect output file extensions from run outdir
    output_exts = _collect_output_extensions(run_id)
    # 2. Query suggest_chains_for_run() from both bioc + cryoem templates
    from galaxy.ai.bioc_chain_templates import suggest_chains_for_run as _bioc_suggest
    from galaxy.ai.cryoem_chain_templates import suggest_chains_for_run as _cryoem_suggest
    suggestions = _bioc_suggest(workflow_name, output_exts) + \
                  _cryoem_suggest(workflow_name, output_exts)
    if not suggestions:
        return
    # 3. Emit SSE chain_suggestion event (max 2 suggestions)
    _post_sse_direct(invocation_id, "chain_suggestion", {
        "trigger_workflow": workflow_name,
        "suggestions": [
            {"name": s["name"], "display_name": s["display_name"],
             "steps": len(s["steps"]), "required_inputs": s["required_inputs"]}
            for s in suggestions[:2]
        ]
    })
```

**Frontend (`galaxy-assistant.ts`):** Add handler for `chain_suggestion` SSE event type.
Currently `needsChainProposal` flag exists but is never acted on (line 1303). Wire it:

```typescript
// In SSE event handler, when event_type === 'chain_suggestion':
// Append a ProposedChainCard message to the chat stream
// (same component used by Tier 2 chain rendering)
```

**`_post_sse_direct()`:** The existing `_post_sse` closure is scoped inside `_narrate_chat`. Extract it to a module-level helper that can be called from `_fire_chain_suggestions`.

---

### Track C — Context propagation + routing fix

**Schema change:** Add `context_params` field to each connection in `workflow_chains.connections`:
```json
{
  "from_step": 1,
  "from_output": "counts_matrix",
  "to_step": 2,
  "to_input": "count_matrix",
  "context_params": {
    "organism": {"from_run_param": "genome", "transform": "genome_to_organism"}
  }
}
```

**Executor change:** In `workflow_chain.py`, when launching step N, resolve `context_params` from step N-1's run record before building the params dict.

**Transform registry** (small lookup dict):
```python
_PARAM_TRANSFORMS = {
    "genome_to_organism": {
        "GRCh38": "hsa", "GRCh37": "hsa",
        "GRCm39": "mmu", "GRCm38": "mmu",
    }
}
```

**Routing disambiguation** (`ai_assistant.py`):  
When the user's query contains `count_matrix`, `counts.tsv`, `gene_counts`, or `already have counts` → set `preliminary_score_boost = +20` for chains with `required_inputs = ["count_matrix"]` (bioc_* chains), steering away from full FASTQ chains.

---

## E2E Tests

### Test B1 — Chain suggestion fires after rnaseq completion
**File:** `scripts/test_chain_suggestion_e2e.sh`  
**Setup:** POST `/api/nextflow/run` with nf-core/rnaseq params (or mock a completed run in the run state store with `workflow_name=rnaseq`, `status=completed`, known output files ending in `.tsv`)  
**Assertion:**
1. SSE stream contains event `event_type=chain_suggestion`
2. `suggestions[0].name` == `bioc_bulk_rnaseq_de_v2`
3. `suggestions[0].steps` == 3
4. No suggestion fires for a `failed` run (negative test)

### Test B2 — Chain suggestion fires after chipseq completion
**Setup:** Mock completed chipseq run with `.broadPeak` outputs  
**Assertion:** `suggestions[0].name` == `bioc_chipseq_annotation_v2`

### Test B3 — Chain suggestion fires after cryoSPARC SPA
**Setup:** Mock completed `cryosparc_standard_spa` run with `.cs` + `.mrc` outputs  
**Assertion:** `suggestions` contains `cryoem_standard_refinement` and `cryoem_conformational_heterogeneity`

### Test B4 — No false-positive chain suggestions
**Setup:** Mock completed `nf-core/mag` run (metagenomics, no chain triggers it)  
**Assertion:** SSE stream does NOT contain `chain_suggestion` event

---

### Test A1 — Cryo-EM chains register correctly
**File:** `backend/tests/test_cryoem_chains.py`  
```python
def test_register_cryoem_chains():
    register_cryoem_chains(db_path=TEST_DB)
    conn = sqlite3.connect(TEST_DB)
    names = {r[0] for r in conn.execute("SELECT name FROM workflow_chains WHERE domain='cryo_em'")}
    assert "cryoem_standard_refinement" in names
    assert "cryoem_conformational_heterogeneity" in names
    assert "cryoem_model_building" in names

def test_cryoem_steps_resolve_to_db_workflows():
    # Each step.workflow_name must exist in the workflows table
    conn = sqlite3.connect(PROD_DB)
    wf_names = {r[0].lower() for r in conn.execute("SELECT name FROM workflows")}
    for chain in CRYOEM_CHAIN_TEMPLATES:
        for step in chain["steps"]:
            assert step["workflow_name"].lower() in wf_names, \
                f"Step '{step['workflow_name']}' not in workflows table"

def test_suggest_chains_for_cryosparc():
    matches = suggest_chains_for_run("cryosparc_standard_spa", ["cs", "mrc"])
    names = [m["name"] for m in matches]
    assert "cryoem_standard_refinement" in names
    assert "cryoem_conformational_heterogeneity" in names
```

### Test A2 — Cryo-EM chain search via API
**File:** `scripts/test_cryoem_chain_search.sh`  
POST `/api/ai_assistant/generate_workflow` with body `{"query": "I finished my cryoSPARC SPA, what should I do next for refinement?"}`  
**Assertion:**
1. `workflow_type == "chain"` in response
2. `chain.name == "cryoem_standard_refinement"`
3. `chain.steps` has at least 3 entries
4. `steps[0].workflow_name` resolves to a `nextflow_path`

---

### Test C1 — Context param propagation in rnaseq→DESeq2 chain
**File:** `backend/tests/test_chain_context_params.py`  
```python
def test_context_params_genome_to_organism():
    # Simulate step 1 completing with genome=GRCh38
    step1_run = {"params": {"genome": "GRCh38"}, "status": "completed"}
    resolved = resolve_context_params(
        connection={"context_params": {"organism": {"from_run_param": "genome",
                                                     "transform": "genome_to_organism"}}},
        prev_run=step1_run
    )
    assert resolved["organism"] == "hsa"

def test_context_params_grch37_also_hsa():
    step1_run = {"params": {"genome": "GRCh37"}}
    resolved = resolve_context_params(
        connection={"context_params": {"organism": {"from_run_param": "genome",
                                                     "transform": "genome_to_organism"}}},
        prev_run=step1_run
    )
    assert resolved["organism"] == "hsa"
```

### Test C2 — Routing selects bioc chain when user has counts
POST `/api/ai_assistant/generate_workflow` with `{"query": "run differential expression on my count matrix gene_counts.tsv"}`  
**Assertion:**
1. `chain.name == "bioc_bulk_rnaseq_de_v2"` (NOT `bulk_rnaseq_de_analysis`)
2. `chain.required_inputs` contains `count_matrix`

### Test C3 — Routing selects full chain when user has FASTQ
POST with `{"query": "run RNA-seq differential expression from my FASTQ files"}`  
**Assertion:** `chain.name == "bulk_rnaseq_de_analysis"` (starts from FASTQ)

---

## Evaluation Metrics

| Metric | How measured | Target |
|--------|-------------|--------|
| Chain suggestion recall | Out of 7 defined triggers (rnaseq, chipseq, sarek, cellranger, cryosparc×3), how many fire the correct chain suggestion | ≥ 6/7 |
| Chain suggestion precision | Of all `chain_suggestion` SSE events fired, what fraction are for the correct domain | ≥ 90% |
| Cryo-EM chain search accuracy | POST `/api/ai_assistant/generate_workflow` for 6 cryo-EM queries (UC-4 to UC-6 × 2 variants each), fraction returning `workflow_type=chain` with correct chain name | ≥ 5/6 |
| Context propagation correctness | 4 genome values (GRCh38, GRCh37, GRCm39, GRCm38) transformed to correct organism code | 4/4 |
| Bioc routing accuracy | 10 queries split evenly between "have FASTQ" and "have counts" — fraction routed to correct chain | ≥ 9/10 |
| No regression on existing 36 chains | Run existing chain search smoke tests | 36/36 pass |
| SSE latency | Time from run completion event to `chain_suggestion` SSE event | < 500ms |

---

## Work Streams (Parallel)

### Track A: Cryo-EM Chains
**Files touched:**
- `backend/lib/galaxy/ai/cryoem_chain_templates.py` — NEW
- `backend/lib/galaxy/ai/ai_assistant.py` — add `register_cryoem_chains()` call at startup
- `backend/tests/test_cryoem_chains.py` — NEW

**Does NOT touch:** executor, frontend, bioc templates, workflow_chain.py

**Acceptance:** Tests A1 + A2 pass; `cryoem_standard_refinement` returned for query "what to do after cryoSPARC SPA"

---

### Track B: Post-completion suggestion wiring
**Files touched:**
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — add `_fire_chain_suggestions()` + hook at line ~3486; extract `_post_sse_direct()`
- `frontend/server/galaxy-assistant.ts` — handle `chain_suggestion` SSE event type

**Does NOT touch:** chain templates, workflow_chain.py, routing logic

**Acceptance:** Tests B1–B4 pass; manual: run rnaseq → SSE stream shows chain suggestion card in chat

---

### Track C: Context propagation + routing fix
**Files touched:**
- `backend/lib/galaxy/ai/workflow_chain.py` — add `context_params` resolution in step launcher
- `backend/lib/galaxy/ai/bioc_chain_templates.py` — add `context_params` to rnaseq→DESeq2 and sarek→VEP connections
- `backend/lib/galaxy/ai/ai_assistant.py` — add count_matrix routing signal boost
- `backend/tests/test_chain_context_params.py` — NEW

**Does NOT touch:** executor (beyond the context_params resolution), cryoem templates, SSE wiring

**Acceptance:** Tests C1–C3 pass; `bioc_bulk_rnaseq_de_v2` correctly routed when user says "count matrix"

---

## Pre-sync checklist (for all tracks)
1. `cd frontend && npx tsc --noEmit -p .`
2. `cd frontend && npx vitest run`
3. For any modified `backend/lib/galaxy/**/*.py`: `python3.9 -c "import galaxy.webapps.galaxy.api.<module>"`
4. `python3 backend/tests/test_cryoem_chains.py` (Track A)
5. `python3 backend/tests/test_chain_context_params.py` (Track C)
6. Then `scripts/sync_to_dev.sh`

---

## Open questions / deferred

- **Model building tools** (Phenix, Coot, MolProbity): are these already indexed as BioMate workflows? If not, Track A should stub them as placeholder workflow entries before wiring into the chain. Check: `SELECT name FROM workflows WHERE name LIKE '%phenix%' OR name LIKE '%molprobity%' OR name LIKE '%coot%'`.
- **`suggest_chains_for_run()` deduplication**: if a user manually asks for a chain AND the auto-suggestion fires, prevent duplicate chain cards. Needs a `seen_chain_names` set in the SSE session context.
- **Chain step ordering UI**: the frontend renders chain steps but currently shows no data-flow diagram. Separate UX work, not in scope here.
