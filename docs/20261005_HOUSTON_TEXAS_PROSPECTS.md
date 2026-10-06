# Houston & Texas Prospects — Prioritized BD / Partnership List

**Date:** 2026-10-05
**Author:** Business / BD team
**Purpose:** A prioritized, actionable list of potential BioMate users and partners to approach in Houston and across Texas, organized by the segment framework (hospital / academic-core, small-biotech & individual-researcher = cloud, pharma / CRO), with warm ties seeded at the top.

**Reuses and extends (read, cited, not re-derived):**
`docs/20260727_TEXAS_TIER1_BD_PROSPECTS.md` (TMC biotech/CRO track) ·
`docs/20260701_FACULTY_SURVEY_AND_COLLABORATION_STRATEGY.md` (UTHealth SBMI / BCM faculty survey) ·
`docs/20261005_SEGMENT_DEMAND_DIFFERENTIATION.md` (hospital-vs-pharma demand) ·
`docs/20261005_MOAT_AND_SEGMENT_MARKETING_STRATEGY.md` (3-segment GTM + moat) ·
`business/BioMate_ZhandongLiu_Collaboration_Proposal.md` (drafted pilot proposal).

**Honesty contract (strict, applies throughout):**
- **Warm** = a real, documented relationship or a defensible personal/affiliation tie (founder background, drafted proposal, verified named contact already in our records). **Cold** = a real, publicly-citable institution/lab/PI with no existing relationship — outreach would be a first touch.
- No specific person, email, or relationship is invented. Where a named contact is needed but unknown, the entry says **"identify contact"** rather than fabricate one.
- External facts carry a source with access date (web accessed 2026-10-05). Repo-sourced facts carry a file path.
- BioMate capability claims follow the Evidenced / Partial / Aspirational labels established in `docs/20261005_SEGMENT_DEMAND_DIFFERENTIATION.md`; this document does not upgrade them.
- MD Anderson / Jim Allison is treated as **cold / aspirational** — no direct line exists (MEMORY `user_uthealth_faculty_background`).

---

## 0. Segment framework (recap, from the moat/segment strategy docs)

Three buyer motions, each with a different scarcity, gate, and first-touch — do not conflate them (`docs/20261005_MOAT_AND_SEGMENT_MARKETING_STRATEGY.md` §2; `docs/20261005_SEGMENT_DEMAND_DIFFERENTIATION.md` §C):

| Segment | Scarcity it feels | What BioMate leads with | Economics |
|---|---|---|---|
| **Hospital / academic core** (MOAT; high-touch, reference-site led) | bioinformatics skill + compute; publication credibility; (China) data residency | no-code chat routing over the validated catalog; instrument connectors; on-prem; QC + methods output | on-prem license + support contract (recurring) |
| **Small biotech / individual researcher** (FUNNEL; product-led, low-touch = cloud) | can't-DIY analysis, no bioinformatics hire, no AWS setup | "reproducible pipelines in minutes, no bioinformatics team" managed compute | usage / subscription (thin, deliberately) |
| **Pharma / CRO** (MOAT; enterprise BD, long cycle) | probability-of-success / speed; IP control; compliance | open execution + QC-governance layer for *your own* data (vs closed silos); ADMET/PBPK/tox screening | deployment + embedded recurring + asset/milestone |
| **Accelerator / channel** (AMPLIFIER) | n/a — one relationship = a pipeline of the above | preferred AI/bioinformatics resource for resident startups | partnership / referral |

**Honest capability guardrails to respect in every pitch** (from the demand doc §A.3/§B.3): single-cell / spatial / proteomics / ChIP have no committed real E2E evidence; there is **no SOC 2 / HIPAA BAA / 21 CFR Part 11 / GxP certification** in repo evidence; no MGI/BGI connector; IND / CRO UX is commented out (crashes); predictions are estimates, not wet-lab truth. Lead lean biotech / academic-core / boutique-CRO, **not** top-10 pharma.

---

## WARM TIES — seed these first (founder is a former UTHealth SBMI faculty member)

These are the warmest Houston entry points and lead the quarter. All three originate in the founder's own background and are already documented in our files.

### W1. Dr. Zhandong Liu — Baylor College of Medicine / Texas Children's  *(WARM — warmest single tie)*
- **Segment:** hospital / academic-core (neuro + computational genomics).
- **Why they fit:** rare-neurological-disease multi-modal workup (WGS + RNA-seq + splicing). His full pipeline is **already wired into BioMate as chain id 1** (`rare_disease_multimodal_workup`: sarek → VEP → rnaseq → DROP/OUTRIDER/FRASER → case-report aggregation), matching his RareCollab paper verbatim (`docs/20260701_...md` §Faculty 3; MEMORY `user_uthealth_faculty_background`). A full pilot proposal is **already drafted** (`business/BioMate_ZhandongLiu_Collaboration_Proposal.md`).
- **BioMate capability:** nf-core/sarek + nf-core/rnaseq + DROP on AWS Batch with clinical-grade QC gates (Evidenced infra; rare-disease E2E Partial).
- **Specific ask:** the 60-minute session already scoped in the proposal — walk one active analysis, confirm the customization list (cutandrun spike-in, raredisease orchestration, scAuto adapter), agree 2–3 baseline comparison analyses for an 8-week pilot.
- **Priority: P1.** This is the single most-ready conversation in the entire list.

### W2. UTHealth Houston SBMI faculty group — Zhao / Zhi / Zheng  *(WARM by founder affiliation; outreach not yet confirmed)*
The founder's former department. A joint 3-PI UTHealth collaboration is already designed (`docs/20260701_...md` §Collaboration Structure). Honest status: these are **affiliation-warm** — defensible personal entry via the founder — but we have no record that outreach has actually occurred, so treat as warm-intro-pending, not an active relationship.

- **W2a. Dr. Zhongming Zhao** — UTHealth SBMI, Bioinformatics & Systems Medicine Lab (bsml320); h-index 90 (`docs/20260701_...md` §Faculty 1). *Segment:* academic-core. *Fit:* single-cell + immune-oncology; **scGWAS already running end-to-end in BioMate** (chain id 72, smoke-tested on Crohn's × Tregs). *Ask:* 30-min call opening on the live scGWAS demo, then pitch the "Autoimmune Virtual Cell" co-development (Nature Methods / Genome Biology target). *Priority: P1* — strongest opening demo of the three.
- **W2b. Dr. Degui Zhi** — UTHealth SBMI Department Chair (`docs/20260701_...md` §Faculty 2). *Segment:* academic-core. *Fit:* population-scale GWAS (TorchGWAS, chain id 69) + EHR foundation models (Med-BERT) for target prioritization + clinical-trial-design layers. *Ask:* reference the Zhao conversation (same campus); pitch GWAS + Med-BERT layer; co-develop a Nature Genetics / Bioinformatics methods paper. *Priority: P2.*
- **W2c. Dr. W. Jim Zheng** — UTHealth SBMI, Professor (`docs/20260701_...md` §Faculty 4; ORCID 0000-0001-7411-6047). *Segment:* academic-core. *Fit:* biomedical-literature LLM knowledge extraction (2024 JAMA paper) → GEO/PubMed methods mining as workflow-orchestration training data. *Ask:* invite as third PI scoped to the LLM-training-data workstream; lower-touch, well-defined deliverable. *Priority: P2.*

**Sequencing (from the faculty doc):** Zhao → Zhi → Zheng, then a single 60-min joint UTHealth kickoff once all three are interested. A single joint institutional agreement is administratively simpler than three.

---

## 1. Houston / Texas Medical Center (TMC)

### 1A. Hospital / academic-core institutions

| # | Institution / program | Segment | Why they fit (real BioMate capability) | Specific ask | Warm/Cold | Priority |
|---|---|---|---|---|---|---|
| 1 | **Baylor College of Medicine — Human Genome Sequencing Center (HGSC)**; Dir. **Richard Gibbs** ([hgsc.bcm.edu, accessed 2026-10-05](https://www.hgsc.bcm.edu/)) | academic-core | 200+ staff, >36,000 sq ft, high-throughput sequencing + downstream bioinformatics — the exact "instrument → reproducible pipeline" wedge; already a DNAnexus power-user (compliance-aware buyer) | Via the Zhandong-Liu BCM relationship, request a warm intro to a core-facility director; propose a reproducibility / methods-audit pilot on an existing cohort | Cold (warm-adjacent via W1 at BCM) | P2 |
| 2 | **Houston Methodist Research Institute — Center for Bioinformatics & Computational Biology + Biostatistics & Bioinformatics (BBI) Core** ([houstonmethodist.org, accessed 2026-10-05](https://www.houstonmethodist.org/academic-institute/research/cores/bioinformatics-core/); 6670 Bertner Ave) | academic-core | Core serves many wet-lab PIs with no bioinformatician — the fan-out channel pattern; genomics/epigenomics/RNA focus maps to transcriptomics (1,695 wf) + epigenomics (265) | Identify contact (center/core director not individually confirmed here); propose a lunch-and-learn + a lighthouse pilot through the core | Cold | P2 |
| 3 | **MD Anderson Cancer Center** — cell therapy / immuno-oncology / immunopeptidomics (founding ground of Mongoose & ImmunoGenesis, `docs/20260727_...md` §Tier-3) | academic-core | Antigen-resolution + immuno-oncology multi-omics is BioMate's positioning (immunopeptidome / TCR-BCR / HLA) | Approach bottom-up through a specific PI lab, not the institution; no direct line — treat as aspirational | **Cold / aspirational** (explicitly no Allison line, MEMORY) | P3 |
| 4 | **UTHealth Houston (beyond SBMI)** — clinical-research arms | hospital | Research-arm entry (not clinical production — no CLIA/FHIR live, demand doc §A.3) | Leverage the SBMI warm group (W2) to fan into adjacent clinical-research labs | Warm-adjacent via W2 | P2 |
| 5 | **Texas Children's Hospital** (with W1/Liu) | hospital | Pediatric rare-disease genomics — same chain-id-1 pipeline as Liu | Fold into the Liu pilot scope | Warm-adjacent via W1 | P2 |
| 6 | **Rice University — CS/Bioengineering; Prof. Todd Treangen** (microbial genomics / metagenomics / biothreat; [profiles.rice.edu, accessed 2026-10-05](https://profiles.rice.edu/faculty/todd-treangen)); Ken Kennedy Institute bioinformatics | academic-core | Metagenomics (Kraken2/MetaSPAdes) + genomics catalog; a reproducible-pipeline + teaching user; TMC-adjacent | Cold intro to Treangen lab; propose a metagenomics reproducibility pilot / student platform access | Cold | P2 |
| 7 | **Memorial Hermann** (TMC clinical system) | hospital | Clinical-research arm; lowest research-compute fit of the TMC hospitals | Deprioritize until a reference site exists; monitor | Cold | P3 |

### 1B. Accelerator / channel — the scalable play

| # | Program | Segment | Why it fits | Specific ask | Warm/Cold | Priority |
|---|---|---|---|---|---|---|
| 8 | **TMC Innovation Factory** + **Innovation Labs @ TMC** (the 34,000 sq ft space TMC takes over as **J&J JLABS vacates in January 2026** — [TMC press release](https://www.tmc.edu/press-releases/tmc-broadens-support-of-houston-start-ups-with-the-launch-of-innovation-labs-tmc/); [InnovationMap, accessed 2026-10-05](https://houston.innovationmap.com/innovation-labs-tmc-2673755580.html)) | accelerator / channel | One relationship = a pipeline of lean "can't-DIY" biotechs — BioMate's ideal cloud→on-prem funnel. 450+ ventures hosted since 2015 | Get BioMate listed as a preferred bioinformatics/AI resource for residents; run office-hours / lunch-and-learn. Reach via the TMC Innovation partnerships team | Cold (high leverage) | **P1** |
| 9 | **TMCi Accelerator for Cancer Therapeutics (ACT)** + **TMC HealthTech Accelerator** ([tmc.edu/innovation, accessed 2026-10-05](https://www.tmc.edu/innovation/therapeutic-labs-tmc/accelerator-cancer/)) | accelerator / channel | ACT cohorts are oncology-therapeutics startups needing biomarker/stratification analysis — direct capability match | Apply as a resource partner / mentor; offer cohort workshops | Cold | P2 |
| 10 | **TMC BioBridge** (international market-entry program — partners with Australia, UK, Denmark, Ireland, Netherlands, Japan, Korea; **no China track as of 2026-10-05** — [TMC BioBridge-Korea release](https://www.tmc.edu/press-releases/texas-medical-center-launches-biobridge-with-republic-of-korea-to-expand-therapeutic-and-medical-technology-development-in-us/), accessed 2026-10-05) | accelerator / channel | Pipeline of international startups entering the US — potential channel for BioMate as a landing-pad analytics partner | Explore partner-resource listing; note it does **not** currently bridge China | Cold | P3 |

### 1C. Houston biotech / startups (small-biotech = cloud; lean = real need)

Carried forward verbatim from `docs/20260727_TEXAS_TIER1_BD_PROSPECTS.md` (contacts verified there; ✓ = public record, ✓fmt = inferred from confirmed company format). **Correction vs that doc:** entries that reference "JLABS @ TMC" as an address should note JLABS vacates Jan 2026 → the space becomes Innovation Labs @ TMC; the tenant companies remain Houston-based regardless.

| # | Company | Segment | Why they fit (capability) | Specific ask | Warm/Cold | Priority |
|---|---|---|---|---|---|---|
| 11 | **Mongoose Bio** (Houston; MD Anderson spinout 2023, TCR-T, CPRIT-funded) — `info@mongoosebio.com` ✓ | biotech (cloud→on-prem) | Immunopeptidome + TCR discovery = BioMate's antigen-resolution stack (AIRR TCR/BCR + HLA + epitope + LC-MS). The "capability bullseye" | Pilot: pressure-test target/epitope selection + TCR–HLA–peptide resolution; "no bioinformatics hire needed." In-person Houston visit | Cold (verified entry point) | **P1** |
| 12 | **ImmunoGenesis** (Houston; Series C IO; founder Michael Curran/MDACC; already buys multi-omics from BostonGene) — format `first.last@immunogenesis.com` ✓ (`bill.tanner@`, `james.barlow@` ✓fmt) | biotech | Immune-excluded ("cold" tumor) responder/resistance stratification for IMGS-001 — validated need + budget | Demo: responder/resistance stratification, "closer, faster, reproducible" vs outsourced multi-omics | Cold (verified contacts) | P1 |
| 13 | **Diakonos Oncology** (Houston; DOC1021 DC vaccine, FDA Fast Track GBM) — contact form at diakonosoncology.com/contact ✓; PR route David Schull/Russo | biotech | Pre-treatment responder signature (scRNA/CyTOF) to predict GBM responders prospectively | Pilot: prospective responder prediction during enrollment, framed as a predictive biomarker | Cold | P2 |
| 14 | **7 Hills Pharma** (Houston; integrin-activator IO adjuvant, CPRIT) — contact form 7hillspharma.com | biotech | Biomarker/responder profiling for immunotherapy combinations | Intro via contact form (CEO Upendra K. Marathi; personal address not public) | Cold | P2 |
| 15 | **ImmunoMet Therapeutics** (Houston; OXPHOS/metabolism oncology) | biotech | Metabolic + immune multi-omics stratification | Verify current status/leadership before outreach (**identify contact**) | Cold (verify first) | P3 |

---

## 2. Texas beyond Houston

### 2A. Academic / hospital institutions

| # | Institution / program | Segment | Why they fit (real capability) | Specific ask | Warm/Cold | Priority |
|---|---|---|---|---|---|---|
| 16 | **UT Southwestern (Dallas) — Lyda Hill Department of Bioinformatics**; inaugural Chair **Gaudenz Danuser** (17 faculty, 120 scientists; [utsouthwestern.edu/departments/bioinformatics, accessed 2026-10-05](https://www.utsouthwestern.edu/departments/bioinformatics/); [Southwestern Medical Foundation, accessed 2026-10-05](https://swmedical.org/lyda-hill-donates-25-million-to-establish-department-of-bioinformatics/)) | academic-core | A flagship computational department — co-development / methods-paper partner and a fan-out channel to its 120 scientists; imaging + multi-omics integration | Cold intro to the department; propose a reproducibility / methods collaboration; also note **Peter O'Donnell Jr. Brain Institute** for neuro multi-omics (ties to W1 profile) | Cold | P2 |
| 17 | **UT Austin — Oden Institute for Computational Engineering & Sciences** (123 faculty across 23 departments; [Wikipedia/Oden, accessed 2026-10-05](https://en.wikipedia.org/wiki/Oden_Institute_for_Computational_Engineering_and_Sciences)) + Dell Medical / biosciences | academic-core | Computational-science hub; growing Austin biotech + omics (`docs/20260727_...md` §Tier-3). *Note:* Vijay Chidambaram (CS) is systems/storage, **not** comp-bio — do not mis-target him | Identify the comp-bio/biosciences PI (**identify contact** — Oden is CSE-broad, not bio-specific); propose a lighthouse academic pilot | Cold | P3 |
| 18 | **UTMB Galveston** — clinical/translational + infectious disease (Galveston National Lab) | hospital / academic-core | NGS + infectious-disease genomics / metagenomics; reproducible-pipeline wedge | **Identify contact** (core/PI not confirmed here); cold intro via a genomics core | Cold | P3 |
| 19 | **UT Health San Antonio (UTHSA)** + **UT San Antonio (UTSA)** | hospital / academic-core | South Texas medical + CS/AI; standard omics-core fit | **Identify contact**; cold | Cold | P3 |
| 20 | **Texas A&M** — institute for biosciences / AgriLife genomics; biomedical informatics faculty ([cstrinstitute.tamhsc.edu, accessed 2026-10-05](https://cstrinstitute.tamhsc.edu/services/biomedical-informatics/biomedical-informatics-faculty-listings/)) | academic-core | Large genomics + ag-bio footprint; reproducible pipelines; student platform access | **Identify contact**; cold intro to a genomics/informatics core | Cold | P3 |

### 2B. Research institutes / CRO-adjacent (San Antonio)

| # | Institution | Segment | Why they fit | Specific ask | Warm/Cold | Priority |
|---|---|---|---|---|---|---|
| 21 | **Texas Biomedical Research Institute (San Antonio)** — 28 PIs, BSL-4, HIV/SIV, TB, filovirus, vaccine immunogenicity ([en.wikipedia.org/Texas_Biomedical_Research_Institute, accessed 2026-10-05](https://en.wikipedia.org/wiki/Texas_Biomedical_Research_Institute)) | academic-core / research-institute | Infectious-disease immunology + vaccine work → immune multi-omics, TCR/BCR, deconvolution; a reproducibility + on-prem (biosecure) fit | Cold intro; propose an immune-profiling / reproducible-pipeline pilot; on-prem angle fits BSL-4 data sensitivity | Cold | P3 |
| 22 | **Southwest Research Institute (San Antonio)** — large independent applied-R&D contract org (bioengineering / chem among divisions) | CRO-adjacent / research-institute | Contract-research backbone opportunity (execution engine behind their services); fits the boutique-CRO partner thesis | **Identify contact** (bioscience division); explore white-label / execution-backbone partnership | Cold | P3 |

---

## 3. Texas biotech / CROs / academic core facilities (on-prem + reproducibility wedge)

| # | Prospect | Segment | Why they fit (real capability) | Specific ask | Warm/Cold | Priority |
|---|---|---|---|---|---|---|
| 23 | **Houston Omics Collaborative (HOC) @ University of Houston** — Dir. **Chandra Mohan, MD PhD** (`cmohan@central.uh.edu` ✓, 713-743-3709; `docs/20260727_...md` §4) | academic-core / channel | UH omics service facility (targeted proteomics, autoantigen microarrays, genomics). Mohan = prominent lupus/autoimmunity biomarker KOL; maps onto BioMate's isotype/autoimmune-stratification thesis. Three plays: wet+dry bundle, KOL/validation co-author, channel to every lab HOC serves | Warm-ish intro (verified contact): propose (a) joint wet+dry offering, (b) co-authored reproducibility/autoimmune-stratification manuscript, (c) channel listing. **Caveat (MEMORY `project_mohan_data_validation_policy`):** his cohort data is HELD-OUT validation only — never training | Warm-cool (verified named contact; no active relationship) | P1 |
| 24 | **Altogen Labs (Austin)** — preclinical CRO (PK/PD, xenografts, ELISA, stable lines, tox; `docs/20260727_...md` §8) | CRO | Wet+dry partnership: they run in-vivo/assays, BioMate adds the omics analysis + reporting layer; or their client base as a channel | Cold intro via altogenlabs.com; propose an execution-backbone / white-label analytics partnership (position as "augment throughput + reproducibility," not "replace") | Cold | P2 |
| 25 | **Boutique / specialized Texas CROs + academic core facilities** (genomics / proteomics / single-cell cores at the institutions above) | CRO / academic-core (channel) | Per `docs/20261005_MOAT_AND_SEGMENT_MARKETING_STRATEGY.md` §2D: boutique CROs + internal academic cores lack bioinformatics teams, face margin pressure, need reproducible/auditable output → BioMate as their on-prem execution backbone (recurring + brings client volume) | Map and **identify contacts** at each core (BCM GARP/genomics, Houston Methodist BBI, UH HOC, UTSW, A&M); pitch execution-backbone partnership | Cold (channel-building) | P2 |

**CRO caveat (honest):** large full-service CROs (IQVIA, ICON, Labcorp, WuXi) have their own platforms/teams → build-vs-buy, long cycle, and a substitution tension (a CRO may resist a tool that commoditizes its dry-lab margin). Pursue boutique/specialized + academic cores, not the majors, as the primary CRO wedge.

---

## 4. China-bridge note (bonus, where real)

- TMC's **BioBridge** international program currently bridges Australia, UK, Denmark, Ireland, Netherlands, Japan, and Korea — **there is no China track as of 2026-10-05** ([TMC BioBridge-Korea release, accessed 2026-10-05](https://www.tmc.edu/press-releases/texas-medical-center-launches-biobridge-with-republic-of-korea-to-expand-therapeutic-and-medical-technology-development-in-us/)). Do not assume a TMC-China on-ramp.
- TMC and its member institutions (MD Anderson, Baylor, UTHealth) employ **many China-connected PIs** — this is a real, widely-known feature of the ecosystem and aligns with BioMate's China hospital/academic strategy (`docs/20261005_SEGMENT_DEMAND_DIFFERENTIATION.md` §A) — but **no specific named China-bridge PI is asserted here** because none is verifiable from our records without fabrication. Treat "China-connected faculty at TMC" as a true ecosystem feature to exploit via the warm SBMI/BCM ties (W1/W2), not as a list of named contacts. (**Identify contacts** once a warm tie is live.)

---

## 5. First 10 to contact this quarter (ranked — warm first)

| Rank | Prospect | Segment | Warm/Cold | Concrete first action |
|---|---|---|---|---|
| 1 | **Dr. Zhandong Liu (BCM / Texas Children's)** | hospital/academic-core | **Warm** | Send the already-drafted 60-min pilot proposal (`business/BioMate_ZhandongLiu_Collaboration_Proposal.md`); schedule the walk-through of one active analysis + confirm the customization list |
| 2 | **Dr. Zhongming Zhao (UTHealth SBMI)** | academic-core | **Warm (affiliation)** | 30-min call opening on the live scGWAS chain (Crohn's × Tregs); pitch the Autoimmune Virtual Cell co-paper |
| 3 | **Chandra Mohan / HOC @ University of Houston** | academic-core/channel | **Warm-cool (verified contact)** | Email `cmohan@central.uh.edu`: propose wet+dry bundle + co-authored reproducibility manuscript (respect held-out-data rule) |
| 4 | **TMC Innovation Factory / Innovation Labs @ TMC** | accelerator/channel | Cold (high leverage) | Contact the TMC Innovation partnerships team; request listing as a preferred bioinformatics/AI resource + schedule a resident office-hours / lunch-and-learn |
| 5 | **Mongoose Bio (Houston)** | biotech (cloud) | Cold (verified entry) | Email `info@mongoosebio.com` proposing a target/epitope + TCR–HLA–peptide resolution pilot; request an in-person Houston meeting |
| 6 | **Dr. Degui Zhi (UTHealth SBMI Chair)** | academic-core | **Warm (affiliation)** | After Zhao, email referencing that conversation; pitch TorchGWAS + Med-BERT target-prioritization layer |
| 7 | **ImmunoGenesis (Houston)** | biotech | Cold (verified contacts) | Email `james.barlow@` / `bill.tanner@immunogenesis.com`: demo IMGS-001 responder/resistance stratification |
| 8 | **Dr. W. Jim Zheng (UTHealth SBMI)** | academic-core | **Warm (affiliation)** | Email scoping the GEO/PubMed literature-mining workstream as the 3rd PI of the joint UTHealth proposal |
| 9 | **UT Southwestern — Lyda Hill Dept. of Bioinformatics** | academic-core | Cold | Cold intro to the department (Chair Danuser's group); propose a reproducibility/methods collaboration + student platform access |
| 10 | **Diakonos Oncology (Houston)** | biotech | Cold | Submit the partnership contact form (or route via Russo Partners PR) proposing prospective DOC1021 responder prediction |

**Day-trip efficiency note (from `docs/20260727_...md`):** ranks 3, 5, 7, 10 are all Houston and convert far better in person — batch them into a single Houston day (HOC/UH + Mongoose + ImmunoGenesis + Diakonos), and anchor it around the W1/Liu BCM meeting.

---

## 6. What could not be verified (honesty log)

- **Named individuals withheld where unknown:** Houston Methodist CBCB/BBI director, Rice Ken Kennedy bio-PI beyond Treangen, UT Austin Oden comp-bio PI, UTMB/UTSA/A&M core directors, and Southwest Research Institute bioscience lead are all marked **"identify contact"** — no name is asserted without a citation.
- **W2 (SBMI trio) relationship status:** classed as *affiliation-warm* via the founder's former-faculty tie (MEMORY `user_uthealth_faculty_background`); our records contain the faculty survey and a designed collaboration but **no confirmation that outreach has actually been initiated**. Do not represent these as active relationships.
- **MD Anderson:** no direct line; explicitly cold/aspirational (MEMORY). Any MDACC path is bottom-up via a specific PI lab.
- **TMC BioBridge China:** confirmed **absent** as of the cited release — do not pitch a China on-ramp through BioBridge.
- **JLABS @ TMC:** the `20260727` doc's "JLABS @ TMC" addresses are being superseded — J&J JLABS vacates Jan 2026; the space becomes TMC-managed **Innovation Labs @ TMC** ([TMC/InnovationMap, accessed 2026-10-05](https://houston.innovationmap.com/innovation-labs-tmc-2673755580.html)). Tenant companies (Mongoose, ImmunoGenesis) remain Houston-based.
- **Company contact emails** (Mongoose, ImmunoGenesis, HOC) are carried from `docs/20260727_...md` with its ✓/✓fmt provenance; re-verify format before a send. Diakonos / 7 Hills / ImmunoMet have **no verified personal address** — use the contact form or PR route; ImmunoMet status should be re-checked before outreach.
- **BioMate capability depth caveats** (single-cell/spatial/proteomics E2E unproven; no SOC 2 / Part 11 / GxP; no MGI/BGI connector; IND/CRO UX offline) apply to every pitch above and must not be over-promised (`docs/20261005_SEGMENT_DEMAND_DIFFERENTIATION.md` §A.3/§B.3).
