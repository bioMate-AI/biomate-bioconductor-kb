# GROMACS receptor sizing, literature survey, and campaign post-mortem

**Date:** 2026-05-18  
**Context:** ANDV inhibitor track step 5 (`gromacs_mmgbsa`) failed on full 9P3I tetramer solvation; this document consolidates root-cause analysis, literature-aligned MD protocol guidance, infra fixes, and community-contribution framing.

---

## 1. Executive summary

| Issue | Verdict | Action |
|-------|---------|--------|
| GROMACS S1a (`9bf5f9a2`) | **Failed** at `SYSTEM_SETUP` — full tetramer → ~758k waters, died at tleap grid charges | **Receptor crop** before tleap (implemented); retry on HPC queue |
| Status API showed `running` | **Infra bug** — read stub 8-line `nextflow.log` | Fixed in `nextflow_executor.py` (trace + `work/.nextflow.log` merge) |
| E2E INH-C1 / PA-1 failures | **System** (chat routing / AI timeout), not bad test queries | Pocket fast-path + PA-1 recovery parity |
| Full tetramer MD | **Not literature practice** for ligand MM-GBSA | Use local pocket model (Tier B below) |

---

## 2. GROMACS S1a failure (9P3I full receptor)

**Run:** `9bf5f9a2-2420-4189-888b-d455909a614d` (`20260528T033751Z`)

| Metric | Value |
|--------|-------|
| Input | Full 9P3I chains A–H (~30,852 ATOM records) |
| tleap waters | ~758,636 TIP3P |
| Box | ~292 Å cube (~25M Å³) |
| Failure | `SYSTEM_SETUP` ×3, exit 143 (~2 h each); “Calculating grid charges” |
| False status | Poller reported `running` until trace-aware fix |

**Manifest:** `research/anti-virus/science_sprint/runs/20260528T033751Z/track_inh_md/manifest.json`

**Why hardware alone fails:** AWS Batch scales *parallel jobs*, not one serial tleap charge-grid build on a multi-million-atom system. Even with 64–128 GB RAM and longer timeouts, full viral GP assemblies are outside standard ligand-MD practice.

---

## 3. Measured 9P3I sizing (campaign S3 PDB)

| Model | ATOM count (approx.) | Solvated estimate |
|-------|----------------------|-------------------|
| Full tetramer (chains A–H) | 30,852 | ~758k waters (observed failure) |
| Vina box trim (+8 Å pad) | 1,327 | ~100× smaller |
| Single chain A | 4,028 | ~17× smaller than failed run |

---

## 4. Literature and community practice

### Two MD tiers

**Tier A — full viral glycoprotein (research MD, not ligand MM-GBSA default)**  
Example: CHARMM-GUI COVID spike systems — ~2.2–2.4M atoms, 640–710k waters, 250×250×370 Å boxes; μs production on HPC.

**Tier B — drug-discovery ligand MD (our target)**  
Local receptor domain, **10–15 Å padding** beyond binding site, ff14SB/AMBER + GAFF2 + TIP3P, **10–100 ns** production, MM-PBSA/GBSA for ranking.

**Hantavirus precedent:** [Frontiers 2023 Gn study](https://www.frontiersin.org/articles/10.3389/fimmu.2023.1113321/full) — Gn **domain** (not full assembly), ff14SB + GAFF, TIP3P, 300 K, 100 ns, MM-PBSA.

BioMate GROMACS parameters (ff, water, salt, temperature, MM-GBSA) already align with Tier B. The failure was **input geometry**, not force field choice.

### Ranked practical solutions (verified)

| Rank | Solution | Literature / field status |
|------|----------|---------------------------|
| 1 | **Box-trim receptor** (Vina pocket center + 10 Å pad) | Field standard; matches Vina, OpenMMDL (~10 Å), CHARMM-GUI local RBD models |
| 2 | Single chain A only | Acceptable fallback; less pocket context |
| 3 | Reduce `box_padding` alone | Insufficient for full tetramer |
| 4 | Publish without MD | Valid — steps 1–4 + REINVENT4 succeeded in manifest |
| 5 | Pre-flight atom/water guard | Good engineering (future) |
| 6 | `structure_top_pocket.pdb` from fpocket | **Broken** — 1-atom STP pseudoatom, not protein |

---

## 5. Manuscript-aligned MD protocol table (Tier B — ANDV 9P3I pocket)

Use this table in Methods when reporting GROMACS + MM-GBSA after receptor crop.

| Step | Parameter | ANDV campaign value | Literature reference |
|------|-----------|---------------------|----------------------|
| Receptor source | PDB 9P3I | Full deposit, **cropped** to top fpocket center | Local domain models (hantavirus Gn MD) |
| Crop geometry | Box center | From step 1 `top_pocket_center` in manifest | Same as Vina docking box |
| Crop padding | +10 Å beyond half box | `trim_pad=10` | OpenMMDL / GROMACS ligand tutorials (8–15 Å) |
| Receptor FF | amber99sb-ildn | Default workflow | AMBER protein FF family |
| Ligand FF | GAFF2 + AM1-BCC | antechamber + parmchk2 | Wang et al. JCC 2004 |
| Water | TIP3P | Default | Standard biomolecular MD |
| Salt | 0.15 M NaCl | Neutralizing | Physiological |
| Box (tleap) | +12 Å from solute | `box_padding=12` | Typical after local crop |
| Temperature | 300 K | NVT/NPT | Hantavirus Gn study |
| Pressure | 1 bar | NPT | Standard |
| Timestep | 2 fs | `dt=0.002` | Constrained bonds |
| Equilibration | 100 ps NVT + 100 ps NPT | Workflow default | Standard protocol |
| Production | 10 ns (5M steps) or smoke 250k | `--gromacs-n-steps` | 10–100 ns Tier B range |
| Binding ΔG | MM-GBSA (gmx_MMPBSA) | Post-production | Valdes-Tresanco JCTC 2021 |
| Analysis | Backbone RMSD/RMSF | Workflow outputs | Standard stability check |

**Docking consistency:** Vina step uses +8 Å pad; MD crop uses +10 Å — slightly larger solvent shell for dynamics, same pocket center.

---

## 6. Implementation: receptor crop (Vina parity)

**Shared module:** `backend/biomni_workflows/nextflow_nfcore/lib/trim_receptor_pdb.py`

**GROMACS workflow:** `RECEPTOR_TRIM` process before `SYSTEM_SETUP` in  
`backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/gromacs_protein_md/main.nf`

**New params:**

| Param | Default | Purpose |
|-------|---------|---------|
| `box_center` | null | JSON `[cx,cy,cz]` from pocket manifest |
| `box_size` | null | JSON `[sx,sy,sz]` Vina box edges (Å) |
| `trim_pad` | 10.0 | Å beyond half box |
| `auto_trim_receptor` | true | Crop when input ≥ `min_atoms_for_trim` |
| `min_atoms_for_trim` | 5000 | Skip for pre-trimmed receptors |

**Pipeline wiring:** `run_andv_inhibitor_pipeline_nextflow.py` passes pocket box to step 5 via `resolve_pocket_box()` when manifest has `top_pocket_center` or `--use-top-pocket-box`.

**Sprint launcher:** `track_inh_md.py` adds `--use-top-pocket-box` for full 9P3I (default).

**Tests:** `backend/tests/test_trim_receptor_pdb.py`

---

## 7. Status polling fix (false “running”)

**File:** `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

- Merges root + `work/.nextflow.log`
- Reads `workflow-trace.txt` for terminal states
- Promotes stale in-memory `running` → `failed` on `Session aborted` / `ProcessFailedException`

**Tests:** `backend/tests/test_nextflow_false_success.py` (8/8 pass)

---

## 8. E2E failures (INH-C1, PA-1) — system, not test bugs

| Test | Verdict | Evidence |
|------|---------|----------|
| **INH-C1** (pocket) | System | Generic fallback + “Workflow generation unavailable”; no pocket fast-path in `galaxy-assistant.ts` |
| **PA-1** (epitope) | System | 4 min hang on “BioMate is thinking…”; PA-1 lacks PB-1 `waitForWorkflowCard` recovery |

Contributing infra: Redis down during E2E setup; empty workflow tables in `universe.sqlite`.

---

## 9. Are we doing innovative work that contributes to the community?

**Short answer:** Yes, but primarily as **reproducible computational infrastructure and an open campaign case study** — not as a novel force field or new MD method.

### What is genuinely contributory

1. **Agentic multi-step inhibitor pipeline** — pocket → pharmacophore → ADMET → Vina → MD → REINVENT4 with JSON manifest chain-of-custody, runnable without chat UI (`run_andv_inhibitor_pipeline_nextflow.py`).
2. **Operational honesty** — documenting full-receptor MD failure, false-success detection, and literature-aligned crop fix benefits any group docking large depositions then running MD.
3. **Unified workflow search / E2E harness** — reduces regression risk for Galaxy + Nextflow + Batch integrations.
4. **ANDV-specific open dataset** — 9P3I pocket center, Vina ensemble (S1b), manuscript stack — **applied computational virology**, reusable as a benchmark scenario.

### What is not novel science

- Force fields, MM-GBSA method, fpocket, Vina — established tools.
- ANDV inhibitor hypotheses — computational prioritization, not experimental validation in this sprint.

### How to frame for publication / community

| Audience | Contribution framing |
|----------|---------------------|
| **bioRxiv / methods note** | End-to-end agentic workflow + reproducible manifest + failure-mode documentation |
| **Galaxy / Nextflow community** | Batch executor patterns, receptor trim shared with Vina, status polling fix |
| **Virology / med-chem readers** | Tier B MD protocol table, hantavirus literature alignment, ranked compound list from steps 1–4 |

**Innovation type:** *Engineering + reproducibility + applied campaign* — valuable to the community as **reference implementation and negative-result documentation**, complementary to breakthrough method papers.

---

## 10. Recommended next steps

1. **Smoke GROMACS** with cropped 9P3I (~1,327 atoms) on `biomate-hpc-queue` via `track_inh_md.py`.
2. **Chat routing:** pocket fast-path in `galaxy-assistant.ts`; PA-1 timeout parity with PB-1.
3. **Pre-flight guard:** reject systems estimated >100k atoms before Batch submit.
4. **Manuscript:** paste §5 protocol table into Methods; cite hantavirus Gn MD precedent.

---

## References

- Abraham et al. GROMACS, SoftwareX 2015  
- Case et al. AmberTools, J. Chem. Inf. Model. 2023  
- Wang et al. GAFF2, J. Comput. Chem. 2004  
- Valdes-Tresanco et al. gmx_MMPBSA, JCTC 2021  
- Hantavirus Gn MD: Frontiers Immunol 2023, [doi:10.3389/fimmu.2023.1113321](https://www.frontiersin.org/articles/10.3389/fimmu.2023.1113321/full)
