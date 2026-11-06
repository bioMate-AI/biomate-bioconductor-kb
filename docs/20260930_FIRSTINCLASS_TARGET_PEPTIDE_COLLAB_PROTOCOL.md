# First-in-Class Collaboration Protocol — We Propose (Target + Peptide Structure), They Validate

**Date:** 2026-09-30
**Model:** A **de-novo, first-in-class** drug-development collaboration. **We** identify the target(s) *and* design the cyclic-peptide structure(s) against them; the **hospital partner validates** — biologically, functionally, and clinically. This is the operating protocol for that division of labor, applicable to both candidate partners (SYSUCC / oncology-NPC; Soochow / autoimmune-rheumatology).
**Relationship to prior docs:** supersedes the "use their already-published targets" framing in the two survey briefs' §7 for the *lead* program. Those validated targets (IL-23/IL-23R, R9AP/EphA2) remain excellent **de-risking anchors / platform-proof** vehicles; this protocol is the **first-in-class** track that runs on top.

> **Honesty contract (carried from our target-ID discipline).** The single best-quantified predictor of clinical success is **human genetic support for the target (~2.0–2.6× approval rate; Nelson 2015, Minikel 2024)**, and the effect *grows with confidence in the causal gene*. So our value is **not** "we find novel targets" as a magic trick — target *discovery* is not the bottleneck, target **confidence** is. Our deliverable is a **genetically/causally-credentialed, peptide-tractable, first-in-class target dossier + a designed binder**, and the partner's validation is the **gate that converts a nomination into confidence**. Every target nomination ships with null-model controls and an explicit direction-of-effect call.

---

## 0 · The two-sided contract in one table

| | **We (BioMate) deliver** | **They (hospital) deliver** |
|---|---|---|
| **Target** | De-novo nomination + causal-evidence dossier + druggable-epitope definition | Biological + patient-sample confirmation; genetic KO/KD causality; disease-model relevance |
| **Molecule** | Designed cyclic-peptide structure(s) + predicted binding mode + property vector | Synthesis QC (or via CRO), binding confirmation, functional + in-vivo efficacy |
| **Evidence loop** | Ingest assay results → DPO-retrain generator; next design round | Generate the assay data that closes the loop |
| **Path** | IND-enabling in-silico package (developability/safety predictions) | GMP, tox, **Phase-I via their trial unit** |

**One line:** *we ship a credentialed target and a molecule to hit it; they ship the biology and the clinic that prove it.*

---

## 1 · Stage-gated protocol (end to end)

Nine stages, each with an **owner**, **deliverable**, and a **go/no-go gate**. Stages 1–3 are ours (dry); 4–8 are theirs (wet/clinical); 9 is the loop.

### STAGE 0 — Disease scoping & evidence assembly *(joint)*
- **Do:** fix the indication and patient population with the partner (autoimmune subtype for Soochow; NPC or defined tumor type for SYSUCC). Assemble the evidence substrate: human genetics (GWAS/eQTL/pQTL), disease omics (bulk/single-cell/spatial), perturbation screens, and the partner's own cohort/expression data.
- **Deliverable:** a scoped disease brief + data inventory.
- **Gate:** is there enough human-genetic + disease-omics substrate to credential targets? If not, the partner's cohort data becomes the first shared asset.

### STAGE 1 — De-novo target identification *(us)*
- **Do:** run the genetics-first nomination stack (per `docs/20260817_TARGET_IDENTIFICATION_SURVEY.md`):
  1. **Name the causal gene** — GWAS fine-mapping → **L2G** (locus-to-gene), **colocalization** (eQTL/**pQTL** coloc, PP.H4), **cis-Mendelian-randomization**, and **rare-variant burden**. pQTL/cis-MR are weighted highest (closest to the druggable protein + gives direction).
  2. **Pin the direction of effect** — gain-of-function/disease → *inhibitor/blocker* (peptide antagonist); loss-of-function-protective → *inhibitor*; loss-of-function-disease → *agonist/replacement* (harder for peptides — deprioritize).
  3. **Corroborate in disease context** — single-cell/spatial expression in the right cell state, perturbation-screen dependency, partner cohort signal.
- **Deliverable:** a ranked target list, each with a **causal-evidence dossier** (genetic support tier, direction, cell-type, effect size) **and null-model controls** (degree/annotation-depth null + matched-annotation subset — network centrality is NOT evidence).
- **Gate:** genetic/causal support tier ≥ threshold AND direction is inhibitory (peptide-tractable). Nominations that are network-only or correlative-only are marked **hypothesis-grade**, not lead-grade.

### STAGE 2 — First-in-class + modality-fit filter *(us)*
- **Do:** intersect the credentialed targets with **peptide-modality fit** and **novelty**:
  - **Modality fit:** favor **protein–protein interfaces**, flat/undruggable surfaces, allosteric grooves — where peptides beat small molecules; favor **extracellular/accessible** first (no permeability tax); intracellular targets carry a permeability requirement (our non-canonical/stapled chemistry).
  - **First-in-class check:** cross-reference ChEMBL / DrugBank / clinical pipelines — the target must have **no approved or advanced-clinical drug of any modality against the relevant mechanism** (that is what makes it first-in-class). Distinguish *first-in-class target* (novel biology) from *first-in-class modality* (known-but-undrugged target, novel peptide approach) — both qualify; label which.
  - **Single vs multiple:** offer both — a single high-confidence target, or a **target pair** (complementary-exposure, anchored on one validated node) per the multi-target thesis. Pairs raise selectivity/first-in-class ceiling but need the pair-nominator's evidence rationale.
- **Deliverable:** the shortlist of first-in-class, peptide-tractable targets (single and/or pair), each labeled FIC-target vs FIC-modality.
- **Gate:** partner scientific sign-off that the biology is credible and worth wet-lab time (their domain expertise is the reality check here).

### STAGE 3 — Target structure, epitope & peptide design *(us)*
- **3a Structure/epitope:** obtain an experimental structure if one exists; else predict (AlphaFold/co-folding) and identify the **druggable epitope / PPI hotspot / pocket** (pocket detection + DrugCLIP-style triage). If neither exists, flag **joint structure determination** as an early partner deliverable (their cryo-EM/crystallography or a CRO).
- **3b Generate:** run the generator (PepGLAD-class) **conditioned on the epitope**; emit macrocycles with **non-canonical chemistry** (N-methyl / D-amino-acid / staples) where permeability or protease-stability demands it; enforce **hard ring-closure**.
- **3c Verify (multi-objective):** score every candidate on the **full panel** — binding affinity (docking → MM-GBSA → FEP on finalists), **membrane permeability** (ΔPSA3D predictor), synthetic accessibility, predicted safety/off-target, developability, with **uncertainty** and **measured-vs-predicted provenance** tags. QC gate rejects hard-threshold failures before expensive scoring; **Pareto/EHVI** selects a diverse, informative shortlist.
- **Deliverable — the PROPOSAL PACKAGE handed to the partner:**
  1. Target dossier (causal evidence + direction + first-in-class claim + null controls);
  2. **Designed peptide structure(s)** — 3D coordinates, sequence + chemistry, predicted binding mode against the epitope;
  3. Predicted property vector per candidate (affinity, permeability, SA, safety, uncertainty);
  4. **Recommended validation assays + explicit success criteria** (so "validated" is pre-defined, not argued after the fact);
  5. An orderable synthesis spec for the CRO.
- **Gate:** ≥1 candidate clears all in-silico QC thresholds with acceptable uncertainty; partner agrees the proposed assays are runnable in their lab.

### STAGE 4 — Target validation *(them)* — *"what they do for us," part 1*
- **Do:** confirm the target is real and causal **in their disease-relevant material**:
  - Expression/prevalence in **patient samples/cohorts** (confirm the target is present in the intended population/subtype);
  - **Genetic perturbation** — CRISPR KO / KD / (over)expression in disease-relevant primary cells or lines to confirm causality **and direction** predicted in Stage 1;
  - Establish the **phenotypic disease-relevant assay** the peptide will later be judged on.
- **Gate:** target confirmed causal + direction matches → proceed; if not, back to Stage 1 (re-nominate).

### STAGE 5 — Binding validation *(them + CRO)* — *part 2*
- **Do:** CRO synthesizes the panel → partner runs **SPR/BLI/ITC** affinity, **specificity/competition**, and (ideally) **structural confirmation of binding mode** (co-crystal / cryo-EM) — which both validates the design and gives the next design round a real structure.
- **Gate:** measured affinity + correct binding mode within target range → proceed; else results feed DPO (Stage 9).

### STAGE 6 — Functional validation *(them)* — *part 3*
- **Do:** cell-based + primary-sample functional assays with dose–response and on-target rescue:
  - **SYSUCC:** NPC organoids / **PDX**, primary tumor cells, immune-cell co-culture, reporter assays (e.g. EBV-entry blockade, NF-κB, migration/invasion), radiosensitisation readouts.
  - **Soochow:** **patient PBMC** assays, primary immune-cell functional readouts, cytokine/receptor-blockade reporters, the disease-phenotype assay from Stage 4.
- **Gate:** functional effect at acceptable potency with on-target evidence → proceed.

### STAGE 7 — In-vivo efficacy & PK/PD *(them)* — *part 4*
- **Do:** efficacy in disease models — **PDX / xenograft** (SYSUCC) or **lupus-prone / arthritis models** (Soochow, incl. their MRL/lpr capability) — plus PK/PD and preliminary tolerability.
- **Gate:** in-vivo efficacy + acceptable exposure → advance to translational.

### STAGE 8 — Translational / clinical *(them)* — *part 5*
- **Do:** IND-enabling tox, GMP peptide manufacture (CRO), regulatory package, and **first-in-human via their Phase-I / GCP trial unit** (SYSUCC's NMPA Anti-Tumor New-Drug center; Soochow's national drug-trial base).
- **Gate:** IND cleared → Phase-I.

### STAGE 9 — Closed loop *(us)*
- **Do:** every assay result (binding, function, in-vivo — successes *and* failures) is ingested and versioned → **DPO-retrains the generator** → the next design round is better-informed. The accumulating proprietary assay data is the **moat**.
- **Cadence:** loop turns at Stages 5–7; each turn tightens the target dossier and the design distribution.

---

## 2 · "What can they do for us?" — the partner's contribution, itemized

This is the crux of the user's question. Mapped to what each candidate uniquely provides:

| Contribution | Why we can't do it ourselves | SYSUCC (oncology) | Soochow (autoimmune) |
|---|---|---|---|
| **Patient samples & cohorts** to confirm target prevalence/relevance | We have no patients | World's largest NPC biobank; million-scale screening cohorts; proteogenomic subtypes | SLE/pSS/RA patient cohorts + PBMC access |
| **Genetic causality (KO/KD/CRISPR)** in disease cells | We predict direction; they prove it | NPC lines + organoids for perturbation | Primary immune cells / disease lines |
| **Binding + structural confirmation** | We predict binding mode; they measure it | SPR/BLI + crystallography/cryo-EM (State Key Lab) | SPR/ELISA + recombinant-protein toolbox (Jiangsu Inst. Clinical Immunology) |
| **Functional efficacy** in disease-relevant systems | Our verify layer is in-silico | **PDX / organoids**, primary tumor, immune co-culture | **Patient PBMC** functional assays, disease-phenotype readouts |
| **In-vivo efficacy + PK/PD** | No vivarium | Tumor xenograft/PDX models | **MRL/lpr lupus** + arthritis models (+ PersonGen platform) |
| **Clinical translation (Phase-I)** | Not a clinic | **NMPA Anti-Tumor New-Drug center + GCP Phase-I unit** (~50% drug-to-approval) | National drug-clinical-trial base; cell-therapy/GMP infrastructure |
| **Domain reality-check on target biology** | Confidence gate | World-leading EBV/NPC biology (Zeng/Bei labs) | Deep autoimmune-receptor immunology |

**Net:** they are the **entire wet + clinical half** of the loop — target confirmation, molecule validation, in-vivo proof, and the regulated path to a patient — none of which our computational engine can produce.

---

## 3 · Per-partner first-in-class opening

Concrete first FIC programs, chosen so the partner's *specific* validation capability is the enabling asset:

- **SYSUCC — first-in-class EBV/NPC target.** Run Stage 1 over EBV+ NPC genetics + their single-cell/spatial atlases to nominate an **undrugged, causal, peptide-tractable node** (candidate spaces: EBV host-dependency factors beyond the known entry receptors; TME immune-evasion PPIs from the atlas with causal follow-up; recurrent-NPC radioresistance nodes). Validate through their EBV-entry/organoid/PDX assays. *De-risking anchor that runs alongside:* the already-validated **R9AP/EphA2** entry receptors (Stage 4 is effectively pre-done — fastest dry→wet proof).
- **Soochow — first-in-class autoimmune target.** Run Stage 1 over lupus/pSS/RA genetics + their surface-receptor immunology to nominate an **undrugged, causal, extracellular-or-accessible immune PPI** with an inhibitory direction. Validate through their PBMC + MRL/lpr assays. *De-risking anchor:* the causally-validated **IL-23/IL-23R** program (head-to-head vs their own mAb).

*(The anchors give the ACT-style traction data; the FIC nominations are the differentiated, defensible assets. Run both — anchor proves the loop, FIC provides the upside.)*

---

## 4 · IP & data governance (for "we propose, they validate")

- **Composition-of-matter** on every generated peptide = **ours** (we designed it).
- **Novel-target use IP** (method-of-treating with a peptide against target X) — structure so the **target nomination + design origin is ours**; co-generated validation data can be jointly owned with a license-back, but the **generator-training rights on that data must be ours** (it is the moat).
- **Inventorship:** target-ID + design = our inventors; validation may earn co-inventorship on the *use* claim per contribution — define in the collaboration agreement up front.
- **HGRAC / cross-border:** mitigated via **our Chinese entity** — the entity holds the collaboration domestically, samples/patient data stay in-country, only de-identified target biology + assay results feed our generator. (See the engagement plan.)
- **Publication:** partner gets academic authorship on validation; we retain the platform/method as internal (state *what* we deliver externally, not the tool stack — per our external-disclosure discipline).

---

## 5 · Indicative timeline & cost (per FIC program)

| Stage | Owner | Time | Cost driver |
|---|---|---|---|
| 0–2 target ID + FIC filter | us | 3–6 wk | compute (spot) |
| 3 design + verify | us | 2–4 wk | compute (FEP/MM-GBSA on finalists) |
| CRO synthesis | CRO | 4–8 wk | **~$15–25k / IP-clean round** |
| 4–6 target+binding+function | them | 2–4 mo | their lab |
| 7 in-vivo | them | 3–6 mo | their vivarium |
| 8 translational/Phase-I | them | 12+ mo | GMP/tox/clinical |
| 9 loop | us | continuous | compute |

Scope **Phase-0 to one CRO round per program** so a no-go is cheap; the anchor program (validated target) can skip Stage 4 and reach a wet readout fastest.

---

## 6 · Honest risks & gates

- **De-novo first-in-class target-ID is genuinely hard and high-variance.** Genetic support is the credentialing bar; a nomination without it is hypothesis-grade. The partner's Stage-4 causality test is the real gate — expect attrition here, and run the validated **anchor** in parallel so the collaboration always has a live wet program.
- **Direction-of-effect risk:** peptides are strong *antagonists/blockers*; **agonist/restore** targets are harder — deprioritize loss-of-function-disease targets for the lead.
- **Intracellular targets** carry the permeability tax — real, and exactly what our non-canonical/stapled chemistry + permeability objective exist to address; stress-test permeability early in cell-based assays.
- **No-structure targets:** if neither experimental nor confident predicted structure exists for the epitope, design quality drops — make joint structure determination an explicit early deliverable.
- **Don't overclaim novelty:** run the ChEMBL/pipeline first-in-class check rigorously and consult prior competitive surveys before asserting "first-in-class" externally.

---

*Companion docs: `20260930_HOSPITAL_SURVEY_SYSUCC_*`, `20260930_HOSPITAL_SURVEY_SOOCHOW_*`, `20260930_HOSPITAL_PARTNERSHIP_ENGAGEMENT_PLAN.md`, `20260817_TARGET_IDENTIFICATION_SURVEY.md`, `20260925_PEPTIDE_EXECUTION_PLAN.md`. Comprehensive faculty + publication rosters for each partner are being compiled separately and will attach to the survey briefs.*

---

## Appendix A — Stage-5 CRO Sub-Protocol + Pre-Registered Success Criteria (PD-L1 anchor round)

**Context.** This is the detailed transaction layer for **Stage 5 (binding validation)** on the **PD-L1
anchor / loop-proof track** — the fastest dry→wet readout (Stage 4 is skippable: PD-L1 is a validated,
structurally-characterized target). For the first-in-class *lead*, Stage 5 is run by the **hospital partner**
with the richer structure+function validation (co-crystal, organoid/PBMC, in-vivo); here a **CRO stands in**
to prove the loop quickly and cheaply. Transaction companions: `20261001_GENSCRIPT_RFQ_PDL1_ROUND1.md`
(orderable RFQ with verified GenScript deliverables) + `20261001_CRO_DBTL_LOOP_DATA_SPEC.md` (data-return
format) + `20260930_PDL1_DEVELOPABILITY_ENGINEERABILITY.md` (the dry screens, calibrated on cyclosporine).

### A.1 CRO deliverables (order + what comes back)
- **Build (synthesis):** head-to-tail cyclic, ≥95% RP-HPLC, 5 mg, **acetate** (TFA→acetate exchange). Standard
  return: COA + HPLC chromatogram + MS spectrum. Add-ons to request: **net peptide content (AAA/nitrogen)**,
  counter-ion quantification, **solubility test**, moisture.
- **Test (binding):** SPR/BLI (Biacore 8K+) vs recombinant human PD-L1 — **affinity ranking → kinetics**;
  return ka, kd, **KD**, Rmax, Chi², **raw sensorgrams** for **ALL peptides incl. non-binders**.
- **Return format:** one structured table + raw traces, **every peptide, every step, failures + non-binders
  included, no pre-filter** (negatives + KD gradient are the training signal).

### A.2 Pre-registered success criteria — define "validated" BEFORE the data
*(Pre-registration is the point: "validated" is not argued post-hoc. These are the round-1 anchor bars;
tighten per program. Honest framing: PD-L1 is a hard flat interface, so a µM first-round binder is a real
"it binds" proof — the native macrocyclic peptide-71 at ~7 nM is the aspiration, not the round-1 bar.)*

| Gate | Metric | **Round-1 success (anchor/loop-proof)** | Stretch |
|---|---|---|---|
| **Build** (synthesis) | purity, mass, ring closure | **≥70%** of ordered peptides delivered ≥95% purity, MS within ±1 Da, cyclization confirmed | ≥90% |
| **Test — binding** (Stage 5) | SPR KD, specific + dose-dependent (1:1 fit, acceptable Chi²) | **≥1 peptide with specific KD ≤ 10 µM** | ≥1 at **KD ≤ 1 µM**; multiple binders |
| **Test — function** (Stage 6, optional) | PD-1/PD-L1 blockade | ≥50% blockade at ≤10 µM for ≥1 binder | IC50 ≤ 1 µM |
| **Learn** (Stage 9) | data completeness → retrain | **100% of peptide outcomes (incl. failures/non-binders) ingested + generator retrained + predicted-vs-measured calibration computed** | measurable ranking/DockQ lift in round-2 design |

### A.3 Decision rules per gate (what each outcome triggers)
- **Build fails (most don't synthesize/cyclize):** do **not** just re-order — the per-peptide **failure modes**
  feed the cyclization-feasibility + synthesizability models; re-design with a turn-inducer prior, then re-order.
- **Binding: ≥1 binder** → advance it to the function assay; use as a **positive** in the DPO retrain.
- **Binding: 0 binders** → still a **successful loop** at the Learn gate: ingest the measured **negatives**,
  diagnose the **predicted-vs-measured gap** (was iptm/ΔG mis-calibrated?), retrain, re-design round-2.
- **Always → Learn gate:** ingest everything. The **binding gate is drug-progress; the Learn gate is
  platform-progress.** Round 1 is declared a success on the **Learn gate** (data→retrain) even with zero
  binders — the proprietary assay data is the moat regardless of this round's hit rate.

### A.4 Honest note on this appendix vs the body
Stages 1–4 and 6–8 of the body protocol (hospital partner: target causality, structure, function, in-vivo,
clinic) are **not replaced** by this CRO sub-protocol — the CRO only covers Build + a binding readout for the
**anchor** loop-proof. The FIC lead still runs the full partner protocol.
