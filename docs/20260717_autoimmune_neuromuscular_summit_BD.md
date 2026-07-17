# Autoimmune Neuromuscular & Nerve Disorders Drug Development Summit
## Business Development & Collaboration Analysis

**Event:** Autoimmune Neuromuscular & Nerve Disorders Drug Development Summit  
**Date:** July 21–23, 2026 | Boston, MA  
**Focus:** MG, CIDP, GBS, MMN drug development — mechanistic, translational, and clinical  
**Organizer:** Hanson Wade | info@hansonwade.com | +1 617 455 4188  
**Website:** www.autoimmune-neuromuscular-drugdevelopment.com

---

## Priority Contacts

### Tier 1 — Discovery & Translational Biology Heads (Direct BioMate Users)

| Person | Role | Company | Alignment |
|--------|------|---------|-----------|
| **Jessica VanBaaren** | Sr. Scientist & PM, Neuromuscular Translational Biology | UCB | Leads translational multi-omics for neuromuscular — direct user of RNA-seq/pathway workflows |
| **Dina Schneider** | VP & Head of Discovery | Cartesian Therapeutics | CAR-T autoimmune reset startup — needs AI-driven target/biomarker tooling |
| **David Pirman** | SVP & Head of Discovery | Biohaven | Discovery head actively expanding into MG/neuropathies |
| **Ruchi Gupta** | Head of Biomarkers | Gilead Sciences | Running biomarker panel session — transcriptomics pipelines directly support her work |
| **Jeremy Sokolove** | CMO | Vor Biopharma | Upstream B-cell targeting startup; needs computational support for mechanism validation |
| **Salma Merchant / David Ngai** | Biology Research Scientists | Alnylam Pharmaceuticals | siRNA for CIDP; PBPK modelling for spinal/CNS access is directly relevant |

### Tier 2 — Senior Pharma (Budget Authority)

| Person | Role | Company |
|--------|------|---------|
| **Tarek Samad** | SVP & Global Head of Research | Lundbeck |
| **Sanjay Rakhade** | Executive Medical Director, Clinical Development | Alexion (AstraZeneca) |
| **Bianca Balbino** | Senior Clinical Scientist | argenx (efgartigimod — MG market leader) |
| **Delphine Masschaele** | Senior Clinical Scientist | argenx |
| **Martin Kolev** | Director, Complement Science | Apellis Pharmaceuticals |
| **Beatrix Bartok** | VP, Clinical Development | Biogen |
| **Julian Chandler** | Associate Director | Alexion Pharmaceuticals |
| **Tony Shock** | Director | UCB |

### Tier 3 — Academic & CRO Partnership

| Person | Role | Institution |
|--------|------|------------|
| **Richard Blumberg** | Professor of Medicine | Harvard Medical School — FcRn biology, potential research collaboration |
| **James Hickman** | Professor / Founder | University of Central Florida / Hesperos (conference host CRO) — Human-on-a-Chip platform, partnership angle |
| **Thomas Bartlett** | MG Patient Advocate | Amgen — patient-reported outcome & trial design perspective |

---

## BioMate Alignment to Agenda

### Three Agenda Slots That Are Word-for-Word BioMate's Pitch

**Day 2 (July 23), 9:00** — *"Reinventing Target Discovery: Overcoming Model Limitations, Data Gaps & Translational Risk"*
> *"Leverage integrated multi-omics and AI-driven analytics to enable robust pathway analysis and informed hit prioritization"*

This is BioMate's core capability. RNA-seq → DESeq2 → pathway enrichment → target ranking, automated end-to-end via chat prompt. Speaker: Jessica VanBaaren (UCB).

---

**Day 2 (July 23), 10:00** — *"Biomarkers in Heterogeneous Autoimmune Neuropathies: Challenges, Trade-offs & Opportunities"* (argenx)
> *"Disease heterogeneity as the central challenge for biomarker development"*

MG has AChR+, MuSK+, and seronegative subgroups with mechanistically different pathology. BioMate's scRNA-seq (Seurat) and bulk RNA-seq (DESeq2/edgeR) pipelines support subtype stratification from patient samples. This is explicitly called out as "the biggest unresolved challenge" in the agenda.

---

**Pre-Conference Workshop B (July 21)** — *"Bridging In Vitro & In Vivo Preclinical Gaps to Improve & De-Risk Clinical Translation"*
> *"Embedding clinically relevant biomarkers into preclinical assays to improve forward and reverse translation"*  
> *"Align early assay readouts with clinical biomarkers to improve translational relevance and reduce late-stage failure"*

BioMate's ADMET + PBPK workflows close exactly this gap by linking compound properties to expected clinical PK before animal studies. Speakers: David Pirman (Biohaven), Dina Schneider (Cartesian), Salma Merchant (Alnylam).

---

**Day 2 (July 23), 1:30** — *"Roundtable: Anatomical Barriers to Efficacy in CIDP: Targeting the Spine to Unlock Full Disease Control"*
> *"Comparing small molecule approaches, acknowledging that small molecules are uniquely capable of accessing CNS or spinal tissues"*

BioMate's PBPK workflow can model CNS compartment PK and predict spinal penetration for biologics vs. small molecules — directly de-risking the go/no-go decision Alnylam (David Ngai) is presenting on.

---

## BioMate Value Propositions for This Audience

### 1. Patient Stratification in Rare, Heterogeneous Diseases
MG's three serological subtypes (AChR+, MuSK+, seronegative) have different immune mechanisms and treatment response profiles. BioMate can run scRNA-seq clustering and differential expression to identify subtype-specific gene signatures from patient samples — addressing the #1 challenge named throughout the agenda.

### 2. Automated Biomarker Discovery Pipeline
Raw FASTQ → DESeq2/edgeR → pathway enrichment (clusterProfiler/enrichGO) → biomarker candidate ranked list, fully automated. Gilead (Ruchi Gupta) and argenx are actively seeking this capability.

### 3. PBPK for CNS/Spinal Access Prediction
The CIDP sessions focus heavily on inadequate spinal penetration of biologics. BioMate's PBPK workflow models CNS compartment PK and predicts whether a biologic or small molecule reaches target tissue — de-risking modality selection before expensive animal studies.

### 4. Tahoe-100M / Replogle Perturbation Data (Available Now)
BioMate now has in S3:
- **Tahoe-100M** (`s3://knowledge-datasets-1759951976/tahoe-100m/`): 338 GB, 100M single-cell perturbation profiles across human cell lines — largest perturbation atlas available, covering 1,000+ compounds × gene regulatory network responses
- **Replogle-Nadig** (`s3://knowledge-datasets-1759951976/replogle_nadig/`): Genome-wide Perturb-seq on K562/RPE1, 36.3 GB — maps causal gene-to-phenotype relationships at scale

These datasets support immune network analysis, off-target prediction, and mechanism-of-action disambiguation — all directly relevant to the "data gaps" speakers are discussing.

---

## Suggested Conversation Hook

> *"BioMate is an AI-powered biomedical platform — you describe your patient cohort or compound in plain language, and it automatically routes to the right genomics or ADMET workflow, runs it on AWS, and returns annotated findings with a downloadable report. For MG/CIDP work specifically, we've built out RNA-seq subtype stratification, multi-omics pathway integration, and PBPK for CNS compartment access. Happy to show you a 5-minute live demo on your data."*

---

## Strongest Immediate Fit

| Company | Why They're the Best First Meeting |
|---------|-----------------------------------|
| **UCB** (Jessica VanBaaren) | Translational biology PM — decision-maker for computational tools, presenting on exact multi-omics workflow gap BioMate fills |
| **argenx** (Bianca Balbino / Delphine Masschaele) | MG market leader with active biomarker validation need; efgartigimod non-responders are the unsolved problem BioMate's subtype analysis addresses |
| **Cartesian Therapeutics** (Dina Schneider) | Small, well-funded CAR-T autoimmune company; Head of Discovery in the room; doesn't have large internal biomedical data team |
| **Vor Biopharma** (Jeremy Sokolove) | Early-stage, CMO present — outsized openness to platform partnerships vs. established big pharma |
| **Hesperos** (James Hickman) | Conference CRO host — partnership to offer BioMate analysis on top of their Human-on-a-Chip wet lab data creates a combined wet+dry lab offering |

---

## Notes
- Registration deadline for early discount: July 20 (tomorrow)
- Drinks reception + scientific poster session: July 22 evening — best informal networking slot
- Speed networking session: July 22, ~10:00 — structured introductions, prepare a 60-second pitch
- Source PDF: `~/Desktop/business/Autoimmune_Neuromuscular_&_Nerve_Disorders-Drug_Development_Full_Event_Guide.pdf`
