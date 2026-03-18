# Pipeline Composition Refactor Plan
**Date:** 2026-03-05
**Status:** Design — not started
**Staging folder:** `backend/biomni_workflows/pipeline_composition/`
**Prerequisite reading:** `20260305_CRYOEM_WORKFLOW_ARCHITECTURE.md`

---

## Problem Statement

BioMate has 20 cryo-EM/ET workflow files that are structurally isolated. Each is a closed system that takes file paths as params and writes outputs to a directory. Nothing records what a completed pipeline produced, nothing validates that an output from pipeline A is compatible with an input to pipeline B, and the AI has no reliable way to chain pipelines without manually constructing paths from conversation context.

This blocks three classes of scientific use:
1. **Sequential chains** — SPA → focused refinement → local refinement
2. **Fan-out** — SPA output → 3DVA simultaneously + symmetry expansion simultaneously
3. **Fan-in** — particles from two import sources → combined 3DVA
4. **Cross-team handoff** — Team A runs SPA; Team B runs downstream analysis on their outputs without re-running SPA

---

## Design Goals

1. Every completed pipeline run leaves a machine-readable record of what it produced and where
2. The AI can resolve input paths for a downstream pipeline from a prior run's record, without manual copy-paste
3. Compatible ports can be auto-wired; incompatible ports are caught before execution, not at runtime
4. The refactor does not break any existing pipeline — new machinery is additive
5. No code changes reach production until the staging folder passes its test suite

---

## Architecture: Three Layers

```
Layer 3: AI-level composition
  │  Reads manifests, matches port types, generates chained workflow artifacts
  │
Layer 2: Port schema registry
  │  Declares what each pipeline accepts and produces (typed ports)
  │
Layer 1: Output manifests
     Each completed pipeline writes workflow_outputs.json to its outdir
```

---

## Layer 1 — Output Manifests

### What

Every pipeline adds a final `PIPELINE_MANIFEST` process that writes `workflow_outputs.json` to `${params.outdir}/`:

```json
{
  "schema_version": "1.0",
  "pipeline_id": "cryosparc_standard_spa",
  "invocation_id": "inv_abc123",
  "completed_at": "2026-03-05T22:00:00.000Z",
  "outdir": "/results/spa_run_20260305/",
  "params": {
    "pixel_size": 1.05,
    "voltage": 300,
    "qc_profile": "cryoem_spa_standard"
  },
  "metrics": {
    "fsc_0143_resolution_angstroms": 3.2,
    "num_particles": 147000,
    "orientation_anisotropy_ratio": 2.1
  },
  "ports": {
    "particles_cs":          "17_homogeneous_refinement/refined_volume.cs",
    "particles_ctf_refined": "20_local_ctf_refinement/particles_ctf_refined.cs",
    "volume_cs":             "17_homogeneous_refinement/refined_volume.cs",
    "nu_refined_volume":     "21_non_uniform_refinement/nu_refined_volume.cs",
    "sharpened_map":         "23_sharpening/sharpened_map.cs",
    "fsc_report":            "19_validation_fsc/validation_report.json",
    "local_resolution_map":  "22_local_resolution/local_resolution.cs"
  }
}
```

All port paths are relative to `outdir` — the manifest is portable if the directory is moved.

### Schema (JSON Schema)

Defined at: `pipeline_composition/manifests/manifest_schema.json`

Key constraints:
- `schema_version` required
- `pipeline_id` must match a registered pipeline in the registry
- `ports` keys must match the pipeline's declared output port names
- `ports` values are relative paths to files that must exist at manifest write time

### Nextflow implementation

```nextflow
process PIPELINE_MANIFEST {
    publishDir "${params.outdir}", mode: 'copy', overwrite: true

    input:
    path sharpened_cs
    path fsc_report
    path refinement_report

    output:
    path "workflow_outputs.json"

    script:
    """
    #!/usr/bin/env python3
    import json, os
    from datetime import datetime, timezone

    fsc = json.load(open('${fsc_report}'))
    refine = json.load(open('${refinement_report}'))

    manifest = {
        "schema_version": "1.0",
        "pipeline_id": "cryosparc_standard_spa",
        "invocation_id": "${params.invocation_id ?: 'unknown'}",
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "outdir": "${params.outdir}",
        "params": {
            "pixel_size":  float("${params.pixel_size}"),
            "voltage":     int("${params.voltage}"),
            "qc_profile":  "${params.qc_profile ?: 'cryoem_spa_standard'}",
        },
        "metrics": {
            "fsc_0143_resolution_angstroms": fsc.get("fsc_0143_resolution"),
            "num_particles":                 refine.get("num_particles"),
            "orientation_anisotropy_ratio":  refine.get("orientation_anisotropy_ratio"),
        },
        "ports": {
            "particles_ctf_refined": "20_local_ctf_refinement/particles_ctf_refined.cs",
            "volume_cs":             "17_homogeneous_refinement/refined_volume.cs",
            "nu_refined_volume":     "21_non_uniform_refinement/nu_refined_volume.cs",
            "sharpened_map":         "23_sharpening/sharpened_map.cs",
            "fsc_report":            "19_validation_fsc/validation_report.json",
        }
    }
    json.dump(manifest, open('workflow_outputs.json', 'w'), indent=2)
    """
}
```

---

## Layer 2 — Port Schema Registry

### What

A single JSON file declares every pipeline's typed input and output ports:

```json
// pipeline_composition/registry/pipeline_registry.json
{
  "pipelines": {
    "cryosparc_standard_spa": {
      "description": "Standard 23-step SPA: movies → sharpened map",
      "entrypoint": "nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf",
      "inputs": {
        "movies_path":   { "type": "path",         "required": true  },
        "pixel_size":    { "type": "float",         "required": true  },
        "voltage":       { "type": "int",           "required": true  },
        "qc_profile":    { "type": "profile_name",  "required": false, "default": "cryoem_spa_standard" }
      },
      "outputs": {
        "particles_ctf_refined": { "type": "cryosparc_cs", "description": "CTF-refined particle stack" },
        "volume_cs":             { "type": "cryosparc_cs", "description": "Homogeneous refined volume" },
        "nu_refined_volume":     { "type": "cryosparc_cs", "description": "Non-uniform refined volume" },
        "sharpened_map":         { "type": "cryosparc_cs", "description": "Final sharpened map" },
        "fsc_report":            { "type": "json",         "description": "FSC curve + 0.143 resolution" }
      }
    },
    "particle_subtraction": {
      "description": "Subtract out-of-mask signal for focused refinement",
      "entrypoint": "nextflow_nfcore/subworkflows/cryo_em/particle_subtraction/main.nf",
      "inputs": {
        "particles_cs": { "type": "cryosparc_cs", "required": true },
        "volume_cs":    { "type": "cryosparc_cs", "required": true }
      },
      "outputs": {
        "subtracted_particles_cs": { "type": "cryosparc_cs", "description": "Signal-subtracted particles" },
        "subtraction_report":      { "type": "json" }
      }
    },
    "local_refinement": {
      "inputs": {
        "subtracted_particles_cs": { "type": "cryosparc_cs", "required": true },
        "volume_cs":               { "type": "cryosparc_cs", "required": true }
      },
      "outputs": {
        "local_refined_volume": { "type": "cryosparc_cs" },
        "local_refinement_report": { "type": "json" }
      }
    },
    "3d_variability_analysis": {
      "inputs": {
        "particles_cs": { "type": "cryosparc_cs", "required": true },
        "volume_cs":    { "type": "cryosparc_cs", "required": true }
      },
      "outputs": {
        "particles_with_latent": { "type": "cryosparc_cs" },
        "component_maps":        { "type": "cryosparc_cs[]" },
        "3dva_report":           { "type": "json" }
      }
    },
    "symmetry_expansion": {
      "inputs": {
        "particles_cs": { "type": "cryosparc_cs", "required": true },
        "volume_cs":    { "type": "cryosparc_cs", "required": true }
      },
      "outputs": {
        "symmetry_expanded_particles_cs": { "type": "cryosparc_cs" },
        "symmetry_expansion_report":      { "type": "json" }
      }
    },
    "helical_spa_pipeline": {
      "inputs": {
        "movies_path":              { "type": "path",  "required": true },
        "helical_rise_angstroms":   { "type": "float", "required": true },
        "helical_twist_deg":        { "type": "float", "required": true }
      },
      "outputs": {
        "helical_volume":              { "type": "cryosparc_cs" },
        "helical_refinement_report":   { "type": "json" }
      }
    },
    "et_full_pipeline": {
      "inputs": {
        "input_dir": { "type": "path", "required": true },
        "pixel_size": { "type": "float", "required": true },
        "voltage":    { "type": "int",   "required": true }
      },
      "outputs": {
        "sta_map":            { "type": "mrc_volume" },
        "sta_report":         { "type": "json" },
        "et_pipeline_summary":{ "type": "json" }
      }
    }
  },
  "type_compatibility": {
    "cryosparc_cs": ["cryosparc_cs"],
    "mrc_volume":   ["mrc_volume"],
    "json":         ["json"],
    "path":         ["path"],
    "float":        ["float", "int"],
    "int":          ["int"]
  }
}
```

### Auto-wiring rule

Two ports are **compatible** when their types match per `type_compatibility`. The AI uses this to auto-suggest connections:

```
cryosparc_standard_spa.outputs.volume_cs [type: cryosparc_cs]
       ↕ compatible
particle_subtraction.inputs.volume_cs    [type: cryosparc_cs]  ✓ auto-wire
local_refinement.inputs.volume_cs        [type: cryosparc_cs]  ✓ auto-wire
3d_variability_analysis.inputs.volume_cs [type: cryosparc_cs]  ✓ auto-wire
```

---

## Layer 3 — AI-Level Composition

### Manifest resolver endpoint

```
GET /api/nextflow/invocations/{invocation_id}/manifest
```

Returns `workflow_outputs.json` for a completed run. The AI uses this when generating a downstream workflow artifact.

### Example composition flow

User: *"Now run focused refinement on that SPA result"*

```python
# AI reasoning:
# 1. Find prior SPA invocation in conversation context → "inv_abc123"
# 2. Call GET /api/nextflow/invocations/inv_abc123/manifest
# 3. Find port "particles_ctf_refined" → "20_local_ctf_refinement/particles_ctf_refined.cs"
# 4. Find port "volume_cs" → "17_homogeneous_refinement/refined_volume.cs"
# 5. Look up particle_subtraction in registry → requires these exact port types ✓
# 6. Generate workflow artifact:
{
  "nextflow_path": ".../particle_subtraction/main.nf",
  "parameters": {
    "particles_cs": "/results/spa_abc123/20_local_ctf_refinement/particles_ctf_refined.cs",
    "volume_cs":    "/results/spa_abc123/17_homogeneous_refinement/refined_volume.cs",
    "outdir":       "/results/focused_refinement_abc123/"
  },
  "upstream_invocation_id": "inv_abc123",
  "upstream_port_mapping": {
    "particles_cs": "particles_ctf_refined",
    "volume_cs": "volume_cs"
  }
}
```

### Fan-out (parallel downstream)

User: *"Run 3DVA and focused refinement on the SPA outputs simultaneously"*

The AI generates **two workflow artifacts** in the same response, both resolved from the same manifest. Nextflow executes them independently and in parallel.

### Fan-in (multiple upstreams)

User: *"Combine the particles from the TRPV1 SPA run and the imported RELION dataset for joint 3DVA"*

```python
# Manifest A: cryosparc_standard_spa → particles_ctf_refined (50k particles)
# Manifest B: import_particles → particles_imported (30k particles)
# Both have type cryosparc_cs
# 3dva input "particles_cs" accepts cryosparc_cs
# → AI generates a MERGE_PARTICLES step first, then 3DVA
```

---

## Implementation Plan

### Staging folder (do not touch production until tests pass)

```
backend/biomni_workflows/pipeline_composition/
  README.md                         ← this plan, brief
  registry/
    pipeline_registry.json          ← port schema for all pipelines
  manifests/
    manifest_schema.json            ← JSON Schema for workflow_outputs.json
  modules/                          ← extracted individual process .nf files (Phase 3)
    cryosparc/
      import_movies.nf
      patch_motion_correction.nf
      patch_ctf_estimation.nf
      ... (one per process)
  pipelines/                        ← refactored pipelines that use include (Phase 3)
    cryosparc_standard_spa/
      main.nf                       ← uses include from modules/
    helical_spa_pipeline/
      main.nf                       ← uses include from modules/
  tests/
    test_manifest_schema.py         ← validates manifest_schema.json
    test_registry.py                ← validates pipeline_registry.json completeness
    test_manifest_generation.py     ← runs a mock pipeline; checks workflow_outputs.json
    test_port_compatibility.py      ← checks all SPA→advanced connections are valid
    test_resolver.py                ← tests manifest resolver API endpoint
```

### Phase 1 — Manifests (Week 1)

**Goal:** Every pipeline writes `workflow_outputs.json`. No code changes to production pipelines.

1. Create `manifests/manifest_schema.json` (JSON Schema)
2. Create `PIPELINE_MANIFEST` process template in `pipeline_composition/modules/pipeline_manifest.nf`
3. Copy `cryosparc_standard_spa/main.nf` → `pipeline_composition/pipelines/cryosparc_standard_spa/main.nf`, add manifest process
4. Same for `helical_spa_pipeline`, `et_full_pipeline`, and all standalone modules
5. Write `tests/test_manifest_generation.py`: run each pipeline in mock mode, validate the manifest

**Promotion criteria:** All 20 pipelines produce valid manifests (pass JSON Schema validation) in mock mode.

### Phase 2 — Registry (Week 1–2)

**Goal:** `pipeline_registry.json` is complete and port compatibility is testable.

1. Write `registry/pipeline_registry.json` for all 20 pipelines
2. Write `tests/test_registry.py`:
   - Every pipeline in `cryo_em/` and `cryo_et/` has a registry entry
   - Every declared output port has a matching key in the pipeline's manifest output
   - All `cryosparc_standard_spa` outputs are compatible with at least one downstream pipeline input
3. Write `tests/test_port_compatibility.py`: exhaustively test all upstream→downstream port connections

**Promotion criteria:** Registry passes all tests; `test_port_compatibility.py` documents every valid chain.

### Phase 3 — Module extraction (Week 2–3)

**Goal:** Eliminate code duplication. IMPORT_MOVIES, PATCH_MOTION_CORRECTION, PATCH_CTF_ESTIMATION defined once; both SPA monolith and helical pipeline `include` them.

1. Extract each of the 23 SPA processes to `pipeline_composition/modules/cryosparc/{process_name}.nf`
2. Rewrite `pipeline_composition/pipelines/cryosparc_standard_spa/main.nf` to use `include`
3. Rewrite `pipeline_composition/pipelines/helical_spa_pipeline/main.nf` to use `include`
4. Verify both produce identical mock outputs to the originals (regression test)

**Promotion criteria:** Both refactored pipelines produce byte-identical mock outputs to the originals. QC gate tests pass (`pytest backend/tests/test_qc_e2e_domains.py -k cryoem`).

### Phase 4 — Manifest resolver API (Week 3–4)

**Goal:** `GET /api/nextflow/invocations/{id}/manifest` returns the manifest for a completed run.

1. Store manifest content in the Nextflow invocation database record when the monitor receives the pipeline summary event
2. Add API endpoint to `nextflow_executor_v2.py`
3. Add AI context enrichment: when generating a downstream workflow artifact, the AI checks for a compatible upstream manifest in the conversation

**Promotion criteria:** E2E test: run SPA in mock mode → call manifest API → generate focused refinement workflow with auto-resolved paths → run focused refinement.

### Phase 5 — Promote to production (Week 4–5)

Replace production files with the tested staged versions:

```bash
# Only after all tests pass
cp pipeline_composition/pipelines/cryosparc_standard_spa/main.nf \
   nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf

cp pipeline_composition/pipelines/helical_spa_pipeline/main.nf \
   nextflow_nfcore/subworkflows/cryo_em/helical_spa_pipeline/main.nf

# For standalone modules: add PIPELINE_MANIFEST to each
for module in particle_subtraction local_refinement 3d_variability_analysis \
              symmetry_expansion global_ctf_refinement filament_tracer \
              helical_refinement topaz_train topaz_extract \
              import_micrographs import_particles; do
  cp pipeline_composition/pipelines/${module}/main.nf \
     nextflow_nfcore/subworkflows/cryo_em/${module}/main.nf
done
```

---

## What This Does NOT Change

- QC governance (`qc_trace_monitor.py`) — unchanged; it already reads JSON reports
- AI assistant flow — unchanged; still generates `nextflow_path` + params; only adds manifest resolution
- Frontend — unchanged in Phase 1–3; Phase 4 adds manifest lookup on the backend
- Galaxy integration — unchanged
- All existing tests — must continue to pass at every phase

---

## Testing Checklist Before Any Phase Promotes

| Test | Command | Must pass |
|---|---|---|
| QC gate unit tests | `pytest backend/tests/test_qc_e2e_domains.py -k cryoem` | 213/213 |
| Manifest schema validation | `pytest pipeline_composition/tests/test_manifest_schema.py` | all |
| Registry completeness | `pytest pipeline_composition/tests/test_registry.py` | all |
| Port compatibility matrix | `pytest pipeline_composition/tests/test_port_compatibility.py` | all |
| Mock pipeline runs | `pytest pipeline_composition/tests/test_manifest_generation.py` | all 20 pipelines |
| Regression vs originals | `pytest pipeline_composition/tests/test_regression.py` | identical outputs |

---

## Open Questions

1. **Where are manifests stored long-term?** Options: (a) file-system only (easy, no DB change), (b) stored in Galaxy job record (searchable, requires DB migration), (c) stored in BioMate Nextflow invocation table (cleanest). Recommendation: (c), already have the invocation table.

2. **Multi-tenant manifests.** If two users run SPA, they must not see each other's manifests. The manifest resolver must check `invocation_id` belongs to the requesting user's session.

3. **ET → SPA chaining.** STA maps are `.mrc`, not `.cs`. `local_refinement` expects `cryosparc_cs`. A `CONVERT_MRC_TO_CS` adapter module would be needed to chain ET → local refinement. This is out of scope for Phase 1–4.

4. **Version pinning.** If `cryosparc_standard_spa` is updated, old manifests reference its previous port layout. The manifest must store the pipeline version (git commit or semver tag).
