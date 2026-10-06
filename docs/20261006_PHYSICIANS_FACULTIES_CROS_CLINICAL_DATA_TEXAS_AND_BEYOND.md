# Physicians, Faculties & CROs with Clinical Data — Texas and Beyond

**Date:** 2026-10-06 · **Purpose:** A single consolidated map of clinical/translational physicians,
academic faculty, wet-lab cores, and CROs / clinical-genomics labs — in Texas and nationally — relevant
to BioMate as (a) clinical-validation anchors and collaborators, and (b) BD / partnership targets.
Consolidates sources previously split across the Drive *accelerator* folder and the repository.

**Honesty contract (strict, applies throughout):**
- **Warm** = a documented relationship or a defensible personal/affiliation tie (founder background, drafted
  proposal, verified named contact already in our records). **Cold** = a real, publicly-citable
  institution/lab/PI with no existing relationship (first touch).
- **No person, email, or relationship is invented.** Where a contact is needed but unknown, the entry says
  **"identify contact."** External facts carry a source; repo facts carry a path.
- MD Anderson / Jim Allison is **cold / aspirational** — no direct line exists.
- BioMate capability claims follow Evidenced / Partial / Aspirational labels; this document does not upgrade
  them. Capability caveats (single-cell/spatial/proteomics E2E unproven; **no SOC 2 / HIPAA BAA / 21 CFR
  Part 11 / GxP certification**; no MGI/BGI connector; IND/CRO UX offline) apply to every pitch below.

**Sources consolidated (read, cited, not re-derived):**
- Drive · *accelerator/TMC_ACT/* `Local_Collaborators` (TMC/Texas collaborator map — ACT/HPV16+ HNSCC)
- Drive · *accelerator/TMC_ACT/* `Clinical_Anchor_Backup_Plan` (verified HNSCC/IO faculty + outreach)
- Drive · `clinical_cro_targets.json` (national CROs & clinical-genomics labs, created 2026-02-25)
- Drive · `texas_targets.json` (Texas long-list, 146 entries, created ~2026-02; **per-contact details must
  be read from the source file — its contact↔institution mapping was not machine-verified here**)
- Repo · `docs/20261005_HOUSTON_TEXAS_PROSPECTS.md` (prioritized BD list, honesty-contracted)
- Repo · `docs/20260727_TEXAS_TIER1_BD_PROSPECTS.md`, `docs/20260701_FACULTY_SURVEY_AND_COLLABORATION_STRATEGY.md`
- Web · ClinicalTrials.gov registry API (HPV16 therapeutic-vaccine + checkpoint trials; accessed 2026-10-06) — §B

---

## A. Clinical & translational physicians / faculty — TEXAS

### A1. Warm ties (founder affiliation — lead the quarter)
The founder is a former **UTHealth Houston SBMI** faculty member; the warmest entry is the SBMI group.
*Status: affiliation-warm — defensible personal entry, but no record that outreach has been initiated.*
- **Dr. Zhongming Zhao** — UTHealth SBMI, Bioinformatics & Systems Medicine Lab; single-cell + immuno-oncology;
  also chairs the **Center for Precision Health / UTHealth Cancer Genomics Center** (CPRIT-funded, ~$2M + the
  BIG-TCR training program). *Note (from `Local_Collaborators`):* the Cancer Genomics Center is a
  **fee-for-service core** — its data belongs to the commissioning investigators and goes to public repos on
  publication; his value is a **custom-data engine + a 164-investigator/18-institution network + CPRIT
  credibility**, not proprietary data. *Priority: P1.*
- **Dr. Degui Zhi** — UTHealth SBMI Department Chair; population-scale GWAS + EHR foundation models
  (Med-BERT). *Priority: P2.*
- **Dr. W. Jim Zheng** — UTHealth SBMI Professor; biomedical-literature LLM knowledge extraction. *Priority: P2.*
- *Sequencing:* Zhao → Zhi → Zheng → one joint UTHealth kickoff.

### A2. Immuno-oncology / HPV16+ HNSCC clinical anchors (ACT flagship)
Verified faculty for the TMC ACT application (CPRIT-funded; Oct 31 deadline). Approach ≥2 in parallel as an
"HPV16 immunotherapy advisory group," not a single-co-PI dependency.
- **Dr. Renata Ferrarotto** — MD Anderson, Head & Neck Medical Oncology. Led the randomized
  peltopepimut-S (PDS0101)+cemiplimab vs cemiplimab trial in recurrent/metastatic **HPV16+ HNSCC** (JITC 2025).
  *Role:* clinical co-PI / validator / SAB anchor. (⚠️ Do **not** build around Maura Gillison — deceased
  July 2026; Ferrarotto is the active successor-generation lead.)
- **Dr. Andrew G. Sikora, MD PhD** — Professor & Director of Research, Head & Neck Surgery, MD Anderson
  (also Baylor Otolaryngology). HPV E6/E7 **peptide vaccine + checkpoint**; ran a window-of-opportunity Ph2.
  *Surgeon-scientist; strongest thematic anchor.*
- **Dr. K. Jagannadha (Jagan) Sastry, PhD** — Professor, Immunology, MD Anderson; ~25 yrs HPV therapeutic
  peptide-vaccine + checkpoint. *Immunology anchor; pair with a clinician.* Known Sikora pairing.
- **Dr. Amir A. Jazaeri, MD** — GYN Oncology, MD Anderson; cervical-cancer immunotherapy (anchor for a
  cervical pivot/fast-follow).
- **Dr. Cassian Yee** — MD Anderson; adoptive/antigen-specific T-cell therapy; **ACT alum** (easy warm intro).
  *Immunogenicity + tumor-killing validation.*
- **Dr. Alexandre Reuben** — MD Anderson; TCR repertoire / neoantigen discovery; **ACT alum**. *Target-discovery
  validation; bridges the immune-LLM to real TCR data.*
- **Drs. Padmanee Sharma & James Allison** — MD Anderson checkpoint-immunotherapy leaders (Allison = Nobel
  laureate); SAB/credibility only. **Cold / aspirational** — no direct line.
- *Sequencing:* lock one MDA clinical anchor (Ferrarotto, or Sikora+Sastry as a package) → add a T-cell
  validator (Yee/Reuben) → name the wet-lab cores → ask ACT to broker intros.

### A3. Texas academic / clinical-genomics centers & faculty (reproducibility + on-prem wedge)
*Named contacts below are from `texas_targets.json` (now parsed/verified, 63 entries); re-confirm emails before outreach.*
- **UT Southwestern (Dallas) — Lyda Hill Department of Bioinformatics** — Chair **Gaudenz Danuser**; faculty
  **Yang Xie** (Dir. QBRC), **Lin Xu**, **Jeon Lee**, **Chao Xing**, **Xiaowei Zhan**. BioHPC; broad multi-omics.
  Also the O'Donnell Brain Institute (neuro multi-omics). *Cold; P2.*
- **Baylor College of Medicine — Human Genome Sequencing Center (HGSC)** — Dir. **Richard Gibbs**; **Fritz
  Sedlazeck** (structural variants). 200+ staff; DNAnexus power-user → compliance-aware buyer. *Cold; P2.*
- **MD Anderson — Bioinformatics & Computational Biology** — Prof. & Chair **Ken Chen** (cancer genomics). *Cold; P2.*
- **Rice University** — **Todd Treangen** (metagenomics / biothreat); **Lydia Kavraki** & **Luay Nakhleh**
  (AI2Health / computational biology); Ken Kennedy Institute. *Cold; P2.*
- **UTHealth Houston — McWilliams School of Biomedical Informatics** (the founder's former school; see A1). *Warm-adjacent.*
- **UT Dallas — Genome Center & Bioinformatics** — **Michael Qiwei Zhang** (epigenomics), Kelli Palmer, Li Zhang. *Cold; P3.*
- **University of Houston — Computational Biology & Bioinformatics** — **Zhiqiang An** (antibody discovery / cancer genomics). *Cold; P2.*
- **UTMB Galveston — Bioinformatics & Genomics Lab** — **Yuriy Fofanov**; infectious-disease genomics; Galveston National Lab. *Cold; P3.*
- **UT Austin** — Center for Computational Biology (**Claus Wilke**, **Edward Marcotte**); **Dell Medical School**
  (Dean **Claudia Lucchinetti**; precision medicine); Oden Institute (CSE-broad). *Cold; P3.*
- **Texas A&M — Institute for Genome Sciences & Society (TIGSS)** (**Joshua Yuan**, synthetic biology); AgriLife
  Genomics (TxGen core). *Cold; P3.*
- **UNT Health Science Center (Fort Worth)** — **Bruce Budowle**, **Arthur Eisenberg** (forensic / molecular genetics). *Cold; P3.*
- **UT Health San Antonio / UTSA**; **TTUHSC (Lubbock)**; **UTRGV (Edinburg)** — South/West Texas genomics. *Identify contact; Cold; P3.*
- **Texas Biomedical Research Institute (San Antonio)** — Pres./CEO **Larry Schlesinger**, **Binhua Ling**; 28 PIs,
  BSL-4, vaccine immunogenicity; immune multi-omics + on-prem (biosecure) fit. *Cold; P3.*
- **Houston Methodist Research Institute — Bioinformatics & Biostatistics Core** (fan-out channel; serves PIs with
  no bioinformatician). Also **Dr. Shu-Hsia Chen** (2025 ACT, IO). *Identify core director; Cold; P2.*

### A3b. Texas hospital systems, cancer centers & clinical-genomics programs
- **UT Southwestern — Simmons Comprehensive Cancer Center** — Dir. **Carlos Arteaga**. *Cold; P2.*
- **Texas Children's Hospital — Jan & Dan Duncan Neurological Research Institute** — Dir. **Huda Zoghbi** (rare
  neuro-disease genomics). *Cold; P2.*
- **Children's Medical Center Dallas — Genomics & Rare Disease** — **Josh Bhatt**. *Cold; P3.*
- **Texas Heart Institute — Cardiovascular Genomics** — Pres./CEO **Joseph Rogers**. *Cold; P3.*
- **Baylor Scott & White Health — Genomics & Precision Medicine** (Dallas); **Memorial Hermann — Clinical
  Genomics** (Houston); **Cook Children's — Genomics & Rare Disease** (Fort Worth). *Identify contact; Cold; P3.*
- **MD Anderson — Proteomics & Metabolomics Core Facility** (see also A4 immunopeptidomics). *Cold; P2.*

### A4. Wet-lab cores — the in-vitro validation package (customers, cheap/fast)
- **MD Anderson Proteomics Facility — immunopeptidomics / MHC-peptide mass spec** (confirm which predicted
  epitopes are actually presented → the "LLM-validated-in-wet-lab" data point).
- **Baylor College of Medicine MHC Tetramer Production Core** (custom tetramers → antigen-specific T-cell flow).
- **BCM Protein/Peptide Core** (local peptide synthesis).
- **MD Anderson ORION immune-monitoring + Flow Cytometry cores** (ELISpot / multimer T-cell assays).
- **Peptide chemistry / developability:** Dr. **Gomika Udugamasooriya** (Univ. of Houston; ACT 2025 alum);
  Dr. **Zhiqiang An** / Dr. **Kyoji Tsuchikama** (UTHealth Texas Therapeutics Institute; CMC/developability, PDC route).

### A5. Collaborator-or-competitor (handle with clear IP boundaries)
- **Dr. Tao Wang (UT Southwestern)** — built **pMTnet** (TCR–pMHC deep learning); founded **NightStar
  Biotechnologies** (AI TCR/neoantigen, ACT 2024). Nearest to our immune-LLM — possible modeling collaborator
  **and** nearest competitor. Clear IP boundaries only.

---

## B. Physicians / faculty — BEYOND TEXAS
*National SAB credibility can be added without a Texas address (the company's CPRIT nexus is via Houston).
Entries below are sourced from ClinicalTrials.gov (registry data, accessed 2026-10-06); institution-level
targets are cold/aspirational with the site PI to be identified (the registry did not name site PIs).*

### B1. Named non-Texas investigators (exact modality — HPV + checkpoint)
- **Dr. Jared Weiss (UNC Chapel Hill)** — VERSATILE-002 (PDS0101+pembrolizumab) investigator; national SAB
  voice on the exact modality.
- **Dr. Charalampos Floudas, MD (National Cancer Institute, Bethesda MD)** — PI, "Combination Immunotherapy in
  Advanced HPV-Associated Malignancies" (NCT04287868, NCI). Named Overall Official; exact HPV+checkpoint space.
- **Pr. Christophe Borg (CHU Besançon, France)** — PI, UCPVax HPV-telomerase vaccine + atezolizumab (VolATIL,
  NCT03946358). *International* modality anchor.
- *Industry study directors (not academic SAB, but modality-adjacent):* Kirk V. Shepard, MD (PDS Biotechnology);
  Head of Clinical Development (Hookipa Biotech).

### B2. Non-Texas institutions that ran the flagship modality (PDS0101+pembro, NCT06790966) — cold, identify site PI
UNC Chapel Hill · Yale · Emory Winship · Mayo Clinic (Rochester / Florida / Arizona) · University of Michigan ·
University of Maryland · Ohio State (James) · Fox Chase · Medical University of South Carolina · University of
Virginia · Penn State Health · University of Kentucky / University of Louisville / Norton · Karmanos (Detroit) ·
University of Kansas · University of Tennessee (Knoxville) · West Virginia University. *(Source: NCT06790966
facility list; each site's PI must be identified before outreach — not asserted here.)*

### B3. Other HPV-vaccine-trial institutions (named-PI TBD) — broader cold pool
From related HPV16 vaccine ± checkpoint trials (NCT04180215 Hookipa; NCT04084951 / NCT04892043 / NCT05357898
SQZ): MSKCC · Mount Sinai (Icahn) · NYU Langone / Grossman · Montefiore-Einstein · Massachusetts General ·
Cedars-Sinai · USC Norris · UCLA · UC San Diego Moores · City of Hope · Sylvester (Miami) · University of
Chicago · Washington University St. Louis · Vanderbilt · Cleveland Clinic · University of Colorado Anschutz ·
Roswell Park · Rutgers · Masonic (U Minnesota) · OHSU / Providence (Portland). *(Institution-level only;
identify the HPV-IO PI at each before outreach.)*

---

## C. CROs & clinical-genomics labs with clinical data

### C1. Texas CROs / core-facility channel
- **Altogen Labs (Austin)** — preclinical CRO (PK/PD, xenografts, ELISA, stable lines, tox). *Wet+dry
  partnership: they run assays, BioMate adds omics analysis + reporting; or their client base as a channel.* P2.
- **Southwest Research Institute (San Antonio)** — large independent applied-R&D contract org (bioscience
  division). *Execution-backbone / white-label thesis. Identify contact; P3.*
- **Boutique / specialized Texas CROs + academic core facilities** (genomics / proteomics / single-cell cores
  at the A3 institutions) — lack bioinformatics teams, face margin pressure, need reproducible/auditable output
  → BioMate as their **on-prem execution backbone** (recurring + brings client volume). *Map & identify
  contacts; P2.*
- **Texas operations of national diagnostic labs** (from `texas_targets.json`, now parsed; re-confirm named
  contacts/emails before outreach):
  - **Sonic Healthcare USA** — Clinical Genomics & Pathology (Austin); CEO **Chris Stelzel**. *Priority A.*
  - **Quest Diagnostics** — Advanced Diagnostics & Genomics (Dallas); VP Advanced Dx & Genomics; Medical Dir., Oncology Genomics.
  - **Labcorp Diagnostics** — Genomics & Molecular Pathology (Houston); Regional Medical Director, Genomics.
  - **Myriad Genetics** — Hereditary Cancer & PGx (CEO **Paul Diaz**); **GeneDx** — pediatric/rare-disease (CEO **Katherine Johansen Taber**).
  - **CHRISTUS Health** — Laboratory & Genomics Services (Irving); Chief Laboratory Officer.
  - Industry R&D in Texas: AstraZeneca BioHub @ TMC3 (Houston); Thermo Fisher sequencing (Austin).

### C2. National CROs & clinical-genomics labs (from `clinical_cro_targets.json`)
Angle: BioMate's **reproducible QC governance + audit-trail** story (Part-11/ICH-E6-oriented). **Caveat:**
large full-service CROs have their own platforms/teams (build-vs-buy; a tool that commoditizes their dry-lab
margin meets resistance) — pursue **boutique/specialized CROs + academic cores** as the primary wedge; treat
the majors as long-cycle/partnership plays.

| Priority | Organization | Location | Type | Fit |
|---|---|---|---|---|
| A | **Labcorp Drug Development (Covance)** — Genomics & Translational | Durham, NC | top CRO | clinical/oncology NGS, pharmacogenomics; Part-11 audit trail |
| A | **Charles River Laboratories** — Genomics & Translational Sciences | Wilmington, MA | top CRO | preclinical safety; toxicogenomics (FDA SEND), GLP compliance |
| A | **PPD (Thermo Fisher)** — Genomics & Central Lab | Wilmington, NC | top CRO | clinical-trial genomics, biomarkers; Part-11 |
| A | **Tempus AI** — Clinical Genomics & AI | Chicago, IL | AI clinical-genomics lab | multi-omics at scale; **partnership angle** (QC layer complements their platform) |
| B | **IQVIA** — Genomics & Real-World Evidence | Durham, NC | top CRO | multi-site trial QC harmonization |
| B | **Syneos Health** — Translational Genomics | Morrisville, NC | CRO | biomarkers; multi-site harmonization |
| B | **Exact Sciences (Genomic Health)** — Oncology Dx | Madison, WI | clinical lab | Oncotype DX; clinical-assay QC |
| B | **Foundation Medicine (Roche)** — Comprehensive Genomic Profiling | Cambridge, MA | clinical lab | FDA-cleared CGP; 510(k) reproducibility/audit |
| B | **Invitae** — Genetic Testing | San Francisco, CA | clinical lab | high-volume rare-disease / PGx panels |

*(`clinical_cro_targets.json` meta lists 18 total targets; the above are the entries captured in the file as
read. Priority-A outreach email drafts exist in `cro_priority_A_emails.txt` for Charles River, Labcorp, PPD,
and Tempus — re-verify named recipients and the capability P.S. before any send.)*

---

## D. First contacts & sequencing

**BD (from `HOUSTON_TEXAS_PROSPECTS.md` — first 10, warm first):**
1. **SBMI group** (Zhao → Zhi → Zheng) — warm by affiliation; open on the live scGWAS demo.
2. **TMC Innovation Factory / Innovation Labs @ TMC** — accelerator/channel, high leverage; request preferred-resource listing.
3. **Mongoose Bio (Houston)** — `info@mongoosebio.com`; target/epitope + TCR–HLA–peptide pilot.
4. **ImmunoGenesis (Houston)** — responder/resistance stratification demo.
5. **UT Southwestern — Lyda Hill Dept.** — reproducibility/methods collaboration.
6. **Diakonos Oncology (Houston)** — prospective DOC1021 responder prediction.
*(Batch the Houston in-person visits — Mongoose + ImmunoGenesis + Diakonos — around the SBMI meeting.)*

**ACT clinical anchor (parallel track, Oct 31 deadline):** send Ferrarotto + Sikora + Sastry the same week;
add Yee/Reuben (ACT alumni, warm intros); name MDA immunopeptidomics + BCM tetramer cores; ask ACT to broker.
Aim for ≥1 signed Letter of Support before Oct 31 (a call + verbal intent is an acceptable interim).

---

## E. Honesty log & gaps
- **"Identify contact"** (no name asserted): Houston Methodist CBCB/BBI director; Rice Ken Kennedy bio-PI beyond
  Treangen; UT Austin Oden comp-bio PI; UTMB/UTSA/A&M core directors; Southwest Research Institute bioscience lead.
- **SBMI trio** = affiliation-warm, outreach **not** confirmed initiated. Do not represent as active relationships.
- **MD Anderson** = bottom-up via a specific PI lab only; institution-level is cold/aspirational.
- **`texas_targets.json`** (Feb-2026, 63 targets) has now been **parsed and its clinical/academic/lab entries
  folded in** (A3/A3b/C1). The named contacts are as recorded in that file (titles are often role-placeholders,
  e.g. "Chief Genomics Officer"); **emails must be re-confirmed before any send**. Its 7 `energy`-segment entries
  (bioremediation/biofuels) were excluded as non-clinical.
- **"Beyond Texas" (§B) is now populated from ClinicalTrials.gov registry data** (WebSearch was unavailable —
  budget exhausted — so the registry API was used instead; no unsourced names were added). Honest limits: only
  **named** out-of-state PIs are Weiss (UNC), Floudas (NCI), and Borg (CHU Besançon, international); the rest are
  **institution-level cold targets** (B2/B3) whose site PIs the registry did not name and must be identified
  before outreach. Cyclic-peptide / αvβ6 / radioligand clinical leads were **not** sourced this pass (next TODO).
- **Company emails** (Mongoose, ImmunoGenesis) and CRO email drafts carry prior ✓/✓fmt provenance — re-verify
  format before sending; Diakonos/7 Hills/ImmunoMet have no verified personal address (use contact form/PR).
- **BioMate capability caveats** (A2/C2 above) must not be over-promised.
