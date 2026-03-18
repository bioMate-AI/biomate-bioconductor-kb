# Cryo-EM Gap Implementation — Test Documentation
**Date:** 2026-03-05
**Branch:** `connection_formal`
**Reviewer:** (colleague)
**Files changed:** 9 files modified, 7 files created

---

## Overview

This session closed 6 gaps between the aspirational cryo-EM researcher business document and the codebase. The gaps were identified by auditing `research_repos/cryo_em_benchmark_paper/20260305_BIOMATE_FOR_CRYOEM_RESEARCHERS.md` against the actual code.

| Gap | Description | Files |
|-----|-------------|-------|
| 1 | Restore aspirational business document | `research_repos/cryo_em_benchmark_paper/20260305_BIOMATE_FOR_CRYOEM_RESEARCHERS.md` |
| 2 | Add `cryoem_spa_standard` + `cryoem_spa_lowdose` QC profiles | `qc_trace_monitor.py` |
| 3 | Orientation anisotropy metric extraction + gate | `qc_trace_monitor.py`, `cryosparc_standard_spa/main.nf` |
| 4 | Cryo-ET pipeline — 5 Nextflow modules | `subworkflows/cryo_et/` (new) |
| 5 | Mol\* 3D structure viewer (PDB/CIF) | `viewers/structure-viewer.tsx` (new) |
| 6 | MRC density map slice viewer | `viewers/density-map-viewer.tsx` (new) |

A post-implementation audit found and fixed one **FAIL** (FSC key mismatch) and three **WARNs** (citation quality, pixel_size propagation in cryo-ET). See §8 for audit details.

---

## 1. File Inventory

### Modified files

| File | Change summary |
|------|---------------|
| `backend/lib/galaxy/jobs/qc_trace_monitor.py` | +2 named profiles, +orientation anisotropy extraction, +orientation anisotropy gate, +TILT_ALIGNMENT dispatch + parser, +STA parser + gate, +FSC key aliases fix, +reference cleanup |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf` | HOMOGENEOUS_REFINEMENT mock now emits `orientation_anisotropy_ratio` |
| `frontend/client/src/components/viewers/index.ts` | Added exports for `StructureViewer` and `DensityMapViewer` |
| `frontend/client/src/components/chat-output-attachments.tsx` | Added `structure` + `density_map` grouping sections, switch cases, import |
| `frontend/shared/schema.ts` | fileType enum extended with `'structure'` and `'density_map'` |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/tilt_alignment/main.nf` | Propagates `pixel_size_angstroms` + `voltage_kv` into report |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/et_full_pipeline/main.nf` | Same pixel_size fix in inlined TILT_ALIGNMENT process |

### New files

| File | Purpose |
|------|---------|
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/import_tiltseries/main.nf` | Process IMPORT_TILTSERIES — MDOC/MRC tilt series import |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/tilt_alignment/main.nf` | Process TILT_ALIGNMENT — AreTomo2/IMOD alignment, per-tilt residuals |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/tomogram_reconstruction/main.nf` | Process TOMOGRAM_RECONSTRUCTION — WBP/SIRT back-projection |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/subtomogram_averaging/main.nf` | Process SUBTOMOGRAM_AVERAGING — STA with per-round FSC |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/et_full_pipeline/main.nf` | Orchestrator: all 4 processes + ET_PIPELINE_SUMMARY |
| `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/et_full_pipeline/nextflow.config` | Profiles: test, docker, singularity, stub, local_gpu, slurm |
| `frontend/client/src/components/viewers/structure-viewer.tsx` | 3Dmol.js structure viewer (PDB/CIF) |
| `frontend/client/src/components/viewers/density-map-viewer.tsx` | Pure-TS MRC slice viewer (XY/XZ/YZ) |

---

## 2. Gap 2 — QC Profiles

### What was added

Two new entries in `QC_NAMED_PROFILES` dict in `qc_trace_monitor.py`:

**`cryoem_spa_standard`**
- Semantic alias for `cryoem_spa_purified`
- Zero threshold overrides — applies the same defaults as purified
- Purpose: gives the most common case a memorable name without ambiguity

**`cryoem_spa_lowdose`**
- Overrides: `total_drift_angstrom: 60.0` (default 50 Å), `fit_quality: 0.65` (default 0.70)
- Use case: datasets collected at < 40 e⁻/Å² total dose (EMPIAR benchmark collections, low-dose screening experiments)
- Rationale: lower total dose reduces per-frame SNR, weakening Thon ring visibility (CTF fit) and increasing apparent beam-induced motion (motion correction)
- Reference: Rohou & Grigorieff 2015 J Struct Biol 192:216 (CTFFIND4) for CTF quality degradation at low SNR

### Test

The `NextflowQCGateHandler` constructor requires a live Galaxy app; use `__new__` for unit tests (same pattern as `test_qc_e2e_domains.py`).

```bash
cd /home/yzhang/biomate/backend
.venv/bin/python -c "
import sys; sys.path.insert(0, 'lib')
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

def make_h(domain, profile=None):
    h = NextflowQCGateHandler.__new__(NextflowQCGateHandler)
    h.workflow_domain = domain
    h.active_profile = profile
    h.qc_profile = profile
    h.qc_overrides = NextflowQCGateHandler.get_profile_overrides(profile) if profile else {}
    return h

# List all cryo-EM profiles
profiles = NextflowQCGateHandler.list_profiles()
for p in profiles:
    if p['id'].startswith('cryoem'):
        print(p['id'], p.get('overrides', {}))
print()

# Validate that cryoem_spa_lowdose relaxes fit_quality gate
h1 = make_h('cryo_em')
ok1, _ = h1._check_qc_thresholds('PATCH_CTF_ESTIMATION', {'fit_quality': 0.68})
h2 = make_h('cryo_em', 'cryoem_spa_lowdose')
ok2, _ = h2._check_qc_thresholds('PATCH_CTF_ESTIMATION', {'fit_quality': 0.68})
print('No profile, fit_quality=0.68:', 'PASS' if ok1 else 'FAIL')
print('cryoem_spa_lowdose, fit_quality=0.68:', 'PASS' if ok2 else 'FAIL')
" 2>/dev/null
```

Expected:
```
cryoem_spa_purified {}
cryoem_spa_membrane {'total_drift_angstrom': 80.0, 'fit_quality': 0.65}
cryoem_spa_phase_plate {'fit_quality': 0.65, 'avg_phase_shift_rad_min': 0.2, 'avg_phase_shift_rad_max': 1.5}
cryoem_spa_standard {}
cryoem_spa_lowdose {'total_drift_angstrom': 60.0, 'fit_quality': 0.65}
cryoem_tomo_in_situ {'total_drift_angstrom': 150.0, 'fit_quality': 0.5, ...}

No profile, fit_quality=0.68: FAIL
cryoem_spa_lowdose, fit_quality=0.68: PASS
```

Also covered by the existing test suite:

```bash
.venv/bin/python -m pytest tests/test_qc_e2e_domains.py -k "TestNamedProfiles" -v 2>&1 | tail -30
```

---

## 3. Gap 3 — Orientation Anisotropy

### What was added

**In `_parse_refinement_metrics()` (qc_trace_monitor.py ~line 1977):**
Extraction loop checking four key aliases in priority order:
1. `orientation_anisotropy_ratio` — primary (written by SPA mock)
2. `anisotropy_ratio` — short alias
3. `best_worst_ratio` — CryoSPARC 3DFSC-style naming
4. `orientation_bias_ratio` — AreTomo2-style naming

**In `_check_qc_thresholds()` HOMOGENEOUS_REFINEMENT branch (~line 3304):**

| Tier | Condition | Action |
|------|-----------|--------|
| GOLD | anisotropy > 10× | Blocking failure — reconstruction has directional artifacts |
| SILVER | anisotropy 5–10× | Advisory — validate with 3DFSC, consider tilted data collection |

Reference: Tan YZ et al. (2017) Nat Methods 14:793–796 (3DFSC paper).

**In `cryosparc_standard_spa/main.nf` (~line 1094):**
HOMOGENEOUS_REFINEMENT mock now emits `orientation_anisotropy_ratio` (random 1.5–4.0× to simulate normal datasets) in `refinement_report.json`.

### Test

```bash
cd /home/yzhang/biomate/backend
.venv/bin/python -c "
import sys; sys.path.insert(0, 'lib')
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

def make_h(domain='cryo_em', profile=None):
    h = NextflowQCGateHandler.__new__(NextflowQCGateHandler)
    h.workflow_domain = domain
    h.active_profile = profile
    h.qc_profile = profile
    h.qc_overrides = NextflowQCGateHandler.get_profile_overrides(profile) if profile else {}
    return h

h = make_h('cryo_em')
ok, _ = h._check_qc_thresholds('HOMOGENEOUS_REFINEMENT', {'orientation_anisotropy_ratio': 1.8})
print('ratio=1.8x:', 'PASS' if ok else 'FAIL')
ok7, r7 = h._check_qc_thresholds('HOMOGENEOUS_REFINEMENT', {'orientation_anisotropy_ratio': 7.0})
print('ratio=7.0x advisory:', [f['metric'] for f in r7 if f.get('advisory')])
print('ratio=7.0x blocking:', [f['metric'] for f in r7 if not f.get('advisory')])
ok12, r12 = h._check_qc_thresholds('HOMOGENEOUS_REFINEMENT', {'orientation_anisotropy_ratio': 12.0})
print('ratio=12.0x blocked:', any(f['metric']=='orientation_anisotropy_ratio' and not f.get('advisory') for f in r12))
" 2>/dev/null
```

Expected:
```
ratio=1.8x: PASS
ratio=7.0x advisory: ['orientation_anisotropy_ratio']
ratio=7.0x blocking: []
ratio=12.0x blocked: True
```

Existing test coverage:
```bash
.venv/bin/python -m pytest tests/test_qc_e2e_domains.py -k "PriyaCryoEM_P2" -v 2>&1 | tail -15
```

---

## 4. Gap 4 — Cryo-ET Pipeline

### Architecture

```
IMPORT_TILTSERIES
    └─► TILT_ALIGNMENT          (GPU, AreTomo2/IMOD)
            └─► TOMOGRAM_RECONSTRUCTION  (WBP/SIRT, parallel per TS)
                    └─► SUBTOMOGRAM_AVERAGING  (GPU, RELION 4 STA)
                                └─► ET_PIPELINE_SUMMARY
```

All tilt series are processed in parallel at alignment and reconstruction stages (each tilt series is a separate Nextflow channel item). This mirrors how AreTomo2 and RELION 4.0 operate in real HPC deployments.

### Mock data values (physically realistic)

| Parameter | Value | Justification |
|-----------|-------|---------------|
| pixel_size | 1.35 Å | Typical for 300 kV Krios + K3 camera at 0.835 Å/px physical, 2× binned |
| voltage | 300 kV | Standard for high-resolution cryo-ET |
| total_dose | 120 e⁻/Å² | Divided across 41 tilts ≈ 2.9 e⁻/Å² per tilt — within safe range |
| tilt_range | ±60° at 3° | 41 images per series — standard Saxton or dose-symmetric scheme |
| alignment_residual | 0.5–3.5 Å | AreTomo2/IMOD fiducial-free: 1–3 Å typical; 5 Å advisory threshold |
| STA FSC resolution | 12–25 Å | Typical for in-vitro STA; cellular STA often 20–50 Å |

### QC gates added

| Process | Metric | Tier | Threshold | Action |
|---------|--------|------|-----------|--------|
| TILT_ALIGNMENT | `mean_residual_angstroms` | SILVER | > 5 Å | Advisory — recommend fiducial markers or better SNR |
| SUBTOMOGRAM_AVERAGING | `final_fsc_0143_resolution_angstroms` | Info | None | Always logged; no blocking gate (no published consensus) |

### Test — mock pipeline run

Requires Nextflow installed. Run:

```bash
cd /home/yzhang/biomate/backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/et_full_pipeline
nextflow run main.nf -profile test 2>&1 | tail -30
```

Expected: all 5 processes complete, `results/test_et/` directory created with:
```
results/test_et/01_import_tiltseries/tiltseries_import_report.json
results/test_et/02_tilt_alignment/tilt_alignment_report.json
results/test_et/03_tomogram_reconstruction/tomogram_reconstruction_report.json
results/test_et/04_subtomogram_averaging/sta_report.json
results/test_et/05_et_pipeline_summary/et_pipeline_summary.json
```

Spot-check the summary:
```bash
cat results/test_et/05_et_pipeline_summary/et_pipeline_summary.json | python3 -m json.tool
```

Expected fields in summary:
- `num_tiltseries`: 3
- `alignment.overall_mean_residual_angstroms`: float 0.5–3.0 Å
- `reconstruction.num_tomograms`: 3
- `sta.final_fsc_0143_resolution_angstroms`: float 12–25 Å

### Test — stub run (no Python needed)

```bash
nextflow run main.nf -profile stub 2>&1 | tail -10
```

Expected: all processes complete with exit 0, output files created (empty, via `touch`).

### Test — individual module

```bash
cd /home/yzhang/biomate/backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/import_tiltseries
nextflow run main.nf --mock_mode true 2>&1 | tail -10
# Expect: tiltseries_import_report.json created with num_tiltseries=3
```

### Test — QC dispatch

```bash
cd /home/yzhang/biomate/backend
.venv/bin/python -c "
import sys, tempfile, json, pathlib
sys.path.insert(0, 'lib')
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

def make_h(domain):
    h = NextflowQCGateHandler.__new__(NextflowQCGateHandler)
    h.workflow_domain = domain
    h.active_profile = None
    h.qc_profile = None
    h.qc_overrides = {}
    return h

with tempfile.TemporaryDirectory() as d:
    p = pathlib.Path(d)
    (p / 'tilt_alignment_report.json').write_text(json.dumps({
        'step': '02_tilt_alignment',
        'overall_mean_residual_angstroms': 6.2,  # Above 5 Å advisory
        'num_tiltseries_aligned': 3
    }))
    h = make_h('cryo_et')
    metrics = h._parse_tilt_alignment_metrics(p)
    print('Parsed metrics:', metrics)
    ok, failures = h._check_qc_thresholds('TILT_ALIGNMENT', metrics)
    print('Advisory failures:', [f['metric'] for f in failures if f.get('advisory')])
    print('Blocking failures:', [f['metric'] for f in failures if not f.get('advisory')])
" 2>/dev/null
```

Expected:
```
Parsed metrics: {'mean_residual_angstroms': 6.2}
Advisory failures: ['mean_residual_angstroms']
Blocking failures: []
```

---

## 5. Gap 5 — 3D Structure Viewer

### What was built

`frontend/client/src/components/viewers/structure-viewer.tsx`

- Loads 3Dmol.js from `https://3Dmol.csb.pitt.edu/build/3Dmol-min.js` via CDN script injection
- Deduplication guard: checks `window.$3Dmol` first, then `document.getElementById('3dmol-script')`, preventing double-load when multiple instances are on screen
- Format detection: `.cif` / `.mmcif` → 3Dmol `'cif'` format; everything else → `'pdb'`
- Style toggle (4 options): Cartoon | Stick | Sphere | Line
- Color scheme (4 options): Spectrum (maps B-factor/pLDDT to rainbow) | Chain | Residue | White
- Fetches from `/api/outputs/${output.id}/display` (same endpoint as image/text outputs)
- Wired into `chat-output-attachments.tsx` under fileType `'structure'`
- Schema: `'structure'` added to fileType enum in `frontend/shared/schema.ts`

### File type routing

Galaxy outputs with extensions `.pdb` or `.cif` or `.mmcif` must have `fileType: 'structure'` for the viewer to render. Check how the backend classifies output file types if structure files appear in the "Other Files" section rather than "3D Structures".

### Test — TypeScript compilation

```bash
cd /home/yzhang/biomate/frontend
npx tsc --noEmit 2>&1 | grep -E "structure-viewer|density-map|chat-output|schema" | head -20
# Expected: no output (zero errors in the affected files)
```

Full typecheck:
```bash
npx tsc --noEmit 2>&1 | tail -5
# Expected: no errors
```

### Test — dev server (visual)

```bash
cd /home/yzhang/biomate/frontend
npm run dev
```

Then in the BioMate UI:
1. Start a workflow that produces a `.pdb` output (e.g. AlphaFold3 structure prediction)
2. When the workflow completes, the "3D Structures" section should appear in the outputs panel
3. The structure should render as a cartoon ribbon with spectrum colouring by default
4. Toggle style and colour scheme buttons should update the view without refetching

### Manual smoke test (no backend)

Download any PDB file (e.g. `https://files.rcsb.org/download/1ABC.pdb`), place it as a static test file, and verify 3Dmol loads and renders it.

---

## 6. Gap 6 — MRC Density Map Viewer

### What was built

`frontend/client/src/components/viewers/density-map-viewer.tsx`

- Zero external dependencies — pure TypeScript + Canvas 2D API
- MRC header parsed via `DataView` (little-endian), per MRC2014 standard (Cheng et al. 2015 J Struct Biol 192:430):
  - `nx, ny, nz` at offsets 0, 4, 8 (int32)
  - `mode` at offset 12 (int32): 0=int8, 1=int16, 2=float32, 6=uint16
  - `xlen, ylen, zlen` at offsets 96, 100, 104 (float32, cell dimensions in Å)
  - `nsymbt` at offset 196 (int32) — extra bytes after 1024-byte header
- Fetches the full file as `ArrayBuffer` from `/api/outputs/${output.id}/download`
- Renders orthogonal slices on a 512×512 canvas with per-slice min/max normalisation
- Axis selector: XY | XZ | YZ tabs
- Z/X/Y slice slider (range input)
- Contrast slider: gamma correction via `Math.pow(v, 1/contrast)`, range 1–5×
- Wired into `chat-output-attachments.tsx` under fileType `'density_map'`
- Schema: `'density_map'` added to fileType enum

### Test — TypeScript compilation

Same as structure viewer:
```bash
cd /home/yzhang/biomate/frontend
npx tsc --noEmit 2>&1 | tail -5
```

### Test — MRC header parsing (unit test, no file needed)

```typescript
// Run in browser console or a Node.js test file
// Creates a synthetic 10×10×10 float32 MRC buffer and verifies parsing

const buf = new ArrayBuffer(1024 + 10*10*10*4)
const view = new DataView(buf)
view.setInt32(0, 10, true)   // nx=10
view.setInt32(4, 10, true)   // ny=10
view.setInt32(8, 10, true)   // nz=10
view.setInt32(12, 2, true)   // mode=2 (float32)
view.setFloat32(96, 50.0, true)   // xlen=50 Å
view.setFloat32(100, 50.0, true)  // ylen=50 Å
view.setFloat32(104, 50.0, true)  // zlen=50 Å
view.setInt32(196, 0, true)  // nsymbt=0

// Fill with gradient data
for (let i = 0; i < 1000; i++) {
  view.setFloat32(1024 + i*4, i/1000.0, true)
}

// parseMrcHeader(buf) should return:
// { nx: 10, ny: 10, nz: 10, mode: 2, xlen: 50, ylen: 50, zlen: 50, nsymbt: 0, dataOffset: 1024 }
```

### Test — dev server (visual)

1. Find or download any MRC/MAP file (e.g. from EMDB: `https://ftp.ebi.ac.uk/pub/databases/emdb/structures/EMD-1000/map/emd_1000.map.gz`)
2. Upload via BioMate or serve as a workflow output with `fileType: 'density_map'`
3. The "Density Maps" section should appear in the outputs panel
4. XY/XZ/YZ tabs should each render the correct cross-section
5. The Z-slider should update the visible slice
6. Contrast slider should brighten/darken the map

---

## 7. QC Test Suite

All existing tests continue to pass after these changes. Run the full suite:

```bash
cd /home/yzhang/biomate/backend
.venv/bin/python -m pytest tests/test_qc_e2e_domains.py -q 2>&1 | tail -5
# Expected: 213 passed
```

Run specifically cryo-EM related tests:
```bash
.venv/bin/python -m pytest tests/test_qc_e2e_domains.py -k "cryoem or CryoEM or Priya" -v 2>&1 | grep -E "PASSED|FAILED|ERROR"
# Expected: all PASSED, 31 tests
```

### Verify the FSC key fix specifically

```bash
.venv/bin/python -c "
import sys, tempfile, json, pathlib
sys.path.insert(0, 'lib')
from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler

def make_h(domain='cryo_em'):
    h = NextflowQCGateHandler.__new__(NextflowQCGateHandler)
    h.workflow_domain = domain
    h.active_profile = None
    h.qc_profile = None
    h.qc_overrides = {}
    return h

with tempfile.TemporaryDirectory() as d:
    p = pathlib.Path(d)
    # Mock pipeline writes fsc_0143_resolution, not fsc_resolution_angstrom
    (p / 'refinement_report.json').write_text(json.dumps({
        'fsc_0143_resolution': 8.5,
        'final_resolution_angstroms': 7.2,
        'orientation_anisotropy_ratio': 2.1
    }))
    h = make_h()
    metrics = h._parse_refinement_metrics(p)
    print('fsc_0143_resolution key parsed:', 'fsc_resolution_angstrom' in metrics, '=', metrics.get('fsc_resolution_angstrom'))
    print('anisotropy parsed:', 'orientation_anisotropy_ratio' in metrics, '=', metrics.get('orientation_anisotropy_ratio'))
" 2>/dev/null
# Expected:
# fsc_0143_resolution key parsed: True = 8.5
# anisotropy parsed: True = 2.1
```

> **Note for all Python test snippets:** run from `/home/yzhang/biomate/backend/` and use `.venv/bin/python`. The `sys.path.insert(0, 'lib')` call in each snippet handles the Galaxy module path. Alternatively, use the pytest suite which sets the path automatically.

---

## 8. Audit Findings and Resolutions

A post-implementation audit was performed. Full audit report available in conversation history.

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| A1 | WARN | `cryoem_spa_standard` reference was informal placeholder | Fixed — replaced with URL to EMPIAR deposition guidelines |
| A2 | WARN | `cryoem_spa_lowdose` references were placeholder text | Fixed — cites Rohou & Grigorieff 2015 (CTFFIND4); BRONZE label retained for motion threshold |
| B1 | **FAIL** | FSC key mismatch: parser looked for `fsc_resolution_angstrom` but mock writes `fsc_0143_resolution` and `final_resolution_angstroms` — FSC gate would never fire | **Fixed** — added both keys to the lookup chain in `_parse_refinement_metrics()` |
| C3 | WARN | `tomogram_reconstruction` always used hardcoded `pixel_size=1.35 Å` — value never propagated from import step | Fixed — `tilt_alignment` now reads pixel_size from manifest and includes it in report; reconstruction reads from report |
| C5 | WARN (false) | Audit agent claimed no `nextflow.config` exists | Not a bug — file was created (`et_full_pipeline/nextflow.config` with 6 profiles including `process_gpu` label) |
| C7 | WARN | Tilt alignment 5 Å threshold is lenient vs IMOD's 1–3 Å typical | Accepted — correctly labeled `[SILVER]` advisory; inline docstring acknowledges "no published consensus"; lenient gate is appropriate for a non-blocking check |

---

## 9. Known Limitations / Future Work

1. **3D structure viewer requires internet access** — 3Dmol.js is loaded from CDN (`https://3Dmol.csb.pitt.edu`). For air-gapped deployments, either vendor the script or self-host. The npm package `3dmol` exists but requires Webpack/Vite configuration.

2. **MRC viewer loads entire file into memory** — For large tomogram maps (1–5 GB), this is impractical. A future version should use a streaming/chunked approach, only loading the requested slice. The current viewer is appropriate for SPA density maps (typically 10–100 MB).

3. **Cryo-ET pipeline is mock-only** — Live mode requires AreTomo2 or IMOD installed and a GPU. Container definitions are commented placeholders. For live runs, integrate with `ghcr.io/czii/cryoet-docker-images/aretomo2:latest`.

4. **STA FSC gate has no blocking threshold** — No community consensus threshold for ET STA resolution exists in the literature (unlike SPA where 10 Å is established). The gate emits an informational advisory for all runs. A blocking threshold could be added once community practice stabilises.

5. **`fileType: 'structure'` routing not yet implemented** — The backend Galaxy output classifier (`ai_assistant.py` or the invocation outputs endpoint) must classify `.pdb`/`.cif` files as `fileType: 'structure'` and `.mrc`/`.map` files as `fileType: 'density_map'` for the new viewers to be invoked automatically. Until that is done, the viewers can be tested by manually constructing an `OutputDataset` object.

---

## 10. Quick Reference — New API Endpoints

No new HTTP endpoints were added. The QC profiles endpoint already existed:

```bash
curl http://localhost:8081/api/qc/profiles | python3 -m json.tool | grep '"name"' | grep cryoem
# Expected: 5 cryo-EM profiles listed
```

---

*Document produced 2026-03-05. For questions, see conversation history or contact the implementing developer.*
