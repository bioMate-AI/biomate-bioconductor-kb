# Dr. Chandra Mohan — Research Data & Grant Inventory

**Prepared:** 2026-09-14
**Subject:** Chandra Mohan, MD PhD — Hugh Roy & Lillie Cranz Cullen Endowed Professor of Biomedical Engineering, University of Houston (cmohan@central.uh.edu). Directs the Houston Omics Collaborative / Cancer Immunotherapy Biomarker Core (CIBC). Prior affiliation: UT Southwestern Medical Center (lupus genetics/immunology). Earliest independent PI role: University of Florida (late 1990s).
**Purpose:** Assess a computational collaboration — extend beyond the ALCAM/LN urine-ELISA slice we already have, into his transcriptomic, genomic/GWAS, IBD, and spatial-omics cohorts, plus his full grant portfolio.

**Sourcing method:** PubMed via NCBI E-utilities (esearch/efetch, `db=pubmed`, term `Mohan C[au] AND (lupus OR "lupus nephritis" OR SLE OR IBD OR "inflammatory bowel")` + targeted GWAS/genome-wide query); GEO via E-utilities (`db=gds`); NIH RePORTER API v2 (`api.reporter.nih.gov/v2/projects/search`, PI Chandra Mohan); CPRIT, Lupus Research Alliance, and DOD/CDMRP via web search. Every row carries a PMID / DOI / accession / grant#. Disambiguation was enforced on author affiliation (UH-BME or UTSW lupus group); two false "IBD" hits (veterinary infectious bursal disease virus; medicinal chemistry) were rejected.

> **CRITICAL CAVEAT ON DATA AVAILABILITY:** For nearly every cohort paper, the *abstract did not state* a repository accession. Data-availability was resolvable from abstracts/GEO for only a handful (listed). All "Not stated" entries below require confirmation from the full-text Data Availability statement before being relied upon for a collaboration. DOIs for pre-2018 papers were anchored on PMID (parser picked up cross-referenced DOIs for some older records); post-2018 DOIs are from `ArticleIdList` and reliable.

---

## PART A — Cohort / Data Publications

### A0. What's genuinely NEW vs. what we already have

| Stratum | Have already? | Papers |
|---|---|---|
| LN urine ALCAM / ELISA / POC-device slice | **YES (excluded from detail)** | 32366845 (Nat Commun 2020 ALCAM), 34981775, 37720233, 36569940, 37431809, 38392017, 32546742 (correction), plus J Autoimmun 2024 panel |
| **Human IBD proteomic cohorts** | **NEW** | 34183667, 36549591, 40252987, 42039204 |
| **Human whole-blood bulk transcriptome (SLE/LN/NPSLE, PRECISESADS)** | **NEW** | 36996699, 38899167, 40672966 |
| **Spatial transcriptomics / spatial proteomics — LN kidney** | **NEW** | 42138328, 42656727, 37516396 |
| **Multi-omic urine proteome + renal scRNA-seq (LN)** | **NEW / partly** | 34783463, 38194790, 32396533 |
| **Autoantibody / autoantigen arrays (SLE)** | **NEW** | 31494269 (ProtoArray 9400-antigen), 27211902 (274-plex serum), 35419005 (immune-complex MS) |
| **Human SLE GWAS / genotype cohort owned by Mohan** | **NONE FOUND** (see A5) | — |

### A1. IBD cohorts (all NEW — the highest-priority gap being filled)

| PMID | Yr | Journal | DOI / PMC | Disease | Modality | Cohort N + composition | X-sec/Long | Tx/response labels | Multi-omic paired (same pts) | Data avail |
|---|---|---|---|---|---|---|---|---|---|---|
| **34183667** | 2021 | Nat Commun | 10.1038/s41467-021-24235-0 · PMC8239008 | IBD (UC+CD), pediatric | Aptamer 1129-plex **stool** proteomics → ELISA | Discovery IBD cohort + **longitudinal 50 UC @ 4 timepoints** | Both | **Y** — predicts wk-4 clinical remission (PUCAI/PGA) | N | Not stated |
| **36549591** | 2023 | Mol Cell Proteomics | 10.1016/j.mcpro.2022.100487 · PMC9918796 | IBD (UC+CD), pediatric | Aptamer 1322-plex **plasma** proteomics → ELISA | N=76 (30 CD, 30 UC, 16 HC) | X-sec | N (diagnosis) | N | Not stated |
| **40252987** | 2025 | Clin Immunol | 10.1016/j.clim.2025.110495 | IBD (UC+CD), pediatric | 1000-plex **antibody array**, **stool** → ELISA | N=73 (24 ctrl, 39 CD, 10 UC), **treatment-naïve** | X-sec | Partial (Tx-naïve baseline) | N | Not stated |
| **42039204** | 2026 | Front Immunol | 10.3389/fimmu.2026.1624045 · PMC13106603 | IBD (Crohn's), pediatric | Aptamer **stool** screen → ELISA | N=47 baseline (Pediatric **RISK** stratification study) | Long/predictive | **Y** — predicts stricturing/penetrating progression | N | Not stated (RISK cohort) |

*Also surfaced via web (medRxiv 2025 preprint): salivary proteomics ML classifier for pediatric IBD — [medrxiv 2025.10.14.25337919]. Preprint, not yet indexed; flag as emerging.*

### A2. Whole-blood bulk transcriptome cohorts — SLE/LN/NPSLE (NEW; riding on EU PRECISESADS)

| PMID | Yr | Journal | DOI / PMC | Disease | Modality | Cohort N | X-sec/Long | Tx/response labels | Multi-omic paired | Data avail |
|---|---|---|---|---|---|---|---|---|---|---|
| **36996699** | 2023 | J Autoimmun | 10.1016/j.jaut.2023.103025 | SLE | **Whole-blood bulk transcriptome + eQTL + serology** | **350 SLE / 497 HC** (PRECISESADS, NCT02890121); external validation **GSE88887** | X-sec | Partial (druggability framing) | Y (transcriptome+eQTL+serology, same pts) | **PRECISESADS = controlled access; GSE88887 = public GEO** |
| **38899167** | 2024 | Kidney Int Rep | 10.1016/j.ekir.2024.03.014 · PMC11184261 | LN + non-renal SLE | Whole-blood bulk transcriptome (WGCNA) | Active LN n=41, active non-renal n=62, HC n=497 (PRECISESADS) | X-sec | **Y** — in-silico predicted response (anifrolumab, daratumumab, CNI, B-cell) | Transcriptome + serology | PRECISESADS (controlled access) |
| **40672966** | 2025 | J Transl Autoimmun | 10.1016/j.jtauto.2025.100296 · PMC12266536 | NPSLE | Whole-blood bulk transcriptome (WGCNA) | Active CNS lupus n=26, active SLE n=38, HC n=497 (PRECISESADS) | X-sec | **Y** — predicted response (anifrolumab, C3i, CNI) | Transcriptome + serology | PRECISESADS (controlled access) |

### A3. Spatial transcriptomics & spatial proteomics — LN kidney (NEW; several outcome-labeled)

| PMID | Yr | Journal | DOI / PMC | Disease | Modality | Cohort N | X-sec/Long | Tx/response | Multi-omic paired | Data avail |
|---|---|---|---|---|---|---|---|---|---|---|
| **42138328** | 2026 | Arthritis Rheumatol | 10.1002/art.70220 | LN | **Spatial transcriptomics (10x Visium)** + cyclic IF + urine ELISA | LN biopsies + transplant controls (N not stated); independent Visium cohort | X-sec | N | Y (spatial RNA + multiplex protein + urine, overlapping pts) | Not stated |
| **42656727** | 2026 | Front Immunol | 10.3389/fimmu.2026.1802673 · PMC13506827 | LN | **34-plex spatial proteomics** (renal) | 16 LN (induction therapy) + RCC controls; 53 glomerular + 49 TI ROIs | Baseline→outcome | **Y** — predicts non-response to induction | Single modality | Not stated |
| **37516396** | 2023 | Clin Immunol | 10.1016/j.clim.2023.109713 | LN | **50-plex imaging mass cytometry** (renal) | Proliferative LN + control kidneys (N not stated) | X-sec | N | Single modality | Not stated |

### A4. Multi-omic PAIRED — urine proteome + renal scRNA-seq (LN) — highest-value integrative resources

| PMID | Yr | Journal | DOI / PMC | Disease | Modality | Cohort N | X-sec/Long | Tx/response | Multi-omic paired (same pts) | Data avail |
|---|---|---|---|---|---|---|---|---|---|---|
| **32396533** | 2020 | JCI Insight | 10.1172/jci.insight.138345 (verify) | LN | **Urine 1000-plex proteomics + renal scRNA-seq integrated** | **30 active LN**; paired kidney-biopsy scRNA-seq | X-sec | Stratifies proliferative vs not (IFN-γ gradient) | **Y** (standout paired) | Not stated (scRNA may be AMP/GEO — verify) |
| **34783463** | 2022 | Arthritis Rheumatol | 10.1002/art.42023 · PMC9050800 | LN | **Longitudinal urine 1000-plex proteomics + renal scRNA-seq** | **30 LN**, biopsy + 3/6/12 mo | Longitudinal | **Y** — Tx response; IL-16 tracks activity | Y/unclear (scRNA may be separate donors) | Not stated |
| **38194790** | 2024 | J Autoimmun | 10.1016/j.jaut.2023.103165 | LN | **Olink PEA urine proteomics** + renal scRNA-seq cross-ref | Urine N=117 (inactive SLE, active non-renal, active LN, HC) + indep. ELISA cohort | X-sec | Partial | Y/unclear (scRNA cross-ref, likely separate source) | Not stated |
| **41031884** | 2025 | J Clin Invest | 10.1172/JCI186143 · PMC12483563 | LN | Aptamer 1317-plex **urine** proteomics at biopsy | LN at renal biopsy (N not stated); acute vs chronic pathology | X-sec (biopsy-paired) | N (AI/CI pathology labels) | Urine + in-vitro mechanism | Not stated |
| **32651195** | 2020 | Ann Rheum Dis | 10.1136/annrheumdis-2019-216312 (verify) | LN | Planar array 1000-plex **urine** + scRNA-seq cross-ref | Screen + independent val + concurrent-biopsy + longitudinal | Both | Some longitudinal | Y/unclear | Not stated |

### A5. Autoantibody / autoantigen arrays & immune-complex proteomics (SLE) — NEW evidence channel

| PMID | Yr | Journal | DOI | Disease | Modality | Cohort N | Notes |
|---|---|---|---|---|---|---|---|
| **31494269** | 2019 | Genomics Proteomics Bioinformatics | 10.1016/j.gpb.2018.11.001 (verify) | SLE | **ProtoArray autoantigen array, 9400 antigens (IgG+IgM)** | SLE vs HC discovery + ELISA/WB validation (N not stated) | Largest autoantigen array; correlates anti-dsDNA |
| **27211902** | 2016 | J Proteome Res | 10.1021/acs.jproteome.6b00183 (verify) | SLE/LN | 274-plex serum antibody array → ELISA | 22 SLE+HC discovery; 28 SLE val; 45 LN @ biopsy; **7 SLE longitudinal** | Serum proteome + paired biopsy activity/chronicity; tracks flares |
| **35419005** | 2022 | Front Immunol | 10.3389/fimmu.2022.850015 | LN | **Immunoproteomics of circulating immune complexes (LC-MS/MS)** + scRNA ref | 62 LN / 21 HC validation | Novel ICx biomarkers |
| **25345756** | 2015 | Clin Exp Immunol | 10.1111/cei.12452 (verify) | LN | 15-adipokine antibody array → ELISA | LN + matched controls (N not stated) | Small array screen |

### A6. Other primary omics/proteomics/metabolomics cohorts (SLE/LN/NPSLE — adjacent evidence channels)

| PMID | Yr | Journal | Disease | Modality | Cohort N | Tx/response | Note |
|---|---|---|---|---|---|---|---|
| **35099126** | 2022 | Arthritis Rheumatol | NPSLE | Aptamer **CSF** proteomics + choroid-plexus transcriptome overlap | NPSLE n=24 + Hong Kong cohort | — | CSF biomarkers |
| **37163449** | 2023 | Arthritis Rheumatol | LN | Protein microarray → ELISA (VSIG4 serum) | screen + val 81 then 155 | Longitudinal | AI-index correlation |
| **38782493** | 2024 | Lupus Sci Med | SLE | **iTRAQ serum MS** → ELISA | Cohort I N=52, II N=117 | — | AMBP/AZGP/RBP4 |
| **36167482** | 2022 | Lupus Sci Med | LN | 1000-plex antibody microarray **urine** | **54 (BLISS-LN trial-derived)**, wks 0/24/52 | **Y — responder vs non-responder + belimumab arm** | **RCT-derived, high value** |
| **32540998** | 2020 | J Immunol | SLE/RA | **LC-MS metabolomics** (bradykinin peptides) + MRM | screen + MRM val (N not stated); incl RA | Assoc renal SLEDAI | — |
| **35651909** | 2022 | Front Cardiovasc Med | SLE (CVD) | Serum **metabolomics** | 9 SLE / 8 SLE+plaque / 8 ctrl | — | **Longitudinal 8–9 y plaque progression** |
| **31075396** | 2019 | Clin Immunol | SLE | Anti-oxidized-lipid autoAb / immune-complex ELISA panel | 64 SLE + 9 HC | Corr SLEDAI, C3/C4 | — |
| **39404817** | 2025 | Rheumatology | LN | Urine ALCAM/CD6 ELISA | **122 biopsy-proven LN, longitudinal wk 0/12/26/52** | **Y — responder vs non-responder** | ALCAM slice but longitudinal & outcome-labeled |
| **30742665** | 2019 | PLoS One | LN | Serum Axl ELISA | 52 class III/IV LN + 20 HC | **Y — induction-therapy response + long-term outcome** | Outcome-labeled |
| **26568320** | 2015 | Arthritis Res Ther | Discoid LE (skin) | **Microarray transcriptome** (lesional vs normal skin) + qRT-PCR/IHC | DLE lesional vs control skin (N not stated) | — | Human skin transcriptome (GEO **GSE72535**, N=17 — see A7) |

### A7. Deposited datasets confirmed via GEO (E-utilities `db=gds`)

| Accession | Type | N | Organism | Year | Title / linked work |
|---|---|---|---|---|---|
| **GSE278051 / GSE278050 / GSE278048** | RNA-seq + ATAC-seq | 70 / 42 / 28 | Mouse | 2024 | KLF13 promotes SLE pathogenesis (chromatin accessibility) — links to PMID 39506084 |
| **GSE72535** | Expression array | 17 | **Human** | 2015 | CD163 macrophages in discoid lupus skin (links to 26568320) |
| **GSE73112** | Expression array | 6 | Mouse | 2015 | FAAH regulates B-cell receptor revision in lupus |
| **GSE50609** | Protein array | 3 | Human/Mouse/Rat | 2013 | 9G4 B-cell autoreactivity in human SLE |
| **GSE10325 / GDS4185** | Expression array | 67 | **Human** | 2008 | SLE PBMC subsets (B/T/myeloid) — publicly reusable human SLE transcriptome |
| **GSE88887** | (external) | — | Human | — | Used by Mohan as *external validation* in 36996699 (public GEO) |

*These are the ONLY deposited accessions positively confirmed. Most cohort papers (spatial, urine proteomics, IBD stool) do not surface an accession from abstract/GEO and need full-text checks.*

### A8. Verified NEGATIVE: no human SLE GWAS/genotype cohort owned by Mohan

Targeted query `Mohan C[au] AND (GWAS OR "genome-wide association" OR genotyping OR "susceptibility loci") AND (lupus OR SLE)` returned ~34 PMIDs. On affiliation/title triage, **all are (a) murine congenic-strain lupus genetics** (Sle1/Sle2/Sle3/Sle5, Ly108, IRAK-region mapping — his UTSW mouse program, e.g. 16778059 Science *Ly108*, 17728789, 15693014, 12687552) **or (b) human genetics papers where Mohan is a collaborator, not the cohort owner** (e.g. 19329491 IRAK1, PNAS 2009 — USC Lupus Genetic Group / Tsao). **No human SLE GWAS dataset generated/owned by Mohan was found.** His genomic assets are murine-genetic + the chromatin (ATAC/RNA) mouse datasets in A7. *Flag: a pre-1999 UF-era or externally-held human genotype resource cannot be fully excluded but none surfaced.*

### A9. Usefulness ratings (per cohort/cluster, for the collaboration axes)

Axes: **Parity** = blind target-recovery / benchmarking value · **Prot-ev** = proteomic evidence channel · **Causal** = causal target-confidence · **Strat** = responder/mechanism stratification · **X-val** = cross-cohort validation.

| Cohort cluster (PMIDs) | Parity | Prot-ev | Causal | Strat | X-val | One-line why |
|---|---|---|---|---|---|---|
| **IBD stool/plasma proteomics** (34183667, 36549591, 40252987, 42039204) | **High** | **High** | Med | **High** | Med | Untouched-by-us disease; two are longitudinal outcome-predictive (remission, stricturing) → clean blind-recovery + responder tests |
| **PRECISESADS whole-blood transcriptome** (36996699, 38899167, 40672966) | **High** | Med | **Med** | **High** | **High** | Large (350+SLE/497HC), eQTL for causal anchoring, in-silico drug-response predictions, external GEO validation |
| **Spatial trans/proteomics LN kidney** (42138328, 42656727, 37516396) | Med | **High** | **High** | **High** (42656727) | Low | Tissue-resolved causal localization; 42656727 has induction non-response labels |
| **Urine proteome + renal scRNA-seq (LN)** (32396533, 34783463, 38194790) | **High** | **High** | **High** | **High** | Med | Paired fluid↔tissue multi-omic; longitudinal Tx-response (IL-16); strongest integrative resource |
| **Autoantigen/autoantibody arrays** (31494269, 27211902, 35419005) | Med | **High** | Med | Med | Med | 9400-antigen breadth = strong proteomic/serologic evidence channel; some longitudinal |
| **RCT-derived urine proteome** (36167482 BLISS-LN; 39404817 ALCAM long.) | Med | **High** | Med | **High** | **High** | Belimumab responder/non-responder labels from trial context = gold for stratification/validation |
| **CSF / metabolomics / skin** (35099126, 35651909, 26568320) | Low | Med | Med | Low | Low | Niche modalities/small N; supporting evidence only |
| **LN urine ALCAM ELISA slice (already have)** | — | — | — | — | — | Excluded — already in hand |

---

## PART B — Grant Portfolio

### B1. NIH (source: NIH RePORTER API v2, PI "Chandra Mohan"; 91 project-year records → 20 distinct core projects; deduped by core project number, amounts summed across FYs captured)

| Core Project # | Title | IC | Org | Role | FY span | Total captured (USD) | Topic |
|---|---|---|---|---|---|---|---|
| **R01AR086872** | Gene-environment triggers & proteomic pathways mediating anti-nuclear autoimmunity & systemic rheumatic disease | NIAMS | UH | **Contact-PI** (MPI: Costenbader) | 2026–2031 | $667,276 (yr1) | 10-yr longitudinal autoimmunity triggers/proteomics (the 2026 "$4M/$5M" news grant) |
| **R01DK134055** | Objective Classification of Lupus Nephritis | NIDDK | UH | **Contact-PI** (MPI: Nguyen) | 2023–2028 | $2,455,928 | ML/AI LN classification |
| **R21AR082713** | Diagnostic utility of antibodies to post-translationally modified nucleosomes in LN | NIAMS | UH | **PI** | 2023–2025 | $333,193 | Autoantibody diagnostics |
| **R33AR078078** | Combined OCE + tomography for skin involvement in systemic sclerosis | NIAMS | UTHSC-Houston | **co-I / MPI** (Contact: Assassi) | 2023 | $388,525 | SSc skin imaging |
| **R61AR078078** | (R61 phase of above) | NIAMS | UTHSC-Houston | **co-I / MPI** (Contact: Assassi) | 2020, 2022 | $779,734 | SSc skin imaging |
| **R56DK122036** | Lupus Nephritis Neural Network (LuNN) | NIDDK | UH | **Contact-PI** (MPI: Nguyen) | 2020 | $100,750 | AI LN |
| **R01AR074096** | Monitoring Disease in Lupus | NIAMS | UH | **PI** | 2019–2026 | $4,512,261 | LN biomarker monitoring |
| **R01AR072598** | A B-Cell Gene for Lupus | NIAMS | UH | **PI** | 2018–2022 | $2,031,550 | Lupus B-cell genetics |
| **R01AR072742** | Novel Point-of-Care assays for Urinary Diagnostics of Nephritis | NIAMS | UH | **co-I / MPI** (Contact: Willson) | 2017–2020 | $1,338,723 | POC urine diagnostics |
| **R21AR072911** | Salivary biomarkers in SLE | NIAMS | UH | **PI** | 2017–2018 | $386,599 | Saliva biomarkers |
| **R01AR055600** | Lupus Genes and B-Cell Signaling | NIAMS | UTSW | **PI** | 2009–2013 | $1,578,759 | Lupus genetics |
| **R01DK081872** | Foreboding Lupus Nephritis in Minority Women | NIDDK | UTSW | **PI** | 2009–2013 | $2,353,477 | LN in minority women |
| **R21AT004436** | Ayurvedic Alternatives in Autoimmunity | NCCIH | UTSW | **PI** | 2009–2010 | $429,788 | CAM/autoimmunity |
| **P50AR055503** | (Lupus SLE Center — Administrative Core) | NIAMS | UTSW | **PI (Core)** | 2007–2011 | $4,211,894 | Lupus center core |
| **P01AI039824** | Candidate Genes for BXSB Lupus | NIAID | UTSW | **PI** | 2007–2011 | $1,264,742 | Murine lupus genetics |
| **R21AR051642** | Lupus locus Sle3 — innate & adaptive immunity | NIAMS | UTSW | **PI** | 2004–2005 | $312,000 | Lupus locus |
| **R01AR050812** | Immunogenetics — target-organ damage in immune nephritis | NIAMS | UTSW | **PI** | 2003–2012 | $3,120,419 | Immune nephritis genetics |
| **R21AR048410** | Candidate gene analysis in murine lupus | NIAMS | UTSW | **PI** | 2001–2002 | $156,000 | Murine lupus genetics |
| **R01AI047460** | Immunogenetic & cellular origins of nephrophilic ANAs | NIAID | UTSW | **PI** | 1999–2003 | $908,217 | Nephrophilic autoantibodies |
| **R01AR044894** | Impact of lupus susceptibility loci on B-cell tolerance | NIAMS | **UF** | **PI** | 1998–2007 | $2,345,011 | Lupus loci / B-cell tolerance (earliest indep. grant) |

**NIH total captured across all 20 core projects (FYs in RePORTER):** **~$29.77M** (sum of the per-project totals above; = amounts RePORTER exposes, which may not equal total committed cost for every year).

**Currently ACTIVE NIH (end date ≥ 2026):** R01AR086872 (→2031), R01DK134055 (→2028), R01AR074096 (2R renewal →2026+). R21AR082713 ended 2025.

### B2. Non-NIH grants

| Grant # / ID | Title | Agency | Role | Amount | Years | Topic | Source |
|---|---|---|---|---|---|---|---|
| **RP250585** | Cancer Immunotherapy Biomarker Core (CIBC) | **CPRIT** (Texas) | **PI / Project Director** (co-lead: Weiyi Peng) | **$2,999,264** (~$3M) | 2025– | Core-facility targeted proteomics for cancer immunotherapy biomarkers (first in TX) | CPRIT award data via cprit.texas.gov; UH News 05/27/2025 |
| **(TIL award)** | Target Identification in Lupus — ALCAM as therapeutic target in LN | **Lupus Research Alliance** | **PI** | **up to $600,000** | 2018–2021 (3 yr) | ALCAM target validation (underpins the Nat Commun 2020 ALCAM work) | lupusresearch.org (announced Jan 2018) |
| **LRA-BMS Accelerant Award** | (Lupus Research Alliance / Bristol Myers Squibb Accelerant) | LRA + BMS | PI/awardee | Not stated | Not stated | Lupus translational acceleration | UH BME faculty page (award listed; # & amount not verified) |
| **DOD lupus/autoimmunity award(s)** | (unspecified) | **DOD** (likely CDMRP Lupus Research Program) | Likely PI | **Not verified** | Not verified | Lupus | Mohan Lab site lists "NIH, DOD, LRA, CPRIT" as funders — DOD confirmed as a funder but **no specific grant #/amount located**. (A separate DOD Impact Award went to Tianfu Wu, a *different* UH PI — do not attribute to Mohan.) |
| Career/early awards | Arthritis Investigator Award; Burroughs Wellcome Career Award; ACR Kunkel Young Investigator; Clinical Immunology Society New Investigator | Foundations | PI | Not stated | Career-era | Honorific/career funding | UH BME faculty page |

### B3. Grant totals (what we can defend)

- **NIH:** 20 distinct core projects spanning **1998–2031**; ~**$29.8M** captured in RePORTER; **3 active** (2 as sole/contact-PI: R01AR086872, R01DK134055; renewal R01AR074096).
- **Non-NIH quantified:** CPRIT RP250585 **$2.999M** + LRA TIL **$0.6M** = **~$3.6M**.
- **Non-NIH confirmed-but-unquantified:** LRA-BMS Accelerant; DOD/CDMRP; foundation career awards.
- **Grand total (quantified, NIH + CPRIT + LRA TIL):** **~$33.4M** — a **floor**; true career total is higher (DOD, Accelerant, indirect/full-cost years, sub-awards not exposed).

---

## What I could and could NOT verify

**Verified:** All 20 NIH core projects with titles/ICs/roles/FYs/amounts (RePORTER, authoritative). CPRIT RP250585 number + $2,999,264 (CPRIT data). LRA TIL 2018 $600K. The disease/modality/cohort-composition fields for cohort papers (from abstracts). GEO deposits in A7. The verified negative on human SLE GWAS ownership.

**Could NOT verify (flagged, not fabricated):**
1. **Repository accessions** for most cohort papers — abstracts don't state them; need full-text Data Availability statements (esp. urine proteomics, spatial-omics, IBD stool, renal scRNA-seq).
2. **Exact cohort N** for: 42138328, 41031884, 37516396, 31494269, 32540998, several array/metabolomics validation cohorts.
3. **Same-patient multi-omic pairing** for 34783463 / 38194790 — the renal scRNA-seq appears cross-referenced from a possibly separate LN kidney single-cell resource, not necessarily the same urine donors. Marked "Y/unclear."
4. **DOD grant specifics** (number/amount/mechanism) — DOD confirmed as a lab funder but no discrete award located.
5. **LRA-BMS Accelerant** award number/amount.
6. **PMID 33206612** (IEEE JBHI LN-classification) — could not confirm Mohan's UH/UTSW affiliation from XML; likely same group, flagged.
7. **Some pre-2018 DOIs** (parser cross-referencing) — anchored on PMID; marked "(verify)" where reconstructed.
