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

### A3. Texas academic / clinical-genomics centers (reproducibility + on-prem wedge)
- **Baylor College of Medicine — Human Genome Sequencing Center (HGSC)**; Dir. **Richard Gibbs** (200+ staff;
  DNAnexus power-user → compliance-aware buyer). *Cold; P2.*
- **Houston Methodist Research Institute — Bioinformatics & Computational Biology + Biostatistics Core**
  (serves many wet-lab PIs with no bioinformatician — fan-out channel). Also **Dr. Shu-Hsia Chen** (2025 ACT,
  IO). *Identify core director; Cold; P2.*
- **Rice University — Prof. Todd Treangen** (microbial genomics / metagenomics / biothreat); Ken Kennedy
  Institute. *Cold; P2.*
- **UT Southwestern (Dallas) — Lyda Hill Department of Bioinformatics**; Chair **Gaudenz Danuser** (17
  faculty, 120 scientists); also the O'Donnell Brain Institute (neuro multi-omics); **Simmons Comprehensive
  Cancer Center**. *Cold; P2.*
- **UTMB Galveston** (clinical/translational + infectious disease; Galveston National Lab). *Identify contact; Cold; P3.*
- **UT Health San Antonio / UTSA**; **UT Austin — Oden Institute** (+ Dell Medical); **Texas A&M** (biosciences /
  AgriLife genomics). *Identify comp-bio/biosciences PI; Cold; P3.*
- **Texas Biomedical Research Institute (San Antonio)** — 28 PIs, BSL-4, vaccine immunogenicity; immune
  multi-omics + on-prem (biosecure) fit. *Cold; P3.*

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
- **Dr. Jared Weiss (UNC)** — VERSATILE-002 (PDS0101+pembro) investigator; national SAB voice on the exact
  modality. (Texas nexus is already satisfied by being Houston-based, so an out-of-state SAB member is fine.)
- *General:* national SAB credibility can be added without a Texas address; team members/advisors may be
  anywhere. (The company's Texas/CPRIT nexus is via Houston.)

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
- **Texas operations of national diagnostic labs** (per `texas_targets.json`, to be re-verified from source):
  Quest Diagnostics, Labcorp, Myriad Genetics, GeneDx, Sonic Healthcare USA, CHRISTUS Health, Baylor Scott &
  White, Baylor Genetics, Children's Medical Center Dallas, Memorial Hermann, Texas Heart Institute, Cook
  Children's — plus industry R&D (AstraZeneca BioHub @ TMC3; Thermo Fisher sequencing, Austin).

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
- **`texas_targets.json`** is a Feb-2026 long-list (146 entries); its per-contact↔institution mapping was **not
  machine-verified** in this consolidation — read specific names/emails from the source file before use.
- **"Beyond Texas" coverage is CRO/clinical-lab-heavy** (C2) and physician-light (B = Weiss/UNC). If broader
  out-of-state physician/faculty coverage is wanted, that is a gap to fill next.
- **Company emails** (Mongoose, ImmunoGenesis) and CRO email drafts carry prior ✓/✓fmt provenance — re-verify
  format before sending; Diakonos/7 Hills/ImmunoMet have no verified personal address (use contact form/PR).
- **BioMate capability caveats** (A2/C2 above) must not be over-promised.
