# BioMate — Texas Target Customer Analysis
**Date:** February 26, 2026 · **Segment:** Texas only · **Confidential**

---

## Selection Methodology

Targets were selected by cross-referencing three signals:

1. **Workflow overlap** — does the lab or organization routinely run analyses that BioMate already handles (RNA-seq, WGS, single-cell, metagenomics, proteomics, ATAC-seq, ChIP-seq, drug discovery, cryo-EM)?
2. **Pipeline pain** — does the org have enough throughput or enough bioinformatics-naive researchers that pipeline setup/debugging is a real bottleneck?
3. **QC governance need** — does the org have clinical, regulatory, or publication reproducibility requirements that BioMate's evidence-graded QC layer directly serves?

**Priority tiers:**
- **A** — Strong workflow overlap + confirmed bioinformatics infrastructure + direct contact available. Outreach within weeks 1–4.
- **B** — Solid overlap, active lab, plausible contact path. Outreach within months 1–3.
- **C** — Emerging infrastructure, indirect fit, or smaller scale. Watch list / warm pipeline.

**Current count:** 45 targets (12 Priority-A, 24 Priority-B, 9 Priority-C). See completeness assessment at end of document.

---

## Priority-A Targets — Detailed Rationale

### 1. UT Southwestern — Lyda Hill Department of Bioinformatics (Dallas)
**Why selected:** Ranked top-5 bioinformatics department nationally. Eight faculty with active multi-omics research spanning RNA-seq, single-cell, drug discovery, clinical genomics, and spatial transcriptomics. Backed by BioHPC — world-class HPC infrastructure that creates exactly the kind of pipeline-configuration overhead BioMate eliminates. Chair Gaudenz Danuser leads a flagship imaging + quantitative biology group; Yang Xie runs the QRBC (Quantitative and Computational Biosciences Center) with strong clinical translation push. QC governance for reproducibility across clinical and publication-grade analyses is a direct need. This is the strongest single academic target in Texas.

**Key contacts:** Gaudenz Danuser (Chair), Yang Xie (QRBC Director), Lin Xu, Jeon Lee, Chao Xing, Xiaowei Zhan.
**Reach:** Cold email + paper citation (reference their published workflows) + ISMB/ECCB conference.

---

### 2. BCM — Human Genome Sequencing Center (Houston)
**Why selected:** One of the founding institutions of the Human Genome Project. 180+ staff, 36,000 sq ft of sequencing infrastructure. Richard Gibbs has been running production-scale genomics since the 1990s; Fritz Sedlazeck is a globally recognized leader in structural variant calling. At this scale, QC automation and batch-run reproducibility are not nice-to-haves — they are operational requirements. BioMate's evidence-graded QC governance and per-run audit logs directly address a center running hundreds of samples per week. WGS, WES, and scRNA-seq are their core workloads.

**Key contacts:** Richard Gibbs (Founder & Director), Fritz Sedlazeck.
**Reach:** TMC networking (they're in the Texas Medical Center), ASHG conference, cold email.

---

### 3. BCM — Quantitative & Computational Biosciences (QCB) Program (Houston)
**Why selected:** Multi-institutional graduate consortium (BCM + Rice + University of Houston + MD Anderson) with a strong drug discovery and translational multi-omics emphasis. This is less a single lab and more an institutional infrastructure play — embedding BioMate into the QCB curriculum would give immediate access to 400+ graduate students who are the next generation of pipeline users. The consortium structure creates a natural multi-institution agreement path.

**Key contacts:** QCB Program Director.
**Reach:** Institutional curriculum integration pitch — not a cold email, a proposal to the program director.

---

### 4. Baylor Genetics — Clinical Genomics Testing (Houston)
**Why selected:** A commercial genomics testing lab spun out of BCM that serves as a CLIA/CAP-certified clinical testing operation. This is the strongest CRO-adjacent target in Texas. Clinical labs have hard compliance requirements: every QC threshold needs to be defensible, every run needs an audit trail. BioMate's evidence-graded QC (GOLD/SILVER/BRONZE cited thresholds) + per-run override logging is purpose-built for this. Their workload includes WGS, WES, prenatal genomics, and cancer genetics — all covered by BioMate. CAP/CLIA accreditation and potential 21 CFR Part 11 path make this an Enterprise-tier opportunity.

**Key contacts:** Medical Director.
**Reach:** BCM network (they share origin), clinical lab associations, cold email.

---

### 5. Igenbio — Genomics for Bioremediation (Houston)
**Why selected:** The single most direct energy-biology convergence target in the database. Igenbio explicitly markets itself as "genome sequencing + analysis for bioremediation acceleration." Their product *is* the metagenomics workflow that BioMate runs: 16S rRNA community profiling, whole-genome sequencing of isolates, and functional gene annotation for hydrocarbon-degrading pathways. This is a potential OEM/white-label play: Igenbio provides the sequencing service, BioMate powers the analysis backend. Energy-sector budgets are larger and stickier than academic lab budgets.

**Key contacts:** Igenbio CEO.
**Reach:** Houston energy-biotech industry network, cold email, potentially LinkedIn direct.

---

### 6. MD Anderson Cancer Center — Bioinformatics & Computational Biology (Houston)
**Why selected:** The top-ranked cancer center in the world by US News. Ken Chen's department runs massive-scale multi-omics pipelines: cancer genomics, immunogenomics, single-cell, spatial transcriptomics. TCGA, CCLE, and similar datasets are part of their standard workflow. Reproducibility at publication scale (and increasingly at clinical trial data integrity scale) is a hard requirement. BioMate's QC governance for RNA-seq, scRNA-seq, WGS, ATAC-seq, ChIP-seq, and proteomics maps directly onto their domain portfolio. High-profile endorsement potential.

**Key contacts:** Ken Chen (Chair).
**Reach:** AACR conference, paper citation (reference their published multi-omics studies), cold email.

---

### 7. NeuroX1 — Generative AI Drug Discovery (Austin)
**Why selected:** An Austin-based AI drug discovery startup focused on neurological disorders. Their core workflow is generative AI for target identification — BioMate's ADMET prediction, pharmacogenomics, proteomics (LC-MS/MS), and molecular docking workflows are the wet-lab validation layer that complements their computational target discovery. This is a startup with a fast decision cycle and technical founders who will understand BioMate's value proposition immediately. Potential co-marketing angle ("from target ID to validated pipeline in one platform").

**Key contacts:** CEO/Co-Founder.
**Reach:** Austin biotech network, LinkedIn, cold email.

---

### 8. Rice University — Treangen Lab (Houston)
**Why selected:** Dr. Todd Treangen is one of the leading metagenomics researchers in the country (GraSSRep, rhea, metagenomic assembly tools). NSF/NIH/CDC funded. The lab sits at the intersection of microbiome science, pathogen surveillance, and environmental genomics — all covered by BioMate's metagenomics workflows. Also relevant to the energy-biology angle: environmental microbiome characterization overlaps with bioremediation use cases. A paper citation approach is strong here — Treangen has published extensively on tools that BioMate integrates.

**Key contacts:** Todd J. Treangen.
**Reach:** Paper citation + cold email. Reference specific tools his lab has published that BioMate wraps.

---

### 9. Texas Medical Center (TMC) — Institutional Umbrella (Houston)
**Why selected:** The largest medical complex in the world: 60+ institutions, 106,000+ employees, $3B+ in annual research spending. This is not a single outreach target — it is a **strategic partnership target**. A deal with TMC Innovation Hub (which runs the TMCx accelerator) could give BioMate access to the entire TMC ecosystem with a single institutional licensing agreement. The TMC3 collaborative research campus ($1.5B) is explicitly designed for industry-academia partnerships. This is the highest-leverage single relationship in the Texas target list.

**Key contacts:** TMC VP of Innovation.
**Reach:** TMC Innovation Hub directly; TMC3 partnership process.

---

### 10. UT Southwestern — Simmons Comprehensive Cancer Center (Dallas)
**Why selected:** NCI-designated comprehensive cancer center, closely linked to the Lyda Hill Bioinformatics Department. Translational genomics for clinical trial data integrity is a hard requirement at NCI-designated centers. BioMate's audit trail + QC governance directly addresses the reproducibility standards that NCI requires for cancer genomics submitted to databases like dbGaP and GEO. RNA-seq, scRNA-seq, WGS, ATAC-seq, and proteomics are all active workloads.

**Key contacts:** Carlos Arteaga (Director).
**Reach:** AACR, clinical genomics networks, Dallas bioinformatics community (via UTSW Lyda Hill connection).

---

### 11. UTHealth — McWilliams School of Biomedical Informatics (Houston)
**Why selected:** The only institution in Texas offering an advanced doctoral degree in biomedical informatics. 130+ faculty, 400+ graduate students. Located inside the Texas Medical Center. This is simultaneously a research target (faculty running pipelines) and a curriculum integration opportunity (students learning bioinformatics tools). BioMate embedded in their graduate training would create a pipeline of users who carry the tool into their careers. Strong AI + health data science emphasis aligns with BioMate's positioning.

**Key contacts:** School Dean (sbmi@uth.tmc.edu).
**Reach:** Institutional proposal for curriculum integration + faculty cold email.

---

### 12. ARPA-H Dallas Hub — Biomedical Innovation Ecosystem (Dallas)
**Why selected:** One of three national ARPA-H (Advanced Research Projects Agency for Health) hubs, part of a $2.5B federal biomedical innovation program. The Dallas hub represents an entire funded ecosystem of startups, academic partners, and translational research programs. A partnership with the hub director positions BioMate as the default bioinformatics execution tool for ARPA-H-funded projects in Texas. This is a federal partnership play, not a single-user sale — the leverage is enormous. ARPA-H's focus on cancer, Alzheimer's, and precision medicine maps directly to BioMate's strongest workflows.

**Key contacts:** Hub Director.
**Reach:** Federal partnership process, ARPA-H program manager networks.

---

## Priority-B Targets — Summary Rationale

| Target | City | Why B not A | Key Workflow Fit |
|---|---|---|---|
| Baylor Scott & White — Precision Medicine | Dallas | Large health system, slower procurement, less direct bioinformatics infrastructure than BCM or UTSW | Clinical WGS, pharmacogenomics |
| Children's Medical Center Dallas | Dallas | Rare disease genomics is active but bioinformatics infrastructure less confirmed than Texas Children's Houston | WGS, WES, variant calling |
| Colossal Biosciences | Austin | High-profile but CRISPR/de-extinction focus requires custom workflow validation; no confirmed bioinformatics lead | Comparative WGS, variant calling |
| ExxonMobil — Advanced Biofuels | Houston | $600M algae program, but paused commercialization 2023; research continues but decision cycle is long | Multi-omics strain optimization |
| GENAC (San Antonio) | San Antonio | Strong genomics + neurobiology + aging fit but smaller organization | RNA-seq, scRNA-seq, drug discovery |
| Houston Methodist Research | Houston | Part of TMC but less dedicated bioinformatics than BCM or MD Anderson | Proteomics, translational genomics |
| ImmunoMet Therapeutics | Houston | Cancer metabolism + multi-omics fit; early-stage startup | RNA-seq, proteomics |
| Mirna Therapeutics | Austin | Small-RNA-seq and functional genomics directly relevant; smaller org | small-RNA-seq, RNA-seq |
| Nanoscope Therapeutics | Dallas | Gene therapy + multi-modal genomics; smaller org | RNA-seq, WGS |
| Rice University AI2Health | Houston | Structural biology + phylogenomics + drug design; complements Treangen Lab | Protein structure, molecular docking |
| Salarius Pharmaceuticals | Houston | Epigenetic oncology with ChIP-seq / ATAC-seq workload exactly matching BioMate; small-cap listed | ChIP-seq, ATAC-seq, drug discovery |
| TAMU AgriLife Genomics Core | College Station | Service core with high throughput; QC automation relevant but less research-focused | RNA-seq, WGS, metagenomics |
| TAMU Galveston Microalgae Lab | Galveston | Long-chain hydrocarbon biosynthesis for biofuels; energy-linked; smaller unit | RNA-seq, WGS |
| TAMU — TIGSS + Joshua Yuan | College Station | World record algae productivity; synthetic biology + genomics; Dr. Yuan is energy-biology keystone figure | RNA-seq, metagenomics, functional annotation |
| TAMU — MEOR Research | College Station | 16S rRNA metagenomics for petroleum reservoir microbiomes; direct BioMate fit; niche audience | Metagenomics, 16S rRNA |
| Texas Biotech Inc. | Houston | Recombinant enzyme design for petrochemical cleanup; proteomics + WGS fit | WGS, proteomics |
| Advanced Microbial Solutions | Houston | Petroleum site bioremediation across 5 states; metagenomics characterization fit | Metagenomics, 16S rRNA |
| Texas Children's Hospital (NRI) | Houston | BCM/Texas Children's rare disease + neurogenomics; Huda Zoghbi is a renowned PI | WGS, WES, scRNA |
| UT Austin CCBB | Austin | Deep learning for structure + drug design; Claus Wilke and Edward Marcotte are senior PIs | Proteomics, protein structure |
| UT Austin UTEX Algae | Austin | World's largest algae collection; Hal Alper metabolic engineering; biofuels energy link | RNA-seq, metagenomics |
| UT Dallas Genome Center | Dallas | 10x Genomics + NextSeq 2000 installed; Michael Q. Zhang (SEQLOGO, cis-regulatory elements) is a senior PI | ATAC-seq, ChIP-seq, scRNA |
| UTMB Galveston BGL | Galveston | $10M+ DHS/DTRA funded; novel pathogen detection + environmental microbiome | Metagenomics, WGS |
| University of Houston Bioinformatics | Houston | BCM/Rice/UH consortium member; growing infrastructure | RNA-seq, WGS |
| XBiotech | Austin | Natural human antibody discovery; proteomics + immunophenotyping | Proteomics, RNA-seq |

---

## Priority-C Targets — Summary Rationale

| Target | City | Why C | Notes |
|---|---|---|---|
| Drylet | Houston | Venture-backed wastewater bioremediation; metagenomics fit but smaller R&D team | Watch for growth |
| ETEC Inc. | Houston | Environmental remediation services; basic metagenomics workload | Low R&D depth |
| Gameto | Austin | Single-cell + organoids for ovarian aging; relevant but early-stage | Possible after scRNA workflows showcased |
| GenPrex | Austin | TUSC2 gene therapy for lung cancer; basic genomics workload | Low bioinformatics priority |
| St. Mary's MS Medical Genomics | San Antonio | Program launching Fall 2026; no existing students yet | Excellent curriculum integration play at founding stage |
| Texas Pharmacogenomics Consulting | Dallas | Niche consultancy; CYP2D6/TPMT/DPYD variant interpretation fit | Good fit but tiny org |
| Texas Tech UHSC Genomics | Lubbock | West Texas hub; growing infrastructure; pharmacogenomics angle | Geographic gap filler |
| UT Health San Antonio | San Antonio | Precision medicine + clinical genomics; slower procurement | Clinical QC angle |
| UTSA Wang Lab | San Antonio | Computational microbial genomics; small lab, good early adopter profile | Could be quick win |

---

## Completeness Assessment

### What Is Well-Covered

The current list is comprehensive for:
- **Houston TMC cluster** — BCM HGSC, MD Anderson, UTHealth McWilliams, Texas Children's, Houston Methodist, TMC umbrella, Baylor Genetics. This is near-complete coverage of the world's largest medical complex.
- **Dallas academic** — UTSW Lyda Hill Bioinformatics, Simmons Cancer Center, BSW Health, UT Dallas, Children's Medical Center, Nanoscope, ARPA-H Hub.
- **Austin biotech** — NeuroX1, Colossal, XBiotech, Mirna, GenPrex, Gameto, UT Austin CCBB, UTEX.
- **Energy-biology niche** — Igenbio, Texas Biotech, Advanced Microbial, Drylet, ETEC, ExxonMobil, TAMU MEOR, TAMUG Microalgae, UTEX Algae.

---

### Notable Gaps — Recommended Additions

The following targets are missing and should be considered for the database:

#### High Priority Gaps (should be Priority B or A)

**1. Dell Medical School — UT Austin (Austin)**
UT Austin's medical school, opened 2016, has grown a precision medicine and genomics research program independent from CCBB. Focus on population health, clinical trials, and health disparities genomics. Located adjacent to the Austin biotech corridor. *Add as Priority B.*

**2. Texas Biomedical Research Institute — TBRI (San Antonio)**
A $100M+/year research center (formerly Southwest Foundation for Biomedical Research). Specializes in infectious disease genomics, comparative genomics using non-human primate models, and virology. Substantial sequencing infrastructure. One of the most significant standalone biomedical research institutes in Texas that is not part of a university. *Add as Priority B.*

**3. University of North Texas Health Science Center — Fort Worth**
UNTHSC runs a nationally recognized forensic genetics program and is building out pharmacogenomics and health disparities genomics. They operate a DNA identity laboratory and have clinical sequencing programs. Fort Worth is an underrepresented city in the current list (only Dallas is covered in the north Texas region). *Add as Priority B.*

**4. The University of Texas MD Anderson — Proteomics and Metabolomics Core**
The current MD Anderson entry covers Bioinformatics & Computational Biology (Ken Chen's department). The separate MD Anderson Proteomics and Metabolomics Core Facility is a distinct outreach target — it is an active service core with its own users and QC requirements. BioMate's LC-MS/MS proteomics workflows and MaxQuant/DIA-NN integration make this a direct fit. *Add as Priority B, separate entry.*

**5. AstraZeneca — Innovation Hub at TMC3 (Houston)**
AstraZeneca opened an innovation hub at TMC3 (Texas Medical Center's research complex) as part of their BioHub network. They explicitly co-invest in early-stage companies and run internal genomics R&D. An enterprise deal with AstraZeneca's TMC hub would have global reach. *Add as Priority B.*

**6. Texas Heart Institute (Houston)**
A standalone research institute at the Texas Medical Center focused on cardiovascular disease. Runs RNA-seq, WGS, and single-cell genomics for cardiac research. Not covered under the TMC umbrella entry because they have independent procurement. *Add as Priority B.*

**7. Thermo Fisher Scientific R&D — Austin**
Thermo Fisher has significant R&D operations in Austin (legacy Life Technologies). They develop sequencing reagents and run internal genomics QC. A partnership/integration angle (BioMate as an analysis layer on top of Ion Torrent / NovaSeq data) is worth exploring. *Add as Priority C (long-term partnership).*

#### Lower Priority Gaps

**8. University of Texas Rio Grande Valley (UTRGV) — Edinburg/Brownsville**
Growing genomics program focused on Hispanic health disparities. Underrepresented population genomics is a growing field. Lower near-term BioMate revenue potential but important for geographic completeness. *Add as Priority C.*

**9. Baylor University — Waco**
Biomedical sciences department with some computational biology. Smaller research footprint than BCM or UT. *Add as Priority C.*

**10. Texas Southern University (Houston) / Prairie View A&M**
HBCUs with growing STEM programs. Limited bioinformatics infrastructure currently, but important for equity-focused outreach and potential federal grant angles (NIH BUILD, RCMI programs). *Add as Priority C.*

**11. Memorial Hermann — Clinical Genomics (Houston)**
One of the largest hospital systems in Houston (17 hospitals), part of TMC. Running clinical genomics for cancer and rare disease. Separate entry from the TMC umbrella because they have independent clinical lab procurement. *Add as Priority B.*

**12. Cook Children's Health Care System (Fort Worth)**
Pediatric rare disease genomics program in Fort Worth. Similar profile to Children's Medical Center Dallas but independent. *Add as Priority C.*

---

### Summary of Completeness

| Area | Current Coverage | Assessment |
|---|---|---|
| Houston TMC academic | BCM, MD Anderson, UTHealth, Rice, UH | **Strong** — add MD Anderson Proteomics Core and Memorial Hermann |
| Houston medical centers | TMC umbrella, Houston Methodist, Texas Children's, Baylor Genetics | **Good** — add Texas Heart Institute |
| Houston energy-biotech | Igenbio, Texas Biotech, Advanced Microbial, Drylet, ExxonMobil | **Strong** — market niche well covered |
| Dallas | UTSW, Simmons, BSW, Children's Medical, UT Dallas, ARPA-H | **Good** — add UNTHSC Fort Worth |
| Austin | CCBB, UTEX, NeuroX1, Colossal, XBiotech, Mirna, Gameto, GenPrex | **Strong** — add Dell Medical School |
| San Antonio | UTSA, UT Health SA, St. Mary's, GENAC | **Moderate** — add TBRI (major omission) |
| College Station / Galveston | TAMU TIGSS, AgriLife, MEOR, TAMUG | **Good** |
| West/South Texas | TTUHSC, UTRGV | **Weak** — low priority but geographic gaps |
| Corporate/pharma | ExxonMobil, AstraZeneca missing, Thermo Fisher | **Weak** — add AstraZeneca TMC Hub |

**All gaps have been added to `texas_targets.json`.** Total list is now **63 targets (13-A / 36-B / 14-C)**.

The 12 additions were:
1. **Texas Biomedical Research Institute, San Antonio** [B] — major standalone institute, infectious disease + comparative genomics
2. **Dell Medical School, UT Austin** [B] — precision medicine, clinical genomics, Austin corridor
3. **UNTHSC Fort Worth** [B] — forensic genetics, pharmacogenomics, Fort Worth node
4. **MD Anderson Proteomics Core** [B] — distinct from Bioinformatics dept, LC-MS/MS direct fit
5. **Memorial Hermann** [B] — largest Houston health system with independent procurement
6. **Texas Heart Institute** [B] — standalone cardiovascular genomics institute at TMC
7. **AstraZeneca BioHub at TMC3** [B] — enterprise pharma with global BioHub network
8. **UTRGV** [C] — South Texas / Hispanic health disparities genomics
9. **Baylor University** [C] — Central Texas corridor (Waco) geographic gap filler
10. **Texas Southern University** [C] — Houston HBCU, NIH RCMI funding angle
11. **Cook Children's Fort Worth** [C] — pediatric rare disease, independent from CMC Dallas
12. **Thermo Fisher Austin R&D** [C] — long-term platform partnership candidate

**Clinical diagnostic labs (6 added):**
13. **Sonic Healthcare USA, Austin** [A] — US HQ in Austin, top-5 diagnostics company, CAP/CLIA, NGS panels
14. **Quest Diagnostics Texas** [B] — largest US clinical lab, major TX operations, NGS oncology + pharmacogenomics
15. **Labcorp Diagnostics Texas** [B] — clinical diagnostics arm (distinct from Covance/CRO already listed), TX presence
16. **Myriad Genetics** [B] — hereditary cancer + pharmacogenomics, massive TX referral volume from MD Anderson / UTSW
17. **GeneDx** [B] — national leader in pediatric/rare disease WGS, serves TX Children's and Cook Children's
18. **CHRISTUS Health Lab Services, Irving** [B] — Texas-HQ'd Catholic health system, CLIA/CAP clinical genomics at scale

---

## Clinical Diagnostic Labs — Segment Notes

This segment was not in the original list and deserves its own framing. Diagnostic labs are structurally different from academic labs and biotech companies:

**Why they are high-value targets:**
- Run NGS at industrial scale (thousands of samples/week) — QC automation is a hard operational need, not a nice-to-have
- CLIA/CAP certification requires documented, defensible QC thresholds — BioMate's GOLD/SILVER/BRONZE cited evidence tiers are purpose-built for this
- 21 CFR Part 11 audit logs are required for any FDA-regulated testing — BioMate's per-run override logging directly addresses this
- Contract size is Enterprise tier ($500–5,000+/month) with long retention; once embedded in a lab's validation workflow, switching cost is very high

**The critical distinction — Labcorp has two separate businesses:**
- `labcorp-diagnostics-tx-001` (this list) = Labcorp's clinical patient testing division (CLIA/CAP)
- `labcorp-genomics-001` (CRO segment list) = Labcorp Drug Development / Covance = pharma contract research
These are completely different buyers with different budgets, procurement paths, and value propositions.

**Reach strategy for diagnostic labs:**
Cold email alone will not work for large chains (Quest, Labcorp). The right sequence:
1. **Conference presence** — AACC (American Association for Clinical Chemistry) and CAP (College of American Pathologists) annual meetings are where lab directors make vendor decisions
2. **Academic connection** — MD Anderson, UTSW, and Texas Children's refer samples to Quest/Labcorp/GeneDx. A warm introduction from those academic contacts is far more effective than cold outreach
3. **Sonic Healthcare USA is the exception** — Austin HQ means accessible leadership; treat like a local biotech, not a national chain

| Lab | Reach Priority | Best First Step |
|---|---|---|
| Sonic Healthcare USA | Immediate (Austin-based) | Direct cold email to genomics director |
| CHRISTUS Health | Soon (Irving/Dallas-based) | Cold email + Catholic health system networks |
| Quest Diagnostics TX | After conference touchpoint | AACC or CAP meeting → follow-up email |
| Labcorp Diagnostics TX | After conference touchpoint | Same as Quest; via separate buyer from Covance |
| Myriad Genetics | Via academic referral path | MD Anderson / UTSW oncology connection first |
| GeneDx | Via pediatric hospital connection | Texas Children's / Cook Children's referral |

---

## Contact Strategy by Segment

| Segment | Primary Approach | Follow-up |
|---|---|---|
| Academic (A-priority) | Paper citation → email referencing their published work | Follow up with demo invitation after 5–7 days |
| Academic (B-priority) | Cold email with workflow-specific hook | Follow up once; if no reply, conference approach |
| Medical centers | TMC Innovation Hub for Houston cluster; individual cold email for Dallas/SA | Institutional proposal for multi-user licensing |
| Biotech startups | LinkedIn DM + email; Austin founders are accessible | Direct demo; fast decision cycle |
| Energy-adjacent | Email + Houston industry network (Rice, TAMU, HARC contacts) | In-person meeting at AIChE or SPE conference |
| ARPA-H / federal | Official partnership inquiry via hub website | Government procurement pathway |

---

*Full data file: `business/marketing/targets/texas_targets.json`*
*Outreach agent: `python business/marketing/outreach_agent.py --output emails --segment texas --priority A`*
