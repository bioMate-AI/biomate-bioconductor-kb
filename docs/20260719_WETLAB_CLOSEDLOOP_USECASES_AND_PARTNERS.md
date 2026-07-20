# Computation↔Wet-Lab Closed-Loop — Use Cases & Partner Landscape (research-backed)

**Date:** 2026-07-19 · Extends `20260719_WETLAB_CLOSED_LOOP_DBTL_INTEGRATION.md`
Two web-research passes (cited). Flags where evidence is weak.

## 0. Correction — the Biomni memory
There is **no published Biomni + online-protein-design-API wet-lab loop.** Biomni's (Stanford, bioRxiv 2025.05.30.656746) wet-lab arm is **PyLabRobot code-generation** — i.e., exactly the `lab_automation` tools in our own AI-tool DB. The real "AI agent → design API → wet-lab" loop is **Adaptyv Bio's TREM2/EGFR competitions** (autonomous agents designed binders, Adaptyv assayed). Don't attribute an Adaptyv loop to Biomni.

## 1. Closed-loop use cases we can actually run

| # | Use case | Loop | Maturity / who | For us |
|---|---|---|---|---|
| **A** | **Cyclic-peptide permeability/binding** | design macrocycle → synthesize → PAMPA/Caco-2 + SPR → refine ADMET model | **WHITE SPACE** — data (CycPeptMPDB/PAMPA), models (CPMP R²≈0.67), generative design (CCPep) all mature, **but no published end-to-end loop** | **First pilot — our moat, fast/cheap assay, first-mover** |
| **B** | **Autoimmune immune-cell perturbation** | predict target/perturbation → CRISPR/Perturb-seq or T-cell functional assay → refit virtual cell | Reference: **IterPert** (Genentech, active-learning Perturb-seq, ~⅓ the experiments); "Closing the loop: teaching scFMs from perturbations" (bioRxiv 2025.07); **Immunai** (commercial, internal) | Second loop — higher value, slower, needs primary-immune-cell partner |
| **C** | Binder/protein design | design → Adaptyv API (BLI/SPR) → refine | Adaptyv competitions; Chai-2 (16% hit rate), Nabla, Cradle | Only if we extend to protein binders |

## 2. The API-closable path (loop closed in software)
Only **two** genuine programmatic wet-labs exist today:
- **Adaptyv Bio** — the *one* public, self-service **assay API**: "one API call" → JSON (KD, Tm, expression) via **BLI + SPR**, agent-ready scoped keys built for overnight autonomous runs. (Cradle/Nabla/Chai run their own labs but expose **no** external assay API.) Precedent: **Tamarind Bio** integrated Adaptyv's API inline.
- **Emerald Cloud Lab (ECL)** — **in Austin, TX** — code-first **Symbolic Lab Language** + Command Center (4,500+ functions) submitting experiments and returning structured data across **chemistry AND immune/cell** (flow, ELISA, SPR/BLI, qPCR, cell bio). **The single best fit to close our loop programmatically, and it's local.**
- Secondary: **Arctoris** (API + SiLA2, did a closed-loop DMTA with IBM) — but partnership-gated, not self-serve. **Strateos** shut public API access in 2023.

## 3. Partner shortlist (by role in the loop)

| Role | Best partner(s) | Access | Fit |
|---|---|---|---|
| **Automated wet-lab (API)** | **Emerald Cloud Lab (Austin TX)** | public code-first API | chem + flow/ELISA/SPR |
| Automated (secondary) | Arctoris | API+SiLA2, partnership | cell bio + SPR |
| **Cyclic-peptide synth+perm+bind (one roof)** | **WuXi TIDES**, **Pharmaron** | quote | macrocycle + PAMPA/Caco-2 + SPR |
| Cyclic-peptide (self-service) | **GenScript** | online ordering | synth + SPR (no permeability) |
| **Autoimmune cell validation (CRO)** | **Charles River** (explicit Th1/iTreg/Th17 + Treg-suppression), WuXi Biology* | quote | primary human T-cell |
| Human PBMC/T-cell flow + CyTOF (service) | **MD Anderson FCCIF/ORION core** | core facility | 18-param flow, CyTOF |

*WuXi: confirm legal entity + BIOSECURE-type due diligence for a US platform.

## 4. The standout academic pairing (local, near-perfect fit)
Both in the Texas Medical Center (~15 min apart), already bridged by Xiao's Rice–Baylor **SynthX Center**:
- **Han Xiao (Rice)** — genetically-encoded **cyclic-peptide display** libraries; **already screened a cyclic-heptapeptide library against IL-17A** (our exact autoimmune macrocycle target from the earlier UC1 benchmark). Discovery/chemistry engine.
- **Christine Beeton (Baylor)** — peptide immunomodulators (Kv1.3; co-inventor of **ShK-186/dalazatide**, Phase 1b–2a for MS/RA); **runs primary human + rodent T-cell assays** (proliferation, cytokine, trafficking) + EAE/CIA models. The rare Texas faculty combining therapeutic-peptide dev with hands-on autoimmune T-cell wet-lab.

Supporting Texas: **Shervin Assassi (UTHealth)** — human autoimmune scRNA/scATAC (scleroderma/lupus/myositis); **Roza Nurieva (MD Anderson)** — Th17/Tfh/Treg (mouse-heavy, verify human); **Chandra Mohan (U Houston)** — lupus/SLE human cohorts; **Anslyn / Ball (UT Austin/Rice)** — macrocyclization chemistry.

## 5. Recommended first pilot (concrete)
**Cyclic-peptide permeability loop, closed via ECL + Xiao/Beeton:**
1. Our macrocycle model designs N≈20–50 candidates against an autoimmune PPI (start **IL-17A** — Xiao already has the display data + baseline).
2. **Build/Test:** synthesize + PAMPA via **ECL (Austin, API)** or **WuXi TIDES/Pharmaron** (one-roof); binding via ECL SPR or Adaptyv API.
3. **Learn:** ingest results → uncertainty-guided retrain (active learning) → next round. Store rounds in S3 flywheel.
4. **Validation partner:** Beeton (Baylor) for primary human T-cell functional confirmation of top hits; Xiao (Rice) for the display/affinity chemistry.

**Why this first:** it sits on genuine white space, the assay is fast/cheap/quantitative, the loop closes in software (ECL/Adaptyv API), and the ideal academic pair is *local and already working together on our exact target.* The autoimmune immune-cell loop (IterPert-style) is the higher-value second loop once a primary-cell partner (Beeton / MD Anderson core) is engaged.

## 5b. Fuller catalog of closed-loop use cases (beyond A/B/C)
Grouped by modality; ✓ = BioMate already has the *Design* workflow, so only Build/Test/Learn need wiring.

**Protein / biologic design (Adaptyv/Cradle/Chai — API-closable):**
- Antibody / nanobody **affinity maturation + developability** — ✓ `scfv_antibody_design`; assay = BLI/SPR + Tm (Adaptyv API).
- **Enzyme engineering / directed evolution** — activity assay; Cradle specializes.
- Protein **stability / Tm / aggregation** optimization — Adaptyv measures Tm.

**Cell & functional-genomics (Perturb-seq / scRNA / flow):**
- **Perturb-seq target discovery** — ✓ `gears_perturbation`; assay = scRNA; reference = IterPert.
- **CAR / cell-therapy construct optimization** — ✓ `cart_construct_design`; assay = cytotoxicity / exhaustion / on-target. **Strong autoimmune tie:** Houston Methodist (Kazzaz) runs autoimmune CAR-T trials.
- Immune-cell **phenotypic** optimization — flow / cell-painting readout.

**Small-molecule (classic DMTA):**
- **ADMET / PK multi-parameter** optimization — ✓ ADMET engine; ADMET is *the* binding constraint (per our survey).
- **PROTAC / molecular-glue degrader** design — cellular degradation assay.
- **Cardiac-safety CiPA-in-the-loop** — ✓ `cipa_cardiac_safety_ode`; in-vitro CiPA assay.

**Nucleic-acid / regulatory (MPRA / reporter):**
- gRNA / CRISPR **editing-efficiency** optimization.
- **5′UTR / promoter / enhancer** design → MPRA.
- **Aptamer** design (SELEX-in-the-loop).

**Synbio / bioprocess (DBTL-native; Culture Biosciences API):**
- **Metabolic pathway / strain engineering** → titer.
- **Bioprocess / media / fermentation** optimization → bioreactor yield.
- **Genetic circuit / biosensor** design.

**Formulation / delivery:**
- **LNP / mRNA delivery** formulation optimization.
- Crystallization / solid-form screening.

**Meta:** **assay/protocol self-optimization** — PyLabRobot titration (our `DBTLController` sim demo already titrates cytokine-stimulation volume).

**Highest-fit for BioMate now (we have the Design side):** cyclic-peptide permeability (A), scFv-antibody affinity (Adaptyv), **CAR-T for autoimmune** (cart_construct + Houston Methodist), Perturb-seq immune target discovery (gears + IterPert), ADMET/CiPA safety loops.

## 6. Honest flags
- Biomni-Adaptyv attribution: **corrected** (unsupported).
- No CRO/tech-bio exposes a real cell-validation **API** — only cloud labs (ECL) close the loop programmatically.
- No published fully-closed **cyclic-peptide** loop exists (white space, not proven impossible).
- Verify: WuXi entity/BIOSECURE; ECL Austin vs SSF contracting entity; Nurieva/Corry human-cell scope; "CBL" identity (likely not a real peptide CRO).
