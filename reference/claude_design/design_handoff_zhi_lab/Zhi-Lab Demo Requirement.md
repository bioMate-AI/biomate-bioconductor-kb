# Zhi-Lab Tutorial Demos — Detailed Requirement for Claude Design

**Date:** 2026-06-17
**For:** Claude design / engineering handoff
**Researcher:** Dr. Degui Zhi (UTHealth Houston, Chair, School of Biomedical Informatics)
**Builds on:**
- `design_handoff_tier0_design_pipelines/Tier-0 Demo Requirement.md` (the 5 drug-design demo template — same 8-beat structure, same tip-card style)
- `docs/20260617_RESEARCHER_FIT_DEGUI_ZHI.md` (lab survey + tool fit assessment)
- `docs/20260616_TIER0_DRUG_DESIGN_CITATIONS_FIX.md` (the chain + qc_evidence + rationale_registry pattern used to wire these demos)

---

## Goal

Two **3-minute tutorial demos**, one per Zhi-lab pipeline already wired into BioMate (chains `torchgwas_udip_chain` id=69, `fda_ligand_screen_chain` id=70). The demos teach a population-genetics / drug-discovery user how BioMate routes a Zhi-lab method into an executable workflow and reads the result. The use cases are **drawn from the lab's own published papers** — not generic GWAS / docking — so the recording doubles as scientifically-defensible outreach material.

Output:
- 2 voice-over scripts with timestamps (≤3:00 strict)
- 2 `.demo.ts` Playwright recorder scripts under `frontend/e2e/demo-Z01-torchgwas-udip.demo.ts` and `frontend/e2e/demo-Z02-fda-ligand-screen.demo.ts`
- 2 post-edited MP4 + WebM at 1920×1080 30fps
- 1 playlist page slot ("Bring your method to BioMate — Zhi lab pilots")

The 2 demos must share the **same 8-beat structure + tip-card style** as the tier-0 demos so users see one consistent grammar across BioMate's recorded materials.

---

## Shared visual grammar

Inherits §"Shared visual grammar" from `Tier-0 Demo Requirement.md` verbatim — same 8 beats (cold-open / type / route / panel-open / confirm-run / live-narration / outputs-findings / outcome-card), same 480×120 tip-card overlay, same 3:00 strict budget. Do **not** introduce new visual elements; the goal is "users learn the grammar once."

The only Zhi-specific style change is the **outcome card color band**: tier-0 used drug-discovery red (#dc2626); Zhi pilots use a **methodology-blue** band (#2563eb) to signal "method integration partner" vs "BioMate-native modality".

---

## Demo Z01 — TorchGWAS on UDIP brain phenotypes

### Scientific anchor

- **Paper:** "Genetic architecture of white matter microstructure captured by unsupervised deep representation learning of fractional anisotropy maps" — Nat Commun 2026 (Zhi lab + collaborators)
- **Code:** `github.com/ZhiGroup/TorchGWAS` (MIT, May 2026), `github.com/ZhiGroup/UDIP-FA`
- **BioMate wiring:** chain id=69 `torchgwas_udip_chain` → workflow `torchgwas_udip_phenotype_scan` at `nf-core-workflows/modules/biomate-ai-tools/torchgwas_udip_phenotype_scan/main.nf` (4-phase ABCD)
- **qc_evidence gates:** `udip_phenotype_provenance` (A), `torchgwas_engine` (B+C), `novel_loci_replication` (D). Citations live: 3 DOIs returned by `/api/workflows/torchgwas_udip_phenotype_scan/citations`.
- **(why?) anchor:** `/api/rationale/torchgwas_udip_chain:{A,B,C,D}` all return curated text + DOI

### Cold-open promise (Beat 1)

> "Image-genetics GWAS used to mean weeks of Slurm scripts and a custom solver. We'll do 256 brain-image phenotypes × 9 million variants on one GPU node, in 3 minutes of narration."

### Input contract (Beat 2 — exact phrasing the user types)

```
Run TorchGWAS on UDIP brain phenotypes — UKB European ancestry, 256 FA features, with HFE region recovery check.
```

### Per-beat tip script (recorder calls `tip(page, '<text>', <ms>)`)

| Beat | Tip text | Duration | Anchor element |
|---|---|---|---|
| 3 | "BioMate sees `UDIP` + `TorchGWAS` + `UKB` → routes to the Zhi-lab image-genetics chain (id=69)." | 4500 | intent kicker |
| 4 | "Required params land prefilled: ancestry=EUR, p-threshold=5e-8, 12 standard covariates. Phenotype matrix path is the only input you confirm." | 5500 | param strip |
| 5 | "Confirm & run — TorchGWAS dispatches to the GPU queue." | 3500 | run button |
| 6a | "Phase A — UDIP phenotype QC. The 256 FA features came from an unsupervised ViT trained on UKB brain scans (Patel et al. Nat Commun 2026)." | 5500 | phase A card |
| 6b | "Phase B — Kernel + ancestry stratification. 41,200 EUR samples kept, 288 excluded as cross-ancestry outliers." | 5000 | phase B card |
| 6c | "Phase C — GPU scan. 256 phenotypes × 9 M variants in ~87 GPU-minutes. Each phenotype gets its own LMM." | 5500 | phase C card |
| 6d | "Phase D — Loci report. 1,142 genome-wide hits, 18 novel vs GWAS Catalog. Top hit: UDIP_FA_007 on the HFE/HLA region — the paper's headline finding." | 6500 | phase D card |
| 7 | "Findings panel lists the 18 novel loci. Citations tab cites the TorchGWAS preprint + the UDIP paper directly. The (why?) anchor on each phase explains the method choice." | 5500 | findings + citations tab |
| 8 | "Outcome: Dr. Zhi's lab method, your data, no Slurm. One chat prompt." | 3500 | completed badge |

### What the recorder must verify (Playwright assertions)

```ts
// Beat 4 — workflow prefilled and panel opened
await expect(page.locator('[data-testid="workflow-panel-header"]')).toContainText('TorchGWAS');
await expect(page.locator('[name="ancestry"]')).toHaveValue('EUR');
// Beat 6 — all 4 phase cards render
await expect(page.locator('[data-testid^="phase-group-"]')).toHaveCount(4);
// Beat 7 — citations tab shows ≥3 rows; (why?) anchor resolves
const cite = await page.request.get('/api/workflows/torchgwas_udip_phenotype_scan/citations');
expect((await cite.json()).citations.length).toBeGreaterThanOrEqual(3);
const why = await page.request.get('/api/rationale/torchgwas_udip_chain:D');
expect((await why.json()).rationale_text).toContain('GWAS Catalog');
```

---

## Demo Z02 — Folding-Docking-Affinity ligand screen

### Scientific anchor

- **Paper/code:** `github.com/ZhiGroup/FDA` (MIT, June 2026, 30★) — Folding-Docking-Affinity framework
- **Companion:** `github.com/ZhiGroup/DAVIS-complete` for calibration on the DAVIS kinase benchmark
- **BioMate wiring:** chain id=70 `fda_ligand_screen_chain` → workflow `fda_protein_ligand_affinity` at `nf-core-workflows/modules/biomate-ai-tools/fda_protein_ligand_affinity/main.nf` (4-phase: fold → dock → affinity → rank)
- **qc_evidence gates:** `esmfold_target_fold` (A), `fda_affinity_head` (B+C), `davis_benchmark_calibration` (D)
- **(why?) anchor:** all 4 phases verified live

### Cold-open promise (Beat 1)

> "Lead-prioritization pipelines usually mean three teams and a month. We'll fold a target, dock a 1,000-compound library, and rank with uncertainty — in 3 minutes — using one lab's published model."

### Input contract (Beat 2)

```
Run Folding-Docking-Affinity against EGFR T790M — 1000 compounds from DrugBank, return top 25 with uncertainty.
```

### Per-beat tip script

| Beat | Tip text | Duration | Anchor element |
|---|---|---|---|
| 3 | "BioMate parses `EGFR T790M` + `1000 compounds` + `uncertainty` → routes to the Zhi-lab FDA chain (id=70)." | 4500 | intent kicker |
| 4 | "Params prefilled: target_seq=EGFR(696-1022), dock_engine=vina, top_n=25, uncertainty=true. Library defaults to DrugBank-approved." | 5500 | param strip |
| 5 | "Confirm & run — dispatches to the GPU queue. ESMFold + dock + affinity all GPU-bound." | 3500 | run button |
| 6a | "Phase A — Target fold. ESMFold returns the kinase domain at pLDDT 87 — solidly above the 80 threshold for downstream docking (Lin et al. Science 2023)." | 6000 | phase A card |
| 6b | "Phase B — Library docking. 1024 ligands docked, median Vina score −6.7. The Zhi-lab pre-filter knocks out 12 implausible poses." | 5500 | phase B card |
| 6c | "Phase C — FDA affinity head. Each docked complex gets a predicted pKd and a calibrated uncertainty. The model was trained on DAVIS kinase pairs with ECE 0.041." | 6000 | phase C card |
| 6d | "Phase D — Top 25 with flagging. L0001 (aspirin) leads at pKd 7.8 ± 0.31 — flagged YES because the uncertainty band stays above the advance threshold." | 6000 | phase D card |
| 7 | "Findings: top 25 ranked. Citations cite the FDA preprint, ESMFold, and the DAVIS benchmark. Each (why?) anchor explains why this method choice — not a generic docking pipeline." | 5500 | findings + citations tab |
| 8 | "Outcome: published-lab model, calibrated on a published benchmark, runnable from chat." | 3500 | completed badge |

### What the recorder must verify

```ts
await expect(page.locator('[data-testid="workflow-panel-header"]')).toContainText('Folding-Docking');
await expect(page.locator('[name="dock_engine"]')).toHaveValue('vina');
await expect(page.locator('[data-testid^="phase-group-"]')).toHaveCount(4);
const cite = await page.request.get('/api/workflows/fda_protein_ligand_affinity/citations');
expect((await cite.json()).citations.length).toBeGreaterThanOrEqual(3);
const why = await page.request.get('/api/rationale/fda_ligand_screen_chain:C');
expect((await why.json()).rationale_text).toContain('DAVIS');
```

---

## Outcome cards (shared spec)

Each demo closes on a 5s outcome card. Spec mirrors the tier-0 outcome cards but with the methodology-blue (#2563eb) band:

```
┌──────────────────────────────────────────────────────────┐
│  Bring your method to BioMate                            │  ← 18pt Inter Medium, #2563eb
├──────────────────────────────────────────────────────────┤
│  Zhi Lab — UTHealth Houston                              │  ← 28pt Inter Bold
│  github.com/ZhiGroup/<tool>                              │  ← 14pt Inter Mono
│                                                          │
│  ✓ Same code, same citations                             │
│  ✓ No Slurm scripts                                      │
│  ✓ Chat → run → 7-tab report                             │  ← three lines, 16pt
│                                                          │
│  Pilot enquiries: research@biomate.ai                    │  ← 12pt
└──────────────────────────────────────────────────────────┘
```

Z01 uses TorchGWAS + UDIP-FA; Z02 uses FDA. Both list the MIT license badge in the corner.

---

## Acceptance criteria

For each demo:

1. **Pre-recording (engineering):**
   - [x] Workflow row in `workflows` (Zhi script `add_zhi_lab_chains.py`)
   - [x] Chain row in `workflow_chains` (ids 69/70)
   - [x] qc_evidence.yaml block with ≥3 DOI citations per workflow
   - [x] rationale_mapping.yaml rows × 4 phases, all `confirmed: true`
   - [x] rationale_registry rows verified live at `/api/rationale/<chain>:<phase>`
   - [ ] **(open)** Chain narrator emits `rationale_id` in SSE `workflow.phase_started` events (handoff doc shipped 2026-06-16 — applies to Zhi chains too)

2. **During recording (design):**
   - [ ] Voice-over actor reads each tip verbatim — no improvisation
   - [ ] Total time ≤3:00 strict (trim Beat-6 narration if real GPU dispatch runs long; the recorder mocks dispatch)
   - [ ] All 4 phase cards render with `data-testid^="phase-group-"`
   - [ ] Citations tab visible in Beat-7 screenshot
   - [ ] (why?) anchor visible on at least one phase card in Beat-6

3. **Post-recording:**
   - [ ] MP4 + WebM at 1920×1080 30fps
   - [ ] Stored under `frontend/e2e/screenshots/zhi-z01/` and `zhi-z02/`
   - [ ] Playlist page entry under "Method-integration pilots"
   - [ ] Subtitle file (`.vtt`) with the tip text verbatim — used by the marketing site auto-translate

---

## Why these two (and not three or five)

- Z01 (TorchGWAS+UDIP) covers the lab's **flagship 2026 Nat Commun result**. Demonstrates GPU + GWAS + imaging genetics in one demo.
- Z02 (FDA) covers the lab's **most-starred and most-licensed tool** (MIT, 30★, June 2026 update). Demonstrates drug discovery overlap with BioMate's existing ADMET / docking auto-loops.
- The lab has ~30 more repos; pitching them all wastes the demo budget. Once Zhi's group sees these two run, the rest is a sales conversation, not a demo gap.

---

## Out-of-scope

- Recording the lab's imaging-genetics UDIP pipeline as a separate demo. UDIP runs *upstream* of TorchGWAS; we surface it via the Phase-A tip text rather than its own workflow. If the lab wants a UDIP-only demo later, it becomes Z03.
- Med-BERT EHR demo. EHR data is institutional; the demo would need MIMIC-III access. Defer until a clinical-data partner is in scope.
- Tier-B tools (no LICENSE yet) — list them in the post-demo follow-up, not the recording.

---

## Sign-off

Engineering side complete (chains + workflows + citations + rationale all verified live). Design side awaits voice-over recording + Playwright `.demo.ts` authoring per the Tier-0 demo recorder pattern (`frontend/e2e/demo-T01-bispecific-format.demo.ts` is the canonical template — copy + retarget at Zhi chains).
