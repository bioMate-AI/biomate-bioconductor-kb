# Conference BD Contact Profiles
## Autoimmune Neuromuscular & Nerve Disorders Drug Development Summit
**July 21–23, 2026 | Boston, MA**

*Deep-researched profiles for all 17 contacts. Last updated: 2026-07-18.*
*⚠️ = affiliation flag — verify before approaching.*

---

## Quick Priority Matrix

| Priority | Person | Company | Why | BioMate Hook |
|----------|--------|---------|-----|--------------|
| **#1** | Jessica VanBaaren | UCB | Has the mandate + the biobank, no tool | RNA-seq responder stratification |
| **#2** | Dina Schneider | Cartesian | Phase 3 running, zero bioinformatics | scRNA-seq pre-treatment responder signature |
| **#3** | David Pirman | Biohaven | Just promoted EVP, IgG4-MuSK open question | B-cell class-switching profiling |
| **#4** | Jeremy Sokolove | Vor Bio | Multi-omics scientist, Phase 3 gMG, BAFF/APRIL | B-cell/plasma-cell subtype profiling |
| **#5** | Tarek Samad | Lundbeck | EVP R&D in 6 weeks, CD40L neuro expansion | Indication mapping across MG/CIDP/GBS |
| **#6** | Bianca Balbino | argenx | FcRn biology paper, non-responder gap | scRNA-seq FcRn expression profiling |
| **#7** | David Ngai | Alnylam | Macrophage biologist, PBPK CNS gap | Peripheral nerve PBPK + macrophage profiling |
| **#8** | Sanjay Rakhade | Alexion | Genomics biomarker scientist, gefurulimab | Within-AChR+ complement stratification |
| **#9** | Ruchi Gupta ⚠️ | Gilead/Alector | Complement biomarker, heterogeneity talk | Transcriptomics + protein multi-modal |
| **#10** | Beatrix Bartok ⚠️ | Biogen/Vividion | Felzartamab MG expansion, precision medicine | Plasma cell burden from scRNA-seq |
| **#11** | Martin Kolev ⚠️ | Apellis→Biogen | Programs being cut, C3 biology expert | C5-variant responder identification |
| Scientific | Tony Shock | UCB | rozanolixizumab architect, 20+ yrs | Engage intellectually → points to Jessica |
| Scientific | James Hickman | Hesperos | Joint CRO offering for smaller biotechs | Wet+dry reporting for their clients |
| Pending ⚠️ | Richard Blumberg | Harvard | FcRn biology lab | FcRn tissue expression profiling |
| Pending | Thomas Bartlett | Amgen/MGFA | Patient advocate | Trial design / endpoint education |

---

---

# TIER 1 — Discovery & Translational Biology Heads

---

## 1. Jessica VanBaaren — UCB
**Sr. Scientist & Project Manager, Neuromuscular Translational Biology | Cambridge, MA**

### Background
Dual-hat role: bench science + cross-functional project management across UCB's MG/neuromuscular translational portfolio. Based at UCB's US research hub in Cambridge. No first-author publications (role is program-delivery facing, not primary-author academic). UCB is actively building this function — multiple Sr./Principal Scientist Translational Muscle Biology hires in 2025-2026.

### UCB's MG Pipeline
| Drug | Mechanism | Status | Subtype |
|------|-----------|--------|---------|
| Rozanolixizumab (RYSTIGGO) | Anti-FcRn → ↓IgG | FDA approved | AChR+ and MuSK+ |
| Zilucoplan (ZILBRYSQ) | Complement C5 inhibitor | FDA approved | AChR+ only |
| Rozanolixizumab + ocular MG | Same | Phase 3 (NCT07463521) | Ocular — NEW 2026 |

**13-cycle durability data just presented at ICNMD 2026.** Variable responder profiles across AChR+ and MuSK+ subtypes are accumulating in UCB's biobank.

### Pain Points She Has Right Now
- Characterizing the non-responder tail across 13 treatment cycles of rozanolixizumab
- Mechanistic explanation for MuSK+ vs AChR+ response divergence (FcRn works for both; complement only for AChR+ — why? No transcriptomic explanation published)
- Building the stratification hypothesis that informs Phase 3b design for the ocular MG study
- No bioinformatics pipeline to turn clinical biosamples (PBMCs, serum) into a ranked biomarker candidate list at throughput

### BioMate Hook
UCB's biobank has rich Phase 3 samples. BioMate can run DESeq2 differential expression + scRNA-seq immune cell subtype analysis on PBMC RNA from responder vs non-responder arms → ranked biomarker candidates annotated by immune pathway → downloadable findings report. Single workflow, chat prompt to AWS. This is the bottleneck tool her translational PM role requires and she doesn't have in-house.

### Opening Line
> *"You're running translational work across two approved MG drugs with very different mechanisms — and the non-responder tail is still uncharacterized. Are you using transcriptomics to stratify the clinical responder data, or is that still in the discovery queue?"*

**Follow-up if she engages:** *"We built a pipeline at BioMate that runs single-cell immune profiling from PBMC RNA directly — you'd have a responder vs non-responder pathway map back in hours. Happy to demo on your published sample types."*

---

## 2. Dina Schneider — Cartesian Therapeutics
**VP & Head of Discovery**

### Background
- PhD-level scientist; Hebrew University → Michigan State → U Michigan
- Lentigen Technology/Miltenyi Biotec (founding member CAR-T R&D, Director I-O & Cell Therapy, led 3 products to clinical trials)
- Cartesian (joined ~2022–2023)
- Published: Science Translational Medicine — trispecific CAR-T; armored BCMA CAR-T for TGF-β environments

### Cartesian Pipeline (2026)
| Program | Stage | Notes |
|---------|-------|-------|
| Descartes-08 (anti-BCMA mRNA CAR-T) — gMG AChR+ | **Phase 3 AURORA** | ~100 pts; topline Q1 2027; FDA SPA; $150M non-dilutive financing secured May 2026 |
| Descartes-08 — Myositis (DM/antisynthetase) | Phase 2 | IND accepted; seamless adaptive design; 1H 2026 |
| Descartes-08 — Pediatric JDM | Phase 1/2 | First participant enrolled |
| In vivo mRNA CAR-T (WestGene deal) | Phase 1 planned | gMG; start 2H 2026; data 1H 2027 |

**Key differentiator:** Autologous anti-BCMA mRNA CAR-T, 6 outpatient weekly infusions, NO lymphodepletion. Company: ~75-89 employees. **Effectively zero in-house bioinformatics.**

### Landmark Paper to Reference
**Nature Medicine, January 2026** — "BCMA-directed mRNA CAR-T cell therapy for myasthenia gravis: exploratory biomarker analysis of a placebo-controlled phase 2b trial"
- Descartes-08 selectively eliminates BCMA-high plasma cells + remodels autoreactive B-cell repertoire
- Does NOT eliminate protective immunity (no hypogammaglobulinemia)
- Phase 2b: 66.7% ≥5-point MGC improvement vs 27.3% placebo (p=0.047)
- Computational work done by external academic collaborators — not in-house

### Open Questions She Is Working On
1. Non-responder profiling (~30% Phase 2b non-responders) — what distinguishes them pre-treatment?
2. Myositis subtype stratification: anti-Jo1, anti-MDA5, anti-Mi-2 have different mechanisms — does BCMA depletion work across all?
3. Pre-treatment transcriptomic signature to enrich Phase 3b population
4. In vivo vs ex vivo CAR-T immune remodeling equivalence (scRNA-seq comparison)

### BioMate Hook
Cartesian has rich Phase 2b immune profiling data (FACS + proteomics + B-cell repertoire) and Phase 3 running. They need a pre-treatment responder signature before Q1 2027 data readout. BioMate's scRNA-seq (Seurat) + multi-omics integration + pathway enrichment closes that gap without a bioinformatics hire.

### Opening Line
> *"Congratulations on the Nature Medicine biomarker paper — the precision BCMA-high selectivity is a remarkable mechanism story. With AURORA running and myositis starting in parallel, are you building a pre-treatment transcriptomic responder signature from the Phase 2b samples? We run automated single-cell profiling on AWS with no bioinformatics team required — could have a responder vs non-responder pathway map back to you before Q1 2027."*

---

## 3. David Pirman — Biohaven
**EVP & Head of Discovery** *(promoted from SVP effective July 13, 2026 — he is 8 days into this role at the conference)*

### Background
- Agios Pharmaceuticals: Director, Head of Metabolism & Proteomics (through Aug 2022) — drove IDH inhibitor and pyruvate kinase activator programs
- Biohaven: VP Biology & Biochemistry (Aug 2022) → SVP Head of Discovery (Jan 2025) → **EVP Head of Discovery (Jul 2026)**
- Scientific identity: metabolomics, metabolic phenotyping, proteomics (LC-HRMS stable isotope tracing, protein degradation). Not historically a transcriptomics/bioinformatics person. 20+ publications, 1,565 citations.

### Biohaven's MoDE Platform & Pipeline
**MoDE (Molecular Degraders of Extracellular Proteins):** bispecific molecules that capture pathogenic extracellular proteins and route them to the liver for lysosomal destruction.

| Asset | Target | Indication | Stage |
|-------|--------|------------|-------|
| BHV-1300 | Pan-IgG MoDE | Graves' disease + MG follow-on | Phase 3 initiation mid-2026 |
| BHV-1310 | Bispecific degrader | MG (acute), IgA nephropathy | Phase 1; AAN 2025: rapid IgG depletion |
| **BHV-1450** | **IgG4-specific MoDE** | **MuSK-MG**, pemphigus vulgaris | Early; IND-stage |

**BHV-1300 Phase 3 data:** >80% mean reduction in TSHR-IgG1 by week 12 in Graves' hyperthyroidism patients.

### The Open Scientific Problem BHV-1450 Creates
BHV-1450 is IgG4-specific. Anti-MuSK antibodies are predominantly IgG4 subclass — strategically brilliant. But it immediately raises:
- Who among MuSK-MG patients has predominantly IgG4-switching B-cell activity?
- Which subpopulation has the highest IgG4-class-switched plasma cell burden and would respond most deeply?
- How do you define the biomarker-defined responder population before Phase 2?

Pirman's metabolomics background doesn't cover scRNA-seq B-cell class-switching analysis. **That's the BioMate gap.**

### BioMate Hook
1. **Lead with his language — metabolomics:** BioMate has metabolomics + proteomics integration pipelines. Show you speak his domain before pivoting to transcriptomics.
2. **scRNA-seq B-cell class-switching (Seurat):** Profile IgG subclass transcript quantification from MuSK-MG PBMC data → define IgG4-dominant responder subpopulation for BHV-1450 Phase 2 design.
3. **Target positioning for next MoDE candidates:** `target_evidence_positioning` workflow scores mechanism novelty + competitive crowding before Biohaven commits to a new degrader.

### Opening Line
> *"Congratulations on the EVP promotion — saw the announcement last week. BHV-1450's IgG4 specificity for MuSK-MG is a smart design, but it makes patient stratification the make-or-break question before Phase 2. We can run single-cell B-cell class-switching profiles on MuSK-MG samples to define the IgG4-dominant subpopulation. Takes a chat prompt."*

---

## 4. Ruchi Gupta — Gilead Sciences ⚠️
**Head of Biomarkers (presenting at conference)**

### ⚠️ AFFILIATION FLAG
Most recent traceable role is **Head of Biomarker Discovery & Operations at Alector** (South San Francisco). Conference listing says Gilead. Verify current employer before approaching — may have moved back to Gilead or be at Alector. Her LinkedIn title "Head of Translation" suggests a possible further move. **Confirm before framing the conversation.**

### Background
- IIT Kanpur — M.S. Chemistry (2006–2008)
- AstraZeneca — cardiovascular biomarkers; LOX-1 for MI/heart failure
- Johnson & Johnson — Tau vaccine (Phase 2); Alzheimer's/Parkinson's biomarker panels
- Gilead Sciences — Director level; **neuroimmunology, complement biology, and fibrosis biology** biomarker programs
- Alector — Head of Biomarker Discovery & Operations; TREM2 agonist (AL002) program in early Alzheimer's; 16+ years total

**Important:** Her complement biology work at Gilead maps directly to MG/CIDP mechanisms. She likely left when Gilead deprioritized these programs.

### Her Talk Angle — "Biomarkers in Heterogeneous Autoimmune Neuropathies"
Likely covers:
- Disease heterogeneity as core problem: CIDP no definitive biomarker; MG three serological subgroups; NfL non-specific
- Protein vs. transcriptomic trade-off (she is Quanterix Simoa-adjacent — protein-biomarker-first)
- Complement proteins (C1q, C3b) as mechanistic biomarkers for complement-inhibitor responder subgroup
- How to bridge biomarker discovery to biomarker-stratified trial endpoint

### BioMate Hook
**Do NOT lead with "transcriptomics replaces protein biomarkers."** She is protein-first. Lead with: *transcriptomics adds mechanistic context to her protein readouts.* Multi-omics integration layering bulk RNA-seq pathway analysis onto Simoa protein data is the offer.

Strongest alignment: patient stratification in heterogeneous diseases (scRNA-seq → distinct immune cell clusters in CIDP subtypes or MG serotypes), complement pathway enrichment from blood/nerve biopsy.

### Opening Line
> *"Your talk touches on exactly the gap we keep running into — great protein biomarker data but still not knowing which immune mechanism is driving a given patient's neuropathy. We've built multi-omics integration workflows that layer transcriptomic mechanistic context onto protein readouts — not a replacement, an additional resolution layer. Given your complement biology background, I'd love to show you what that looks like on nerve biopsy data."*

---

## 5. Jeremy Sokolove — Vor Biopharma
**CMO (joined November 2025)**

### Background
- Boston University MD; Rheumatology & Immunology fellowship at Stanford
- Stanford faculty PI: **multi-omics biomarker discovery in autoimmune disease**. Key papers: *"Multi-omic Biomarkers Distinguish Rheumatoid Arthritis in Discordant Monozygotic Twins"* (Nature-level); *"Mechanistic biomarkers for clinical decision making in rheumatic diseases."* 90+ publications, ~12,640 citations.
- AbbVie: Head of Immunology Translational Science
- GSK: SVP Head of Clinical Pharmacology & Experimental Medicine
- Odyssey Therapeutics: CMO
- Roivant Sciences: CMO-in-Residence
- **Vor Bio: CMO (November 2025)**

### The Vor Pivot — Why He's Here
Vor Biopharma was an HSC-engineering leukemia company. In **June 2025**, complete pivot: in-licensed **telitacicept** from RemeGen (China), raised $175M, repositioned entirely as autoimmune/B-cell.

**Telitacicept:** BAFF/APRIL dual fusion protein inhibitor. Blocks both survival cytokines for autoreactive B cells and long-lived plasma cells.

| Program | Indication | Status |
|---------|------------|--------|
| Telitacicept | **gMG (global)** | **Phase 3 UPSTREAM MG** (NCT06456580); ~180 AChR+/MuSK+ pts; topline H1 2027 |
| Telitacicept | Sjögren's | Phase 3 ongoing |
| Telitacicept | IgA nephropathy (China) | NEJM May 2026; approved China |
| Telitacicept | SLE | Approved China |

**China Phase 3 gMG data (AANEM Oct 2025):** 4.83-point MG-ADL improvement; 98.1% achieved ≥3-point response.

### Why Sokolove Resonates with BioMate
He IS the user BioMate is built for. He spent his Stanford career doing what BioMate automates: multiplex arrays, ACPA profiling, RA patient stratification from multi-omics. The pitch: *"The analysis you spent a grant cycle doing at Stanford now runs in a chat prompt."*

**His open questions right now:**
1. Which immune subgroup within AChR+ patients drives the MG-ADL improvement signal?
2. How to differentiate telitacicept (upstream B-cell/plasma-cell depletion) from approved FcRn inhibitors in the same patient who could take either
3. Recruiting into UPSTREAM MG while efgartigimod is already approved and pulling from the same patient pool

### BioMate Hook
- **scRNA-seq B-cell/plasma-cell subpopulation profiling** — identify plasmablast-dominant vs naive B-cell-dominant patients from gMG PBMCs; predict BAFF/APRIL blockade responders
- **Patient recruitment feasibility workflow** — UPSTREAM MG competes with efgartigimod/rozanolixizumab for the same AChR+/MuSK+ patients; BioMate can model competing trial burden
- **DESeq2 responder/non-responder analysis** on baseline/post-treatment paired samples from any available cohort

### Opening Line
> *"Congratulations on the telitacicept pivot — BAFF/APRIL in gMG is a smart mechanism bet against the FcRn field. The question I'd love your take on: does UPSTREAM MG's design let you pull apart which immune subgroup within AChR+ patients drives the MG-ADL response? That stratification story is how you differentiate once efgartigimod is already approved."*

---

## 6. Salma Merchant + David Ngai — Alnylam Pharmaceuticals
**Biology Research Scientists**

### Salma Merchant
Limited public profile. Biology Research Scientist at Alnylam, likely embedded in a neuromuscular or complement program. **Lead with the cemdisiran data and complement-CIDP biology as the conversation entry point.**

### David Ngai
- PhD, University of Toronto
- Postdoc: **Columbia / Ira Tabas Lab** — macrophage immunometabolism, efferocytosis
  - *"PFKFB2-mediated glycolysis promotes lactate-driven continual efferocytosis by macrophages"* — **Nature Metabolism 2023**
  - *"Efferocytosis drives a tryptophan metabolism pathway in macrophages to promote tissue resolution"* — **Nature Metabolism 2024**
- At Alnylam: Scientist, Biology (Cambridge, MA)
- Presenting at: *"Anatomical Barriers to Efficacy in CIDP: Targeting the Spine"* roundtable

### Alnylam's Neuromuscular Pipeline
- **Cemdisiran** (C5 RNAi; Regeneron licensed for commercialization): **Phase 3 NIMBLE positive (August 2025).** 74% complement inhibition as monotherapy; ~99% with pozelimab. BLA filing planned Q1 2026.
- **No confirmed CIDP IND** — complement biology in CIDP is validated (Sanofi riliprubart C1s inhibitor Phase 3) but Alnylam program not public
- **CNS/extrahepatic delivery gap:** GalNAc-siRNA is liver-targeted; peripheral nerve needs C16 intrathecal conjugate. Published WB-PBPK-PD model (Pharmaceutics 2025) covers liver compartments only — **peripheral nerve compartment is unmodeled**

### BioMate Hooks
1. **PBPK extension:** BioMate's PBPK workflow can add the peripheral nerve/spinal compartment modeling layer that Alnylam's published GalNAc model doesn't cover — directly relevant to Ngai's roundtable topic on anatomical barriers in CIDP
2. **scRNA-seq macrophage state profiling:** Ngai's efferocytosis background maps to macrophage-mediated nerve repair after complement-mediated demyelination in CIDP. BioMate can cluster macrophage metabolic states from patient nerve biopsy scRNA-seq data

### Opening Lines
**For David Ngai:**
> *"Your efferocytosis work at the Tabas Lab — the lactate-continual-efferocytosis paper — is exactly the mechanism that drives nerve repair after complement-mediated demyelination in CIDP. We've built scRNA-seq clustering workflows that can profile macrophage metabolic states directly from patient nerve biopsy data. Is the CIDP program looking at biopsy-level immune profiling for patient stratification?"*

**For Salma Merchant (fallback):**
> *"With cemdisiran's Phase 3 NIMBLE data in — nearly 74% complement inhibition as monotherapy — is the team thinking about CIDP next? Complement activation is clearly causal in CIDP nerve biopsy data. We have pathway analysis tools that work directly on nerve biopsy transcriptomics."*

---

---

# TIER 2 — Senior Pharma (Budget Authority)

---

## 7. Tarek Samad — Lundbeck
**SVP & Global Head of Research → EVP Head of R&D (effective September 1, 2026)**

### ⚠️ TIMING FLAG — HIGHEST LEVERAGE WINDOW
He is 6 weeks from becoming Lundbeck's top R&D decision-maker. This conference is the last opportunity to reach him as an approachable research lead before he steps into the EVP role.

### Background
- PhD: Molecular/cellular neurobiology, Louis Pasteur University (Strasbourg) — neurodegeneration
- Harvard/MGH faculty: neuroimmune mechanisms; published Nature, Science, Neuron, JCI (45+ papers)
- Pfizer: Head of Neurodegeneration Research → Head of Neuroinflammation Research
- Sanofi: Head of MS and Neuroimmunology Research (early discovery → Phase 2)
- Immunitas Therapeutics: CSO
- Lundbeck: SVP Global Head of Research (2021) → **EVP Head of R&D (September 1, 2026)**

**Key publication:** Nature 2001 — IL-1β–mediated induction of Cox-2 in the CNS, foundational neuroimmune pain paper. Sustained editorial presence in neuroinflammation through 2025-2026.

### Lundbeck's Neuroimmunology Pipeline
| Program | Target | Indication | Stage |
|---------|--------|-----------|-------|
| **Lu AG22515** | **CD40L blocker** | Thyroid Eye Disease → **neuro-immunological expansion planned** | Phase Ib data at ENDO 2026 |
| Asedebart | Anti-ACTH mAb | Cushing's disease | Phase II |
| Amlenetug | Anti-α-synuclein | Multiple system atrophy | Phase II |
| Bocunebart | Anti-PACAP | Migraine prevention | Phase III |
| Bexicaserin | 5-HT2C super-agonist | Rare epilepsy | Phase III |

### Lundbeck's AI Gap — BioMate's Lane
- **Cradle partnership (June 2026):** AI-guided protein engineering
- **Iambic Therapeutics (2024):** AI-driven small molecule design
- **Zero publicly disclosed AI platform for multi-omics patient data analysis, biomarker discovery, or patient stratification**

All Lundbeck AI investment is on the *design* side. BioMate is the *analysis* side — the missing half.

### BioMate Hook
The CD40L program (Lu AG22515) needs indication expansion evidence beyond TED. BioMate can run multi-omics pathway analysis to map CD40L pathway activation signatures across MG, CIDP, and GBS patient cohorts — exactly the transcriptomic evidence base needed to prioritize the next neuro-immunological indication.

### Opening Line
> *"I saw your CD40L program presented at ENDO — the TED data was interesting, but the neuro-immunological extension case is the more exciting bet. We've built the multi-omics infrastructure to do exactly that kind of indication mapping — run transcriptomics from MG and CIDP patient cohorts through pathway enrichment to see where CD40L signature is strongest. Happy to show you what that looks like in 5 minutes."*

**Note:** He is a keynote-level speaker at this summit and has chaired Hanson Wade neuroimmunology events before. He is easy to identify and approach at the event.

---

## 8. Sanjay Rakhade — Alexion (AstraZeneca)
**Executive Medical Director, Clinical Development**

### Background
- MD, Grant Medical College, University of Bombay; PhD, Wayne State University
- Fellowship/faculty, Boston Children's Hospital & Harvard Medical School — **epileptogenesis** research; used microarray genomics to characterize transcriptional responses and identify seizure biomarkers. Published: *Nature Reviews Neurology*, *Annals of Neurology*, *Journal of Neuroscience*
- Industry: Sarepta Therapeutics (Duchenne MD), Sanofi Genzyme (lysosomal storage, MS), Alexion
- At Alexion: oversees late-stage clinical development in neuromuscular

### Alexion's gMG Pipeline
- **Gefurulimab (ALXN1830):** Dual-binding C5 nanobody, once-weekly SC injection
- **PREVAIL Phase III:** Positive at 26 weeks (1.6-point MG-ADL improvement vs placebo; 260 patients, 20 countries); AAN 2026: 20 presentations, 5 oral, all complement-focused
- Biomarker work in-progress: AChR autoantibody isotype profiling + MAC deposition assays to stratify complement activation level within AChR+

### Key Scientific Problem
Who in AChR+ is truly complement-driven vs. other pathogenic mechanisms (antigenic modulation, AChR blockade)? PREVAIL raises the within-AChR+ stratification question that biomarker titer alone doesn't answer.

### BioMate Hook
His academic background is directly genomics-based biomarker discovery. He will immediately understand the value. scRNA-seq (Seurat) + bulk RNA-seq (DESeq2) on circulating immune cells from gMG patients — stratify complement-high vs complement-low subpopulations within AChR+ cohort.

### Opening Line
> *"You went from epileptogenesis biomarkers at BCH to complement inhibition in gMG — the core problem is the same: who in your AChR+ population is complement-driven? We can run scRNA-seq clustering on patient PBMCs to profile that stratification — same day, chat-driven. Happy to show you."*

---

## 9. Julian Chandler — Alexion Pharmaceuticals
**Associate Director (Research Scientist)**

### Background
- Research Scientist at Alexion, Connecticut
- ResearchGate: 100+ citations; primary focus: **fibrodysplasia ossificans progressiva (FOP)** — progressive heterotopic ossification of skeletal muscle
- Published on: anti-ACVR1 antibody mechanisms, clinical staging of FOP, BMP/ACVR1 pathway signaling, DNAJB4 loss-of-function myopathy

### BioMate Hook
FOP flare vs. quiescent muscle differential expression — BMP/ACVR1 downstream nodes driving ossification. BioMate's pathway enrichment + target evidence positioning (OpenTargets scoring) directly applicable to FOP target validation.

### Opening Line
> *"Your ACVR1 work in FOP — are you profiling gene expression in flare vs quiescent muscle to identify the downstream BMP cascade nodes? BioMate can run DESeq2 pathway enrichment from RNA-seq in minutes on that kind of comparative data."*

---

## 10. Bianca Balbino — argenx
**Senior Clinical Scientist (Translational Lead Neurology)**

### Background
- PhD, Institut Pasteur (Paris) — therapeutic antibody development, allergic diseases
- argenx since February 2020 (~6.5 years)
- Role straddles translational science and clinical: interprets trial data, manages academic collaborators, supports protocol work

### Key Publication
**JCI Insight, May 2024** — *"Differential effects of FcRn antagonists on the subcellular trafficking of FcRn and albumin"*
Mechanistic work showing how different FcRn inhibitors vary in intracellular trafficking effects — implications for albumin preservation vs IgG depletion selectivity. Co-author: *"Impact of antibody Fc engineering on translational pharmacology and safety"* (2025).

### argenx Pipeline
| Asset | Indication | Status |
|-------|------------|--------|
| Efgartigimod (VYVGART Hytrulo) | gMG (AChR+, MuSK+, seronegative) | Approved; seroneg expansion 2026 |
| Efgartigimod | CIDP | Approved (ADHERE data ongoing) |
| **Empasiprubart** | **CIDP, MMN** | **Phase 3** (EMVIGORATE + EMNERGIZE; started fall 2025, readout ~2027) |
| Adimanebart (ARGX-119) | CMS, ALS, SMA | Advancing to registrational for CMS |

**Non-responder hypothesis:** ~20% AChR seronegative have pathogenic IgG without detectable antibody. Even within responders, clinical non-response occurs. Hypothesis: non-responders have IgA, complement-activated, or T-cell-driven disease that FcRn blockade misses — hence empasiprubart (C2) and ARGX-121 (IgA) pipeline. **Baseline transcriptomic stratification for non-responders not yet published.**

### BioMate Hook
scRNA-seq profiling of FcRn expression heterogeneity across immune cell subsets (B-cells, monocytes, dendritic cells) in gMG patient samples — cell-type-resolved view of why FcRn antagonism works differently across patients. Her JCI Insight paper is about subcellular trafficking; the upstream question is which cells drive the difference.

### Opening Line
> *"Your JCI Insight paper on FcRn subcellular trafficking differences was really clarifying — it raises the question of which cell types are actually expressing FcRn at high levels in MG patient tissue. We have a single-cell RNA-seq pipeline that profiles FcRn expression across all immune subsets from patient samples — would that cell-type-resolved view be useful for your translational work?"*

---

## 11. Delphine Masschaele — argenx
**Senior Clinical Scientist**

### Background
- PhD (Belgium/Ghent area — argenx HQ)
- Senior Clinical Scientist focused on trial execution and data readout for efgartigimod studies

### Key Publications
- ADAPT NXT Part A & B: Fixed-cycle vs every-other-week IV efgartigimod dosing in gMG — **Neurology** and **Annals of Clinical and Translational Neurology (April 2025)**
- Co-author: *"Impact of Long-Term IV Efgartigimod on Quality of Life"* (MGFA 2025 poster)

Her published work: making efgartigimod fit patient lives — fixed cycles vs demand-driven dosing. Core clinical science question: who needs which dosing regimen and why?

### BioMate Hook
Baseline gene expression signatures predicting whether a patient will need fixed vs on-demand dosing — turning a scheduling question into a biomarker-driven decision. DESeq2 on baseline PBMC RNA from ADAPT NXT cohort arms.

### Opening Line
> *"The ADAPT NXT dosing data is fascinating — the question of who needs fixed cycles vs EOW almost begs for a baseline biomarker. We run transcriptomic stratification workflows that can identify gene expression signatures predicting dosing response. Have you looked at baseline transcriptomics as a predictor of dosing trajectory?"*

---

## 12. Martin Kolev — Apellis → Biogen ⚠️
**Associate Director, Complement Science**

### ⚠️ CRITICAL CONTEXT: Apellis Acquired by Biogen
**Apellis was acquired by Biogen for $5.6B, closed May 14, 2026.** Biogen is cutting most legacy Apellis research programs. Martin Kolev is in a professionally vulnerable position. **Approach with awareness — do not ask directly about program status.** Best outcome is a warm scientific relationship, not a deal.

### Background
- PhD, Cardiff University (complement immunology)
- Division of Transplant Immunology and Mucosal Biology, King's College London (post-doc)
- 69 publications, 2,978 citations
- Key papers: *"With complements: C3 inhibition in the clinic"* (Immunological Reviews 2023); complement-T cell metabolic crosstalk papers (Immunity 2015, Front Immunol 2017); complosome — intracellular complement (Nature Reviews Nephrology 2023)

### Apellis/Biogen Neuromuscular Status
- **EMPAVELI (pegcetacoplan):** Approved for C3G and IC-MPGN (kidney). No neuromuscular approval.
- **ALS program (MERIDIAN):** Phase 2 — **FAILED and discontinued.** No benefit over placebo.
- **No active MG, CIDP, or GBS programs.**

### The Scientific Hook That Still Works
C5 inhibitors (ravulizumab, eculizumab, zilucoplan) approved in AChR+ gMG — but **~10-15% of patients carry C5 variant (p.Arg885His) that prevents complete terminal complement blockade.** Upstream C3 inhibition (pegcetacoplan) theoretically rescues these patients. Published 2025 case report: ravulizumab-refractory gMG patients responding to different C5 epitope approach. C3 inhibition bypasses C5 variants entirely.

### BioMate Hook
Identifying C5-variant-adjacent patients from transcriptomic complement pathway signatures — profiling C3, CFB, CFD, C4, C5 terminal complex gene expression from patient PBMCs or muscle biopsy to stratify C3 vs C5 pathway dominance. This is the "find the responders before you dose them" analysis that would justify a pegcetacoplan MG program within Biogen.

### Opening Line
> *"I saw your 2023 Immunological Reviews piece on C3 inhibition in the clinic — the data on C5-variant patients who don't respond to ravulizumab is striking. Has Biogen revisited whether pegcetacoplan could rescue that subpopulation in MG? We can profile complement pathway dominance from RNA-seq data — could help identify that responder signature before a trial."*

---

## 13. Beatrix Bartok — Biogen ⚠️
**VP, Clinical Development (conference listing)**

### ⚠️ AFFILIATION FLAG
LinkedIn shows she moved to **Vividion Therapeutics as VP, Clinical Immunology in 2024.** Conference listing says Biogen. Verify current employer before the conversation. Opening line below handles both cases.

### Background
- MD, University of Pécs (Hungary); rheumatology faculty UCSD
- UCSD: independently-funded research lab on RA pathogenesis — fibroblast-like synoviocytes, PI3Kδ as RA target, B-cell biology in autoimmune disease. 21 publications.
- Eli Lilly: Medical Advisor, inflammation
- **Gilead Sciences:** Executive Director, Clinical Development (Inflammation & Respiratory); Rheumatology Disease Area Head
- **Vividion Therapeutics:** VP, Clinical Immunology (joined 2024)

### Biogen's Neuromuscular/Immunology Pipeline (If She's Still There)
| Asset | Mechanism | Indication | Phase |
|-------|-----------|------------|-------|
| **Felzartamab** | Anti-CD38 mAb | **MG, CIDP (planned expansion)** | Ph3 kidney; MG/CIDP named target |
| Litifilimab | Anti-BDCA2, pDC depletion | SLE | Ph3, readout Q4 2026 |
| Dapirolizumab pegol | Anti-CD40L | SLE | Ph3 |

**HI-Bio acquisition (July 2024, $1.15B)** brought felzartamab — Breakthrough Therapy Designation for kidney. Biogen investor materials explicitly name MG and CIDP as felzartamab expansion targets. Anti-CD38 mechanism: depletes long-lived plasma cells producing AChR/MuSK/anti-neurofascin autoantibodies.

### BioMate Hook
Plasma cell burden profiling from scRNA-seq on patient biopsies — predict felzartamab responders within heterogeneous AChR+/MuSK+/seroneg MG population. She built her career on precision patient selection; this is her scientific identity.

### Opening Line
> *"Your felzartamab expansion into MG is the most mechanistically differentiated move in the complement-agnostic space right now — but the AChR/MuSK/seronegative split makes patient selection critical. We've built a plasma cell burden profiling workflow from bulk and single-cell RNA-seq that could support responder prediction for anti-CD38 in heterogeneous autoimmune cohorts."*

*If she's at Vividion:* > *"Vividion's covalent immunology approach needs precision target identification — we have multi-omics target positioning that integrates OpenTargets, ChEMBL, and transcriptomic evidence. Same 5-minute demo offer stands."*

---

---

# TIER 2 — Supporting Contacts

---

## 14. Tony Shock — UCB
**Director**

### Background
- PhD Biochemistry, University of London (1987); post-doc NHLI London
- Celltech (~1987–2004) → UCB (2004, via Celltech acquisition) — **20+ years**
- Scientific architect of **rozanolixizumab**: co-authored the foundational 2018 characterization paper + PK/PD modelling + ITP blockade mechanism paper
- Also: epratuzumab (anti-CD22, SLE), dapirolizumab pegol (anti-CD40L, SLE) — familiar with Phase 3 failures in autoimmunity
- Scientific identity: autoantibody removal — FcRn, B-cell, IgG recycling. Does not publish genomics/multi-omics work.
- **Conference speaker** at this summit; has chaired Hanson Wade neuroimmunology events previously

### BD Strategy
Tony is NOT a computational buyer. He is the scientific patriarch of rozanolixizumab. The right move: engage him intellectually on the companion diagnostic angle ("what's the cellular correlate of IgG functional response?"), get him curious, and **let him introduce you to Jessica VanBaaren** as the person to follow up with.

### Opening Line
> *"Rozanolixizumab clears IgG consistently across patients, but the functional response varies. Have you been able to profile the immune cell composition in responders vs non-responders from the Phase 3 samples — or is the stratification hypothesis still at the antibody-titer level?"*

---

---

# TIER 3 — Academic & CRO Partnership

---

## 15. James Hickman — University of Central Florida / Hesperos
**Professor / Founder | Conference CRO Host**

### Key Facts
- 60-person NIH SBIR-funded wet-lab CRO; no omics/bioinformatics capability
- **NMJ chip data included in Dianthus Therapeutics IND (gMG, Phase II, 2024)** — Dianthus's team did the regulatory packaging, not Hesperos
- Big pharma clients (AZ, Pfizer-tier) have always handled computational analysis themselves — that's why this gap has been invisible for 10 years
- **FDA 2025 Alternative Methods guidance** (FDCA §3601-3612) making chip data IND-eligible more systematically — pulling in smaller biotechs who don't have internal bioinformatics

### Pitch (Joint CRO Offering)
Do NOT pitch "Hesperos needs BioMate." Pitch a **joint offering to their smaller biotech clients:**
> *"Your clients get functional chip data from you and then struggle to turn it into a citable CTD package. BioMate closes that loop — their chip data goes into BioMate, they get an annotated findings report with an audit manifest ready for §2.4 and §2.6. Together we offer a complete wet+dry service smaller biotechs can't assemble alone."*

Revenue-share CRO partnership. Much easier conversation with a professor-founder than "buy our platform."

---

## 16. Richard Blumberg — Harvard Medical School / Brigham and Women's
**Professor of Medicine | Vice Chair for Research, BWH | FcRn Biology Founder**

### Background
MD, Jefferson Medical College; fellowships at MGH, Brigham, Dana-Farber. Holds the Jerry S. Trier endowed chair in Gastroenterology at Brigham and Women's Hospital; Professor at HMS. **Credited as the first to establish FcRn function in adult life.** His mechanistic work directly enabled Factor VIII-Fc and Factor IX-Fc (approved hemophilia treatments) and the entire FcRn inhibitor class for autoimmunity — efgartigimod, rozanolixizumab, nipocalimab all descend from his biology.

**Was CHAIR at the Hanson Wade Fc-Mediated Function Summit 2025** (same organizer as this conference). He knows many attendees well and may be formally involved in the program agenda.

**Research focus:** Mucosal immunity; intestinal IgG transport via FcRn; FcRn role in dendritic cell antigen presentation and cross-presentation; IgG catabolism regulation; IBD; intestinal barrier function. His lab thinks about FcRn as a gatekeeper of immune surveillance across epithelial barriers — foundationally upstream of all FcRn-targeted MG therapies.

### BioMate Hook
His lab's open question on non-responders maps to BioMate's scRNA-seq strength: RNA-seq of FcRn-expressing tissues (intestinal epithelium, vascular endothelium, placenta), transcriptomic profiling of IgG catabolism and recycling pathways, DC antigen presentation pathway enrichment. BioMate could map FcRn expression across cell types and identify transcriptomic signatures of high vs low FcRn activity in patient biopsies — explaining the ~30% who don't respond to FcRn inhibitors.

### Opening Line
> *"Your work establishing FcRn's adult function is what made the whole drug class possible — we've been thinking about how transcriptomic profiling of FcRn-expressing cells could help map which tissues drive the IgG dysregulation in patients who don't respond to FcRn inhibitors. Would that kind of cell-type-resolved map be useful to your lab?"*

---

## 17. Thomas Bartlett — Amgen / MG Patient Advocate
**Patient Advocate supporting UPLIZNA (inebilizumab) gMG launch**

### Background
~20 years at Apple (technology and global sales); Dell; life science consulting applying technology to reduce time-to-medical-outcomes. **Lives with gMG himself** — experienced symptoms >1 year before hospitalization prompted diagnosis. Prior patient engagement roles at argenx, J&J Innovative Medicine, Rare Disease Advisor.

**Current role:** Patient Advocate at Amgen supporting the gMG launch of **UPLIZNA® (inebilizumab-cdon)** — CD19-targeted B-cell depleter, FDA-approved December 2025 for AChR+ and MuSK+ gMG. Amgen's first MG product; he is the on-the-ground patient voice at this conference.

**Most distinctive angle:** Champion of **wearables and textile sensors** for real-time MG symptom data acquisition — predicting and preventing myasthenic crises. Technology-first worldview; sees AI as the bridge between patient experience and clinical endpoints. Receptive to computational tools in a way most patient advocates are not.

**PRO concern:** MG-ADL vs. QMG discordance — patients and clinicians often assess improvement differently. Live advocacy issue.

### BioMate Hook
His technology background makes him the rare patient advocate who will engage on computational biology. The angle: once you have real-time wearable data + RNA-seq from patient samples, can you predict who needs a CD19 depleter (UPLIZNA) vs. FcRn inhibitor before a patient fails their first therapy? BioMate's patient stratification and rare disease power calculator also directly support his advocacy for better-powered trials with patient-meaningful endpoints.

### Opening Line
> *"You've been pushing on wearables for real-time symptom monitoring — we've been thinking about the companion problem: once you have longitudinal functional data plus RNA-seq from patient samples, can you actually predict who needs a CD19 depleter versus an FcRn inhibitor before they fail the first one? That's the responder-stratification question BioMate is set up to answer."*

---

---

# Key Affiliation Flags — Verify Before Conference

| Person | Listed | Possible Actual | Action |
|--------|--------|-----------------|--------|
| Ruchi Gupta | Gilead Sciences | Alector (Head of Biomarker Discovery) | Check LinkedIn before July 21 |
| Beatrix Bartok | Biogen VP | Vividion Therapeutics VP (since 2024) | Check LinkedIn before July 21 |
| Martin Kolev | Apellis | Biogen (via $5.6B acquisition, May 2026) | Confirmed Biogen; programs being cut |
| Julian Chandler | "Associate Director" | Research Scientist (possible title upgrade in programme) | Minor — doesn't change the conversation |

---

# Timing Windows That Won't Come Back

| Opportunity | Why Time-Sensitive |
|-------------|-------------------|
| **Tarek Samad (Lundbeck)** | Last conference before he becomes EVP Head of R&D (Sept 1). He'll be unreachable 6 weeks from now. |
| **David Pirman (Biohaven)** | 8 days into EVP role — he's defining his priorities NOW. |
| **Cartesian (Dina Schneider)** | Phase 3 AURORA topline in Q1 2027 — 6 months to build a pre-treatment responder signature that matters. |
| **Vor Bio (Jeremy Sokolove)** | Phase 3 UPSTREAM MG mid-enrollment — biomarker plan is being written now, not after topline. |

---

# 60-Second Speed Networking Pitch (July 22, ~10:00)

> *"BioMate is an AI-powered biomedical platform — you describe your patient cohort or compound in plain language, it routes automatically to the right genomics or clinical workflow, runs on AWS, and returns annotated findings with a downloadable report. We've built out RNA-seq subtype stratification, scRNA-seq immune cell profiling, PBPK for CNS/peripheral access, and clinical trial design tools specifically for rare autoimmune neuromuscular diseases. For MG work: you send us your Phase 3 PBMC samples, we return a responder vs non-responder pathway map in hours. Happy to do a 5-minute live demo on your data — what's the open biomarker question on your program right now?"*
