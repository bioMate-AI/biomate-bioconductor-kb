# BioMate: Licensed Tool Integration Plan
**Date:** 2026-05-04  
**Context:** Strategic reposition — BioMate as orchestration layer, not budget alternative

---

## 1. Positioning Principle

BioMate does not compete with Simcyp, Schrödinger, or NONMEM. It **orchestrates** them.

When a user has a Simcyp license, BioMate:
1. Extracts parameters from natural language
2. Generates the Simcyp input files / CLI call
3. Injects the user's license credential at runtime
4. Captures outputs, runs QC gates, auto-remediates
5. Generates the IND §2.6.5 narrative from the Simcyp result

The user gets Simcyp's regulatory-grade accuracy + BioMate's accessibility, QC, and documentation. Neither tool alone does this.

---

## 2. Legal Framework — Bring Your Own License (BYOL)

### Established pattern (already in codebase):
- **User provides** their own license server address or license key
- **BioMate injects** it as an environment variable at Nextflow container launch
- **BioMate never holds** master credentials for high-cost commercial tools
- **BioMate holds** master credentials only for free-tier tools (AlphaFold3 docker auth, Boltz2 NVIDIA NIM free tier)

### Legal classification of tools:

| Tool | License Type | BioMate Role | Legal Risk |
|------|-------------|--------------|------------|
| Schrödinger (Glide, FEP+, Prime) | Commercial FlexLM | BYOL — user provides `27008@server` | None — user holds license; BioMate is execution layer |
| Simcyp | Commercial FNP | BYOL — user provides license file path | None — same |
| NONMEM | Commercial (ICON) | BYOL — user provides NONMEM install path | None — same |
| GastroPlus | Commercial (SimPlus) | BYOL — user provides license key | None — same |
| StarDrop | Commercial (Optibrium) | BYOL — user provides license server | None — same |
| MOE | Commercial (CCG) | BYOL — already implemented | None — already live |
| AMBER | Academic-free / commercial | Already implemented (free academic build in ECR) | None |
| PK-Sim | Open source (LGPL) | BioMate ships Docker image | None — free |
| GROMACS | Open source (LGPL) | Already implemented | None |
| nlmixr2 | Open source (GPL) | Already implemented | None |
| OpenFE | Open source (MIT) | Already implemented | None |

### What BioMate must NOT do:
- Never redistribute Schrödinger/Simcyp/NONMEM binaries in ECR images without license
- Never share a single institutional license across multiple BioMate users (license terms prohibit this)
- Never advertise "includes Schrödinger" — say "supports Schrödinger when you bring your license"

### What BioMate CAN do:
- Ship Docker images with the tool's **free CLI components** (Schrödinger's schrodinger_run, rdkit, openbabel) that work without a license for non-licensed tasks
- Provide open-source fallback workflows that run without any license
- For academic institutions: offer a "shared demo license" pool if the license terms permit concurrent academic use (check per vendor)

---

## 3. Current State Audit

### ✅ Already implemented (licensed wrappers)
| Tool | Workflow ID | Quality | Notes |
|------|-------------|---------|-------|
| Schrödinger Glide SP/XP/HTVS | 12801 | Real wrapper | Calls `glide` CLI; full LigPrep + grid + docking |
| AMBER pmemd GPU | 12802 | Real wrapper | Calls `pmemd.cuda`; GAFF2 ff; production MD |
| MOE Covalent Docking | 12803 | Real wrapper | Calls `moebatch`; SVL script for covalent |

### ✅ Already implemented (open source, best-in-class)
| Tool | Workflow ID | Quality | Notes |
|------|-------------|---------|-------|
| GROMACS | 12799 | Best open | MM-GBSA; CHARMM36/OPLS4 ff |
| OpenFE RBFE | 12830 | Best open | Production RBFE; AT-SOMD; lomap2 |
| REINVENT4 | 12800 | Best open | AZ open-sourced; state-of-art generative |
| AiZynthFinder | 12806 | Best open | MIT; ASKCOS comparable; retrosynthesis |
| DiffDock | (tool) | Best open free | SOTA diffusion docking |
| nlmixr2 PopPK | 12892 | Best open | R; FDA-acceptable; SAEM estimation |
| AlphaFold DB | 12647 | Best available | 200M+ structures |

### ❌ Missing licensed wrappers (highest priority first)

| Priority | Tool | Domain | Why Critical | Effort |
|----------|------|--------|-------------|--------|
| P1 | **Simcyp** | PBPK | Regulatory gold standard; EMA Qualification Opinion 2025; used in every NDA | 3 days |
| P1 | **NONMEM** | PopPK | FDA submission-grade; every NDA PopPK report; 40yr industry standard | 2 days |
| P2 | **Schrödinger FEP+** | RBFE | Best FEP accuracy; Glide exists but FEP+ is separate suite; top-20 pharma lead opt | 2 days |
| P2 | **GastroPlus** | PBPK+ADMET | Best PBPK absorption model (ADAM); PBBM; regulatory second option to Simcyp | 2 days |
| P3 | **StarDrop** | ADMET/SAR | Best ADMET visualization + Nova generative; Optibrium API available | 2 days |
| P3 | **Monolix** | PopPK | SAEM estimation; European pharma standard; Lixoft API | 1 day |

### ❌ Missing open-source wrappers (best-in-class, no license needed)

| Priority | Tool | Domain | Why Critical | Effort |
|----------|------|--------|-------------|--------|
| P1 | **PK-Sim** | PBPK | Free open-source PBPK; OSP Suite; ontogeny models; EMA-accepted | 2 days |
| P1 | **AutoDock-GPU** | Docking | Free; 100× faster than Vina; GPU-accelerated; SMINA variant | 1 day |
| P2 | **DeepPurpose** | DTI | Best open DTA prediction; MIT; CNN/Transformer | 1 day |
| P2 | **GNINA** | Docking | CNN scoring; AutoDock-based; better than Vina for protein flexibility | 1 day |

---

## 4. Implementation Plan

### Phase 1 (this session): P1 licensed wrappers + license_registry entries

**4.1 Add to license_registry.py:**
- `simcyp` — FNP license file path; BYOL; open alt: pk_sim
- `nonmem` — ICON license; BYOL; open alt: nlmixr2
- `gastroplus` — SimPlus license key; BYOL; open alt: pk_sim
- `schrodinger_fep` — same FlexLM as Glide but FEP+ token pool; BYOL

**4.2 Build Simcyp PBPK wrapper:**
- Accepts: compound params, study design, population (virtual trial)
- Calls: `simcyp -i input.pps -o output/` via CLI
- Fallback: if no license, routes to BioMate's own `pbpk_simulation` with notice
- Output: Simcyp population PK results + validation plots + IND §2.6.5 auto-narrative

**4.3 Build NONMEM PopPK wrapper:**
- Accepts: NONMEM dataset (.csv), model type (1/2-compartment), estimation method
- Calls: `nonmem run001.ctl` or `nmfe75 run001.ctl run001.lst`
- Fallback: if no license, routes to `nlmixr2_population_pk`
- Output: parameter estimates, ETAs, VPCs, GOF plots, PopPK report

**4.4 Build PK-Sim wrapper (open source, no license):**
- Calls PK-Sim CLI (`pk-sim --run simulation.json --export results/`)
- Full OSP Suite parameters: tissue distribution, ontogeny, DDI
- No license gate — ships in BioMate biomni-tools ECR image

### Phase 2 (next session): P2 items
- Schrödinger FEP+ wrapper
- GastroPlus wrapper  
- GNINA docking (open, better than Vina)

### Phase 3: P3 items
- StarDrop API integration
- Monolix wrapper
- DeepPurpose DTI

---

## 5. Routing Strategy

Each domain gets a **tiered routing** based on license availability:

```
User query: "Run PBPK for my compound, 10mg/kg oral"

BioMate checks:
  1. Does user have Simcyp credential? → simcyp_pbpk (regulatory grade)
  2. Does user have GastroPlus credential? → gastroplus_pbpk (regulatory grade)  
  3. No license? → pk_sim_pbpk (open source, regulatory-accepted) OR pbpk_simulation (BioMate native)
  
QC gate applies regardless of which tool ran.
IND narrative generated from whichever tool's output.
```

This is **the moat**: no other platform does multi-tier routing with fallback + auto-QC + IND docs.

---

## 6. Quality Hierarchy Per Domain

| Domain | Tier 1 (submission) | Tier 2 (IND-ready) | Tier 3 (screening) |
|--------|--------------------|--------------------|-------------------|
| PBPK | Simcyp (BYOL) / GastroPlus (BYOL) | PK-Sim (open) | BioMate native pbpk_simulation |
| PopPK | NONMEM (BYOL) | nlmixr2 (open) | BioMate Monte Carlo |
| FEP/RBFE | Schrödinger FEP+ (BYOL) | OpenFE (open) | BioMate ΔΔG surrogate |
| Docking | Schrödinger Glide XP (BYOL) | GNINA/DiffDock (open) | AutoDock Vina (open) |
| MD | AMBER pmemd (BYOL/free acad) | GROMACS (open) | BioMate native |
| Covalent | MOE (BYOL) | GNINA covalent (open) | BioMate warhead scoring |
| ADMET | StarDrop (BYOL) | ADMET-AI (open) | BioMate ML (ChEMBL) |
| Safety | DILIsym (BYOL, if integrated) | BioMate CiPA/S7A ODE | QSAR flags |
| Retrosynthesis | Syncraft (BYOL) | AiZynthFinder (open) | BioMate structural rules |

User sees: **"Running with Simcyp (your license) — regulatory-grade output"** or **"Running with PK-Sim (open source) — IND-ready output"** — always transparent about which tier they're getting.
