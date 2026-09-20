# Cryo-EM (single-particle reconstruction)

> One-line promise: take a folder of raw cryo-EM movies all the way to a
> sharpened 3D density map with a gold-standard resolution number you can trust —
> motion correction, CTF, particle picking, 2D/3D classification and refinement
> run for you on the cloud, with the FSC gate telling you whether the map is
> publication-grade before you open it.
> For: **structural biologists** who image on a Krios/Glacios and want a
> reconstruction without babysitting CryoSPARC, and **cryo-EM core-facility
> staff** who run the same pipeline for many users and need reproducible,
> gate-checked output. No coding, no CryoSPARC job-tree clicking required.

<!--
P1 chapter. Every "supported" claim below is green in coverage-ledger.md § "Cryo-EM (single-particle reconstruction)".
Honesty rule: the pipeline documented here is the CryoSPARC-native single-particle chain that BioMate actually runs
(cryosparc_standard_spa/main.nf). Tool names from the polished tutorial narrative (MotionCor2/CTFFind/Gctf/Topaz/
DeepEMhancer, "FitQ < 0.20", "GSFSC 3.21 Å") are ILLUSTRATIVE — the real pipeline uses CryoSPARC's own patch motion
correction, patch CTF, blob+template picking and CryoSPARC sharpening; the enforced gates are stated from code
(qc_evidence.yaml + qc_evaluator.py). Cryo-ET, the ensemble→cryptic-pocket mega-chain, and any auto-remediation loop
are NOT claimed here (Appendix E).
-->

## What this is for

This is the **"movies → map"** path. You bring **raw movie stacks** (`.tif`,
`.mrc`, or `.eer`) off the microscope plus the acquisition metadata (pixel size,
voltage, spherical aberration, total dose); BioMate runs the full
**single-particle analysis (SPA)** pipeline on CryoSPARC and returns a
**sharpened 3D density map** together with the **gold-standard FSC curve** that
sets its resolution.

The whole 23-step CryoSPARC standard workflow runs end to end, orchestrated for
you (`cryosparc_standard_spa/main.nf`):

1. **Preprocessing** — beam-induced **motion correction** and **CTF estimation**,
   one parallel job per micrograph batch.
2. **Particle picking** — automated **blob picking**, junk-class removal, then a
   **template picker** trained on your own 2D classes for a cleaner second pass.
3. **Classification** — two rounds of **2D classification** with class selection,
   to throw away ice, edges and junk before you spend GPU time in 3D.
4. **3D reconstruction** — **ab-initio** (multiple classes), **homogeneous
   refinement**, **local CTF refinement**, and **non-uniform (NU) refinement**
   for the final high-resolution map.
5. **Validation & post-processing** — gold-standard **FSC**, **local resolution**
   estimation, and **B-factor sharpening** to the deposited-quality map.

The through-line of this chapter is **interpretation, not a metrics dump.** The
FSC resolution, the CTF fit quality and the particle count are each explained as
"what this number means and what to do next," and the worked example ends on a
*decision* (this map, this resolution, this confidence), not a job tree.

> **Tip** — Already have extracted particles from a previous session? You do not
> have to re-do motion/CTF/picking. The pipeline has a **particles entry mode**
> (`import_mode = "particles"`, with `particle_star_file` + `particle_blob_path`)
> that skips straight to 2D classification. Re-running from movies is the
> expensive part; skip it when you can. (`main.nf:96-99`, workflow routing
> `main.nf:3016-3020`.)

## Use cases

| Goal (researcher's words) | Workflow(s) / chain | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "Reconstruct a 3D map from my cryo-EM movies" | `cryosparc_standard_spa` (full 23-step SPA) | Movies (`.tif`/`.mrc`/`.eer`) + pixel size, voltage, Cs, dose | Sharpened density map (`.mrc`) + gold-standard FSC + local-resolution map | Cloud (AWS Batch + GPU CryoSPARC) |
| "I already have picked particles — just do 2D→3D→refine" | `cryosparc_standard_spa`, `import_mode="particles"` | Particle STAR file + blob path | Refined + sharpened map + FSC | Cloud |
| "My protein is symmetric — apply the point group" | `cryosparc_standard_spa`, `symmetry=C2/D2/O/T/I` | Movies + symmetry | Symmetrised refined map + FSC | Cloud |
| "It's a membrane protein / phase-plate data — use the right QC gates" | `cryosparc_standard_spa` + QC profile `cryoem_spa_membrane` / `cryoem_spa_phase_plate` | Movies + sample-type hint | Map + FSC scored against the relaxed profile | Cloud |
| "Read my map — show me slices and the FSC curve" | in-app **Density Map Viewer** + **FSC / motion / CTF** chart viewers | Any `.mrc`/`.map` + cryo JSON reports from a run | Orthogonal-slice viewer, FSC curve, motion histogram, CTF chart | Instant (in-app, no run) |

> **Pitfall — this is single-particle analysis, not tomography.** The
> `cryosparc_standard_spa` chain reconstructs **purified particles imaged as
> movies**. It is **not** cryo-electron tomography (tilt series, subtomogram
> averaging, in-situ lamellae). Cryo-ET subworkflows exist in the catalog but are
> **not documented or gold-verified in this chapter** — see "What's not covered."

## How to ask

BioMate routes on intent. The word that matters most is **"cryo-EM" /
"CryoSPARC" / "single-particle" / "SPA"** plus a hint of your input (movies vs
particles) and your sample type.

Full reconstruction from movies:

> "Process my cryo-EM micrographs through the full CryoSPARC SPA pipeline."
> *(the verified routing probe — `experiments/verified_queries/candidates.yaml:72-75`,
> expected workflow `cryosparc_standard_spa`.)*

With acquisition metadata (the pipeline needs these to be physically correct):

> "Run single-particle cryo-EM on these movies — pixel size 1.05 Å, 300 kV,
> Cs 2.7 mm, total dose 50 e⁻/Å², C1 symmetry."

Symmetric particle / known point group:

> "This is an icosahedral virus capsid — run SPA with I symmetry."

From already-extracted particles:

> "I already have a particle stack — start from 2D classification, skip motion
> and picking."

**How the routing decides which QC profile you get.** The QC monitor picks a
cryo-EM profile from your prompt *before* checking other domains, so the electron
microscopy `em` token never gets mistaken for a genome build
(`qc_trace_monitor.py:1085-1093`):

- "tomography / lamella / FIB-SEM" → `cryoem_tomo_in_situ` (very high drift
  tolerance).
- "phase plate / VPP" → `cryoem_spa_phase_plate` (relaxed CTF fit quality — VPP
  fits are inherently noisier).
- "membrane protein / GPCR / channel / detergent / nanodisc" →
  `cryoem_spa_membrane` (80 Å drift tolerance, relaxed CTF).
- otherwise → `cryoem_spa_purified` (the strict default).

Naming your sample type is not cosmetic — it changes the numbers a "fail" is
measured against (see QC gates below).

**Disambiguation to avoid:**

- **SPA vs cryo-ET.** "cryo-EM" alone defaults to single-particle. If you have a
  **tilt series**, say "tomography" — but note the SPA gold example and the
  documented worked run here are single-particle only.
- **Movies vs particles.** If you say "reconstruct from my movies" you get the
  full chain (motion/CTF/picking included). If you already have a particle STAR
  file, say so — otherwise the pipeline will try to run motion correction on
  inputs it doesn't have.
- **Metadata is a prerequisite, not a guess.** Pixel size, voltage and Cs are
  physical constants of your scope/session. The pipeline has defaults
  (1.05 Å, 300 kV, 2.7 mm — `main.nf:44-47`) but a wrong pixel size silently
  ruins the resolution. State yours.

## Tools & workflows behind this

| Tool / workflow | Role | Where (verified) |
|---|---|---|
| `cryosparc_standard_spa` | Full 23-step CryoSPARC SPA pipeline (movies→sharpened map) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf`; workflow entry `main.nf:3004-3168` |
| Patch motion correction | Beam-induced motion correction, one job per micrograph batch (parallel) | `main.nf:680` (`PATCH_MOTION_CORRECTION_BATCH`) |
| Patch CTF estimation | CTF fit; extracts defocus range + fit-quality QC metric | `main.nf:841` (`PATCH_CTF_ESTIMATION_BATCH`); fit range `main.nf:54-55` |
| Blob picker + junk detector + template picker | Automated picking, junk-class removal, then template-based re-pick from your own 2D classes | `main.nf:978` (`BLOB_PICKER_BATCH`), `JUNK_2D_DETECTOR`, `main.nf:2162` (`TEMPLATE_PICKER`) |
| 2D classification ×2 + class selection | Two rounds of 2D classify with select, on parallel particle sub-batches | `CLASSIFY_2D_R1_BATCH` (`main.nf:1231`), `CLASSIFY_2D_R2_BATCH` (`main.nf:1338`), `SELECT_2D_R1/R2` |
| Ab-initio reconstruction | K parallel initial 3D models (default 3 classes) | `main.nf:1420` (`AB_INITIO_BATCH`); `params.num_ab_initio_classes` `main.nf:65` |
| Homogeneous → local CTF → non-uniform refinement | The 3D refinement ladder to the final high-res map | `HOMO_REFINEMENT_BATCH` (`main.nf:1505`), `LOCAL_CTF_REFINEMENT` (`main.nf:2654`), `NON_UNIFORM_REFINEMENT` (`main.nf:2725`) |
| Validation FSC | Gold-standard half-map FSC; emits the resolution gate metric | `main.nf:2476` (`VALIDATION_FSC`); gate wired `main.nf:2631-2640` |
| Local resolution + sharpening | Per-voxel resolution map + B-factor sharpened final `.mrc` | `LOCAL_RESOLUTION` (`main.nf:2844`), `SHARPEN` (`main.nf:2907`) |
| Sample-type presets | Per-sample ab-initio iterations / notes (virus, ribosome, membrane…) | `main.nf:368-396` |
| QC-gate evidence + monitor | Cryo-EM thresholds with citations; reads run trace | `backend/config/qc_evidence.yaml:738-788`; `backend/lib/galaxy/jobs/qc_trace_monitor.py:1085-1093, 1442-1453` |
| In-app viewers | Density map slices; FSC / motion / CTF charts from cryo JSON | `frontend/client/src/components/viewers/density-map-viewer.tsx`, `fsc-curve-chart.tsx`, `motion-histogram-chart.tsx`, `ctf-quality-chart.tsx` |

> **Note — one pipeline, CryoSPARC-native.** BioMate does not chain external tools
> (MotionCor2, CTFFind/Gctf, Topaz, DeepEMhancer) as separate steps. Every step
> is a CryoSPARC job that BioMate submits, polls and collects via the
> `cryosparc-tools` library (`main.nf` `cs_helper`). The polished tutorial
> narrative names those external tools for familiarity; the *runtime* uses
> CryoSPARC's own patch motion correction, patch CTF, blob/template pickers and
> `sharpen` job. Where the manual and the tutorial diverge, the manual states the
> code truth.

> **License** — CryoSPARC is licensed software (academic licenses are free from
> Structura Biotechnology); BioMate orchestrates a licensed CryoSPARC instance on
> your behalf. Your movies, particles and maps are yours. Deposited-quality maps
> are suitable for EMDB submission but BioMate does not submit for you.

## QC gates & how to read them

A cryo-EM QC gate answers one question for a structural biologist: **"is this map
real, and is the resolution number honest?"** Cryo-EM has three natural failure
points — bad motion correction, bad CTF, and an over-optimistic resolution — and
BioMate gates each. Every threshold below is stated **from code**, with its
citation and its provenance tier.

| Gate | Threshold (default `cryoem_spa_purified`) | What a fail means | Enforced / cited where |
|---|---|---|---|
| **Gold-standard FSC 0.143 resolution** | **≤ 4 Å pass** · 4–8 Å advisory · **> 15 Å FAIL** | The final map's resolution by the gold-standard half-map FSC 0.143 criterion. > 15 Å means the reconstruction did not converge to anything interpretable. | Metric wired in `main.nf:2631-2640` (emits `cryo_em_fsc_resolution_passes`, `fsc_resolution_angstroms`); thresholds `qc_evidence.yaml:740-758` — **metric GOLD** (Rosenthal & Henderson 2003), **cutoffs SILVER** (operational) |
| **CTF fit quality** | **≥ 0.70** (red-line floor 0.5; membrane/VPP 0.65) | The CTF estimation is unreliable — below the floor, picking and everything downstream is invalid. | `qc_evaluator.py:77` (`min_ctf_fit_quality`), red-line `qc_trace_monitor.py:41-45`; gate logic `qc_evaluator.py:178-190` |
| **Motion drift** | **≤ 50 Å total** advisory · **> 100 Å FAIL** (membrane 80 Å) | Beam-induced or stage drift is degrading the micrographs; high-res signal is smeared out. | `qc_evidence.yaml:760-773` (SILVER, Punjani 2017); `qc_evaluator.py:75-76` |
| **Particle count** | flags **< 50 000** for sub-3 Å targets | Too few particles to average out noise to high resolution. | `qc_evidence.yaml:775-788` (SILVER, Henderson 1995); yield gate `qc_evaluator.py:231-243` |

> **Pitfall — the CTF gate is 0.70, not 0.20.** The polished tutorial screen
> shows "12 micrographs flagged for FitQ < 0.20 (auto-removed)" as an
> *illustration*. The **enforced** CTF fit-quality gate is **≥ 0.70** for
> purified samples (`qc_evaluator.py:77`), with an absolute **red-line floor of
> 0.5** below which the run is treated as a failed CTF estimation
> (`qc_trace_monitor.py:41-45`). Read 0.70 as your interpretive bar, not 0.20.

> **Pitfall — the resolution gate is ≤ 4 Å, not < 3.5 Å.** The gate that the
> pipeline actually emits marks a map as passing at **FSC 0.143 ≤ 4 Å**
> (`main.nf:2637`, `qc_evidence.yaml:752-758`); 4–8 Å is advisory and only
> > 15 Å hard-fails. A "3.5 Å" figure appears in narrative material but is not
> the coded pass line. And the resolution cutoffs are labelled **SILVER /
> operational** on purpose — the *FSC 0.143 metric itself* is the GOLD,
> paper-anchored part (Rosenthal & Henderson 2003); the specific 4/8/15 Å tiers
> are BioMate's operational reading of field norms, not values from that paper
> (`qc_evidence.yaml:744-757`).

**How to read each, as a scientist:**

- **FSC 0.143 resolution** — this is *the* number. It comes from splitting your
  particles into two independent half-sets, reconstructing each, and asking at
  what spatial frequency the two half-maps stop correlating (cross the 0.143
  line). It is the honest, over-fitting-resistant resolution. Read it first;
  everything else is upstream diagnostics that explain it.
- **CTF fit quality** — a low fit quality means the software could not confidently
  model defocus/astigmatism for those micrographs. Below the 0.5 red line, picked
  particles are meaningless. The usual fix is to broaden
  `ctf_fitting_resolution_min` / tighten `ctf_fitting_resolution_max`
  (`main.nf:54-55`; suggestion emitted at `qc_evaluator.py:189`).
- **Motion drift** — high total drift smears high-resolution information. Advisory
  above 50 Å; a hard fail above 100 Å usually means a stage or dose-symmetry
  problem at collection, not something you can fully rescue computationally.
- **Particle count** — sub-3 Å needs numbers. Fewer than ~50 000 selected
  particles is flagged for high-resolution targets; the remedy is more data or
  looser 2D-classification filters, not a lower FSC threshold.

> **QC gate — pick the profile that matches your sample.** The same map read
> against `cryoem_spa_purified` (CTF ≥ 0.70, drift ≤ 50 Å) versus
> `cryoem_spa_membrane` (CTF ≥ 0.65, drift ≤ 80 Å) can "pass" or "fail" purely on
> that choice. A GPCR in detergent legitimately has noisier CTF and more drift;
> scoring it against the purified profile is the single most common
> misinterpretation. Say "membrane protein" so the right gates apply
> (`qc_trace_monitor.py:350-362`).

### What "fixing" a QC fail looks like here

Cryo-EM QC issues are surfaced to you to act on — there is **no automatic
remediation loop wired into the live pipeline** (unlike the ADMET chapter's
auto-loop). The fixes are decisions a microscopist makes:

- **Low CTF fit** → adjust the CTF fit resolution range and re-run
  (`ctf_fitting_resolution_min/_max`).
- **High junk fraction / few particles** → re-estimate
  `particle_diameter_angstroms`, loosen the picker, or restrict to a cleaner
  micrograph subset (suggestions emitted at `qc_evaluator.py:227, 242`).
- **Orientation anisotropy** (preferred orientation) → force `symmetry=C1` or add
  2D classes; a map that looks stretched in one axis is usually this, not true
  low resolution (`qc_evaluator.py:266`).
- **Poor FSC** → more particles, deeper refinement, or revisit the mask
  (`qc_evidence.yaml:757` remediation note).

## Worked example (gold standard)

**Goal.** Reconstruct a 3D map from a benchmark single-particle dataset and read
the artifact as a structural biologist would.

**Dataset.** **EMPIAR-10025** — the *T. acidophilum* **20S proteasome (T20S)**,
the canonical CryoSPARC introductory-tutorial dataset. It is the reference dataset
staged for this chapter at
`s3://biomate-workflow-inputs/tutorial-gold/cryo_em/EMPIAR-10025/`. The 20S
proteasome is a well-behaved D7-symmetric complex with a published high-resolution
structure, so it is the natural sanity anchor: a clean run should recover a
high-resolution, D7-symmetric map.

> **Note (gold-standard registry).** EMPIAR-10025 is the intended cryo-EM gold
> dataset for this chapter, but it is **not yet present in the machine-readable
> registry** `evaluation/tutorial_demos/gold_standards.yaml` (which today lists 7
> other domains; cryo-EM is absent). Related β-galactosidase datasets appear in
> the infra (`start_backend.sh:73` → EMPIAR-10028; test fixtures reference
> EMPIAR-10061). The chain, its steps and its QC gates are **code-verified (C)**;
> the gold-dataset binding is a **registry gap** to be closed, and a full live
> GPU/Batch run to reproduce exact numeric outputs is **pending (L / ⏳)** — GPU
> CryoSPARC Batch runs cost real money and the plan forbids speculative execution.

**Prompt:**

> "Process my cryo-EM micrographs through the full CryoSPARC SPA pipeline —
> EMPIAR-10025, 20S proteasome, D7 symmetry."

**What comes back and how to read it:**

- **Motion & CTF diagnostics.** The motion histogram and CTF chart show
  per-micrograph drift and fit quality. Interpretation: with total drift under the
  50 Å advisory line and CTF fit above 0.70, the micrographs are trustworthy —
  this is your first sanity gate, before any particle is picked.
- **2D classes.** After two rounds of 2D classification and selection, the
  selected classes show clean, recognisable proteasome views (top and side).
  Interpretation: the picked set is real particles, not ice or junk; a screen full
  of blurry blobs here would mean stop and re-pick.
- **The map.** Ab-initio → homogeneous → local CTF → non-uniform refinement
  produces the final volume; `SHARPEN` writes the B-factor-sharpened
  `volume_sharpened.mrc`. This is the artifact you carry forward — open it in the
  Density Map Viewer and you should see resolved secondary structure at the
  D7-symmetric core.
- **The resolution — the honest number.** The gold-standard FSC curve
  (`fsc_validation.json`) reports the FSC 0.143 resolution. Interpretation: this
  is the number you cite and deposit. If it comes in ≤ 4 Å the pipeline marks the
  map **pass** (`cryo_em_fsc_resolution_passes`, `main.nf:2637`); 4–8 Å is a valid
  but advisory map; only > 15 Å means the reconstruction failed to converge.

**The artifact.** A sharpened density map (`volume_sharpened.mrc`) + a
local-resolution map (`local_resolution.mrc`) + the gold-standard FSC curve
(`fsc_validation.json`) + a run summary. You end on a decision — *this map, at
this FSC-0.143 resolution, with D7 symmetry, passes the gate* — which is exactly
the "gold-standard-comparable artifact" the tutorial-demo plan mandates, not a
CryoSPARC job tree.

![FSC curve for the reconstructed map](../assets/cryo-1-fsc-curve.png)
<!-- CAPTURE route=/chat (or the run's after-run Outputs tab) state=a completed cryosparc_standard_spa run on EMPIAR-10025; open the fsc_validation.json output so FscCurveChart renders the gold-standard FSC curve with the 0.143 crossing marked. Needs a real GPU/Batch run. -->

![Sharpened density map in the Density Map Viewer](../assets/cryo-2-density-map.png)
<!-- CAPTURE route=/chat (after-run Outputs tab) state=a completed cryosparc_standard_spa run; open volume_sharpened.mrc so DensityMapViewer renders orthogonal XY/XZ/YZ slices with the slice slider. Needs a real GPU/Batch run producing a .mrc. -->

## Outputs & visualization

Every cryo-EM output renders in the after-run panel's Outputs tab through the
in-app viewer taxonomy (`frontend/client/src/components/step-output-preview.tsx`);
the mapping below is by file type. This is cross-referenced from
[I.8 Outputs, viewers & interactive panels](../modules/I08-outputs-viewers-interactive.md).

| Output | File | In-app viewer | When to go interactive |
|---|---|---|---|
| Sharpened final map | `volume_sharpened.mrc` | **Density Map Viewer** — orthogonal XY/XZ/YZ slices, slice slider, contrast (`density-map-viewer.tsx`; ext routing `step-output-preview.tsx:78,99`) | Open in ChimeraX/Coot for model building or surface rendering |
| Local-resolution map | `local_resolution.mrc` | **Density Map Viewer** | Colour-by-local-resolution in ChimeraX |
| Gold-standard FSC | `fsc_validation.json` | **FSC curve chart** (`fsc-curve-chart.tsx`; routed by filename `step-output-preview.tsx:631`) | Read the 0.143 / 0.5 crossings inline — no export needed |
| Motion report | `motion_report_*.json` | **Motion histogram chart** (`motion-histogram-chart.tsx`; `step-output-preview.tsx:632`) | Read per-micrograph drift distribution |
| CTF report | `ctf_report*.json` | **CTF quality chart** (`ctf-quality-chart.tsx`; `step-output-preview.tsx:633`) | Read defocus/fit-quality spread |
| CryoSPARC particle/class tables | `*.cs` / `*.csg` | **Download only** — binary CryoSPARC dataset, not browser-renderable (`step-output-preview.tsx:79-80,102`) | Open in CryoSPARC or with `cryosparc-tools` |
| Particle STAR tables | `*.star` | **Table viewer** (STAR/RELION parser, 200-row preview; `step-output-preview.tsx:166,213`) | Download for RELION cross-checking |

> **Tip — the map viewer needs no plugin.** The Density Map Viewer parses the MRC
> header and renders orthogonal slices in pure TypeScript/canvas
> (`density-map-viewer.tsx`) — no ChimeraX install, no browser extension. Use it
> to eyeball whether the map has real features (resolved helices, a sensible
> envelope) the moment the run finishes. Go to ChimeraX/Coot only when you move on
> to model building.

> **Tip — cryo runs are long; detach and come back.** A full movies→map SPA run
> is a multi-hour GPU Batch job. You do **not** have to keep the tab open — the
> run continues server-side and the panel reconnects to live progress when you
> return. See [I.6 Running an analysis](../modules/I06-running-an-analysis.md) for
> the detach / reconnect behaviour of long-running cloud runs.

## Pitfalls & tips

> **Pitfall — a wrong pixel size silently ruins resolution.** Pixel size, voltage
> and Cs are physical constants of your session, not preferences. The pipeline
> defaults to 1.05 Å / 300 kV / 2.7 mm (`main.nf:44-47`); if your data was
> collected at a different pixel size and you don't say so, every downstream
> resolution number is wrong even though nothing "fails." Always state your
> acquisition metadata.

> **Pitfall — set the symmetry.** Leaving `symmetry=C1` on a truly symmetric
> particle (a virus capsid, the D7 proteasome) throws away signal and inflates the
> particle count you need. Conversely, imposing symmetry that isn't there creates
> artefacts. Set the correct point group (`params.symmetry`, `main.nf:64`).

> **Pitfall — preferred orientation reads as low resolution.** If your map looks
> smeared along one axis, that is usually orientation anisotropy (particles
> adopting a preferred view at the air–water interface), not true low resolution.
> The anisotropy gate flags it (`qc_evaluator.py:249-267`); the fix is a tilted
> collection or additive, not a lower FSC threshold.

> **Tip — score against the right profile.** `cryoem_spa_membrane` and
> `cryoem_spa_phase_plate` exist because detergent scatter and VPP optics
> genuinely produce noisier CTF fits. Naming your sample type gives you the gates
> your data deserves instead of failing a strict purified-protein bar
> (`qc_trace_monitor.py:342-403`).

> **QC gate — trust the gold-standard FSC, not the refinement's own number.** The
> resolution to cite is the half-map FSC 0.143 from `VALIDATION_FSC`, computed on
> two independent half-sets — it is over-fitting-resistant by construction. An
> internal refinement "resolution" printed mid-pipeline is not the deposited
> number; read `fsc_validation.json`.

## What's not covered

Honest scope — these are **not** claimed as present in this chapter; they live in
**Appendix E (Coverage & roadmap)**:

- **A cryo-EM auto-remediation loop.** Unlike the ADMET chapter, there is **no**
  auto-loop wired into the live cryo-EM pipeline. A QC evaluator with cryo-EM
  gates exists under `backend/experiments/cryo_em_autoloop/` but is **not** wired
  into the production executor (`lib/galaxy/...`). Failing gates are surfaced for
  you to correct and re-run manually.
- **Cryo-electron tomography (cryo-ET).** Tilt-series alignment, subtomogram
  averaging and in-situ workflows have subworkflows in the catalog
  (`nextflow_nfcore/subworkflows/cryo_et/`) and QC evidence
  (`qc_evidence.yaml:790-824`), but are **not** documented, worked, or
  gold-verified in this chapter.
- **The cryo-EM ensemble → cryptic-pocket mega-chain.** A composed chain that
  would take a cryo-EM ensemble into cryptic-pocket / druggability analysis is
  **not runnable** and is explicitly excluded here (Appendix E).
- **Batch (many-dataset) runs.** This chapter documents a **single**
  movies→map run. Fan-out over many datasets in one submission is not documented
  here.
- **External-tool step chaining (MotionCor2 / CTFFind / Gctf / Topaz /
  DeepEMhancer).** The pipeline runs **CryoSPARC-native** patch motion, patch CTF,
  blob/template picking and CryoSPARC `sharpen`. It does **not** invoke those
  external programs as separate steps; where the tutorial narrative names them,
  treat it as familiar shorthand for the CryoSPARC-native equivalent.
- **A machine-readable cryo-EM gold-standard entry.** EMPIAR-10025 is the intended
  gold dataset and is staged in S3, but the row is **missing from**
  `evaluation/tutorial_demos/gold_standards.yaml` (registry gap) and the numeric
  outputs have **not** been re-confirmed by a fresh live GPU/Batch run.
- **EMDB submission.** BioMate produces deposit-quality maps but does **not**
  submit to EMDB/PDB for you.

---
_Verification: this page depends on the coverage-ledger rows under
**"## Cryo-EM (single-particle reconstruction)"** — chain `cryosparc_standard_spa`
23-step workflow + step processes (motion / CTF / blob+template pick / 2D ×2 /
ab-initio / homo+local-CTF+NU refine / FSC / local-res / sharpen) at `main.nf`
(C), particles-entry `import_mode` (C), sample-type presets + QC profile routing
`qc_trace_monitor.py:1085-1093,342-403` (C), FSC 0.143 gate ≤4/adv/>15 wired
`main.nf:2631-2640` + `qc_evidence.yaml:740-758` (C; cutoffs SILVER, metric GOLD),
CTF fit-quality ≥0.70 + 0.5 red-line `qc_evaluator.py:77` / `qc_trace_monitor.py:41-45`
(C), motion drift + particle-count gates `qc_evidence.yaml:760-788` (C), viewer
taxonomy for `.mrc` density + FSC/motion/CTF JSON charts + `.cs` download-only
`step-output-preview.tsx` / `density-map-viewer.tsx` (C), routing probe
`candidates.yaml:72-75` (C), EMPIAR-10025 gold dataset (staged S3; registry gap
🔧, numeric live-run L / ⏳), tutorial-vs-code tool-name + threshold mismatches
documented (C 🔧), and the roadmap/gap rows including cryo-ET, cryo autoloop,
ensemble→cryptic-pocket mega-chain, and Batch (🗺️)._
