# Conference Demo Playbook — Boston Summit July 21–23, 2026
**Audience:** BD team, scientific staff running live demos  
**Platform:** dev-public.biomate.ai  
**Login:** lifeifei163361@163.com / WpmFixture!2026 (demo account)

---

## How to read this document

Each demo has:
- **Intent** — what the contact actually wants to know
- **Query** — exact text to paste into BioMate chat (copy verbatim)
- **Data** — what input files or identifiers BioMate needs
- **Chain** — which workflows fire, in order
- **Why compelling** — why this demo lands with this specific contact
- **Expected output** — what should appear in the panel and chat

---

## Demo A — "MG Immune Profiling"
**Contacts served:** Jessica VanBaaren (UCB), Dina Schneider (Cartesian), Bianca Balbino (argenx), Jeremy Sokolove (Vor Bio), Sanjay Rakhade (Alexion), Richard Blumberg (Harvard/BWH), Delphine Masschaele (argenx), David Pirman (Biohaven), Thomas Bartlett (Amgen/MGFA) — **9 contacts**

**Pitch:** *"You have PBMC samples from MG patients. Here's what BioMate does with them in one session."*

---

### Step 1 — Single-cell RNA-seq clustering

**Intent:** Profile immune cell populations in PBMC data from MG patients to identify which subsets differ from healthy controls.

**Query (paste exactly):**
```
Run single-cell RNA-seq clustering on PBMC data from myasthenia gravis patients 
versus healthy controls. Identify B cells, T cells, plasma cells, and monocytes. 
I also want to see FcRn expression across the immune subsets.
```

**Data:**
- Best: upload or reference a public MG PBMC h5ad file (GSE142256 — MG patient PBMCs from GEO, 8 patients)
- Fallback for demo: reference the public PBMC 3k 10x demo dataset (`pbmc3k`) — BioMate auto-resolves it
- If no file: BioMate will ask for a file path or GEO accession; provide `GSE142256`

**Chain:**
```
nf-core/scrnaseq
  ├── STARsolo alignment + quantification
  ├── Seurat: normalization → PCA → UMAP → Leiden clustering
  ├── Cell type annotation (marker gene scoring)
  │     B cells: CD19, CD79A, MS4A1
  │     T cells: CD3D, CD3E, CD8A, CD4
  │     Plasma cells: SDC1, CD38, PRDM1, XBP1
  │     Monocytes: CD14, LYZ, FCGR3A
  └── FcRn (FCGRT) expression overlay across clusters
```

**Why compelling:**
- Jessica VanBaaren (UCB): her 13-cycle Phase 3 biobank needs exactly this responder cell profiling
- Bianca Balbino (argenx): needs FcRn expression heterogeneity across B cells/monocytes/DCs for efgartigimod mechanism work
- Dina Schneider (Cartesian): pre-AURORA Phase 3 responder signature from Phase 2b PBMC scRNA-seq
- One command replaces weeks of bioinformatics setup

**Expected output:**
- UMAP plot with 8–12 immune clusters labeled (B naive, B memory, plasma cell, CD4 T, CD8 T, NK, monocyte, DC)
- FcRn expression bar chart: highest in monocytes and DCs, lower in lymphocytes
- Top marker genes per cluster (CSV table)
- Status badge: COMPLETED; After Run tab shows outputs + cluster annotation CSV

---

### Step 2 — Differential expression: responders vs non-responders

**Intent:** Find which genes differ between patients who responded to FcRn inhibitor therapy and those who did not.

**Query (paste exactly):**
```
Run differential expression analysis comparing responders versus non-responders 
in MG patients using DESeq2. The condition column is called "responder". 
Use the cluster labels from the prior scRNA-seq run.
```

**Data:**
- If running from Step 1: BioMate carries the run context; the count matrix from Step 1 feeds Step 2
- If starting fresh: provide a count matrix CSV (gene × sample) with a metadata file containing a `responder` column
- Public example: GSE142256 bulk RNA-seq arm with responder/non-responder labels

**Chain:**
```
nf-core/differentialabundance  (routes to DESeq2)
  ├── Import count matrix + sample metadata
  ├── DESeq2: design formula ~ responder
  ├── Log2 fold change shrinkage (apeglm)
  ├── Volcano plot + MA plot
  └── Ranked gene list (padj < 0.05, |log2FC| > 1)
```

**Why compelling:**
- Delphine Masschaele (argenx): baseline PBMC RNA-seq predicts fixed vs on-demand efgartigimod dosing → this is literally her question
- Jeremy Sokolove (Vor Bio): which BAFF/APRIL immune subgroup within AChR+ drives telitacicept MG-ADL response
- Thomas Bartlett (Amgen/MGFA): predict CD19 depleter vs FcRn inhibitor responders from RNA-seq before first therapy failure

**Expected output:**
- Volcano plot: FcRn pathway genes (FCGRT, FCGR2B) enriched in responder up-direction
- Top 20 DE genes table with padj, log2FC, gene symbol
- Downloadable results CSV

---

### Step 3 — Complement pathway enrichment

**Intent:** Do the DE genes point to complement as a mechanism in non-responders?

**Query (paste exactly):**
```
Run pathway enrichment analysis on the top differentially expressed genes 
from the MG responder comparison. Focus on complement cascade genes: 
C3, C4A, CFH, CFB, C5, CR1, C3AR1, C5AR1, CD55, CD59, SERPING1. 
Use clusterProfiler enrichGO.
```

**Data:** DE gene list from Step 2 (BioMate carries context), or paste gene list directly

**Chain:**
```
clusterprofiler
  ├── Over-representation analysis (ORA / hypergeometric test)
  ├── GO Biological Process: complement activation (GO:0006958), 
  │     complement-mediated cytotoxicity (GO:0001906)
  ├── KEGG: Complement and coagulation cascades (hsa04610)
  └── Bar chart of top enriched terms + gene ratio
```

**Why compelling:**
- Martin Kolev (Apellis→Biogen): C5 variant patient identification; C3 vs C5 pathway dominance from transcriptomics — this is his exact scientific question
- Salma Merchant (Alnylam): complement-CIDP biology and cemdisiran next indication
- Sanjay Rakhade (Alexion): within-AChR+ complement stratification for gefurulimab PREVAIL responder prediction

**Expected output:**
- Enrichment bar chart: GO:0006958 (complement activation) at top with p < 0.01
- Complement gene hit list: C3, C5, CFB, CR1, SERPING1 as top contributors
- Downloadable enrichment table (CSV) with GO term, p-value, gene ratio, hit genes

---

## Demo B — "CD40L Indication Expansion"
**Contact:** Tarek Samad (Lundbeck — becomes EVP Sept 1, 2026)  
**Pitch:** *"You're wondering whether CD40L pathway activation is strong enough in CIDP and GBS to justify expanding from MG. Here's how you answer that in one session."*

---

### Step 1 — GWAS→eQTL→scRNA target chain

**Intent:** Pull genetic evidence for CD40LG across three neuroimmune indications, check whether the GWAS loci have eQTL support in immune cells, and identify which cell types express it most.

**Query (paste exactly):**
```
Analyze CD40L genetic evidence and cell-type expression across myasthenia gravis, 
CIDP, and GBS using the GWAS and eQTL target chain. Target gene is CD40LG (TNFSF5). 
Show me which disease has the strongest genetic support and which immune cell types 
drive the signal.
```

**Data:** No files needed — workflow queries public databases:
- GWAS Catalog (gwas.ebi.ac.uk) for MG/CIDP/GBS loci near CD40LG
- OpenTargets Genetics for colocalizing signals
- GTEx v10 + eQTLGen for eQTL support in whole blood/PBMC
- CellxGene Census for CD40LG cell-type expression across immune subtypes

**Chain:**
```
gwas_scrna_eqtl_target_chain
  ├── Layer 1 — GWAS: significant loci (p < 5e-8) near CD40LG ± 500 kb
  │     per disease: Myasthenia Gravis, CIDP, GBS
  ├── Layer 2 — eQTL colocalization: does the GWAS locus colocalize with
  │     a cis-eQTL for CD40LG in whole blood or PBMC?
  │     (PP4 > 0.5 threshold; GTEx v10 + eQTLGen)
  └── Layer 3 — scRNA cell-type specificity: CD40LG expression across
          B cells, T cells, plasma cells, monocytes, NK cells
          (CellxGene Census: 750,000 human immune cells)
Output: ranked evidence matrix + chain_output.txt narrative
```

**Why compelling for Tarek Samad:**
- CD40L inhibitor in MG has Phase 2 data (Lundbeck/UCB); Tarek is deciding whether CIDP/GBS warrant expansion
- This analysis would take a computational biology team 2–3 weeks; BioMate does it in one run
- He becomes EVP Sept 1 — presenting this kind of evidence-based indication map is the exact language of EVP-level decisions
- The output directly answers "where is the genetic signal strongest?"

**Expected output:**
- `gwas_loci.csv`: GWAS hits per disease, p-values, nearest genes
- `candidate_genes.csv`: genes at loci with eQTL support scores
- `scrna_expression_profile.csv`: CD40LG expression across cell types per disease
- `target_priority_report.json`: ranked evidence matrix with 3-layer score
- `chain_output.txt`: narrative summary — e.g. "MG has strongest genetic signal (3 loci, PP4=0.72 in PBMC); CIDP has 1 eQTL-supported locus; GBS has no genome-wide signal but CD40LG is highly expressed in activated T cells"

---

### Step 2 — CD40L pathway enrichment (optional follow-up)

**Query:**
```
Run pathway enrichment analysis on CD40 signaling genes in MG patient transcriptomics: 
CD40LG, CD40, TRAF2, TRAF5, MAP3K7, NFKB1, TNFRSF5. Show me which downstream 
pathways are activated.
```

**Chain:** `clusterprofiler` → CD40/NF-κB pathway, KEGG TNF signaling

**Expected:** CD40-NF-κB pathway enriched; downstream inflammatory mediators (IL6, IL12, TNF) as secondary hits

---

## Demo C — "IND-Ready Evidence Package"
**Contacts:** Dina Schneider (Cartesian Therapeutics), James Hickman (Hesperos)  
**Pitch:** *"From your Phase 2b data to a citable CTD package — one session."*

---

### Step 1 — ADMET screening

**Intent:** Screen candidate compounds for safety and PK liability before committing to PBPK modeling.

**Query (paste exactly):**
```
Run full ADMET screening on these compounds. Predict hERG, Cmax, BBB penetration, 
DILI risk, and Ames mutagenicity.

SMILES:
CC(=O)Oc1ccccc1C(=O)O
CC12CCC3C(C1CCC2O)CCC4=CC(=O)CCC34C
CN1CCC[C@H]1c2cccnc2
```

**Data:** SMILES strings pasted inline — BioMate accepts them directly

**Chain:**
```
Predict ADMET Properties (AI)
  ├── hERG IC50 prediction (cardiotoxicity flag if IC50 < 1 µM)
  ├── BBB penetration score (CNS accessibility)
  ├── Cmax prediction (oral absorption estimate)
  ├── DILI liability score (hepatotoxicity)
  ├── Ames mutagenicity (genotoxicity)
  └── Lipinski Ro5 + solubility
```

**Why compelling:**
- Dina Schneider (Cartesian): needs pre-IND package for AURORA trial (Q1 2027 topline) — ADMET is the first gate
- James Hickman (Hesperos): their chip-based CTD data is valuable only when combined with computational ADMET/PBPK to make it IND-ready

**Expected output:**
- ADMET results table: all 3 compounds × 6 properties
- Traffic-light color coding: hERG OK/FLAG, DILI OK/FLAG
- Recommendation: which compound(s) proceed to PBPK

---

### Step 2 — PBPK simulation

**Intent:** Model the winning compound's pharmacokinetics to predict human plasma and tissue concentrations for the IND submission.

**Query (paste exactly):**
```
Run PBPK simulation for compound 1 (aspirin, CC(=O)Oc1ccccc1C(=O)O) 
which passed ADMET. Oral dose 325 mg single dose. 
Predict plasma and tissue concentrations over 24 hours for a 70 kg adult.
```

**Chain:**
```
pbpk_simulation
  ├── Physiologically-based 11-compartment model
  │     (blood, liver, kidney, gut, lung, heart, brain, muscle, fat, skin, rest)
  ├── Parameter estimation from molecular weight + logP + pKa + fu,p
  ├── Oral absorption via gut lumen → portal blood
  ├── Hepatic first-pass extraction
  └── NCA: AUC0-24, Cmax, Tmax, t1/2, CL/F
```

**Expected output:**
- PK profile plot: plasma concentration-time curve (Cmax ~30 µg/mL at ~1h for aspirin)
- NCA table: AUC, Cmax, t1/2, Vd
- Multi-tissue overlay: liver vs plasma vs brain concentrations

---

### Step 3 — IND §2.6 narrative + audit export

**Intent:** Generate the §2.6.1 Summary of Pharmacokinetics narrative that goes into the IND CTD, with a signed audit trail.

**Query (paste exactly):**
```
Generate the IND section 2.6.1 pharmacokinetic narrative from the PBPK simulation 
results. Format it for the CTD module 2.6.4 written summary.
```

Then immediately follow with:
```
Export the full audit trail with SHA256-signed manifest and claims index.
```

**Chain:**
```
Step 1: BioMate AI generates §2.6.1 narrative text from PBPK outputs
Step 2: run_audit_export
  ├── SHA256 hash of every output file
  ├── claims_index.json: maps each claim in the narrative to its source output
  ├── cite-as strings per output (e.g., "BioMate PBPK run ID abc123, 2026-07-19")
  └── Signed manifest.json (timestamp + run ID + file hashes)
```

**Why compelling:**
- This is the "last mile" that makes computational data IND-citable
- Dina Schneider: her Phase 2b PBMC data is already analyzed; she needs the CTD package
- James Hickman: Hesperos's chip data + BioMate PBPK + run_audit_export = a complete CRO offering for small biotech clients

**Expected output:**
- §2.6.1 narrative paragraph (400–600 words, clinical language)
- `manifest.json` with SHA256 per file
- `claims_index.json`: {"aspirin Cmax ~30 µg/mL": "pbpk_results/nca_table.csv:row3"}
- Download buttons for manifest + narrative DOCX

---

## Demo D — "Peripheral Nerve PBPK for GalNAc-siRNA"
**Contact:** David Ngai (Alnylam Pharmaceuticals)  
**Pitch:** *"Your published GalNAc-siRNA PBPK covers liver. Here's what the nerve compartment looks like."*

---

**Intent:** Alnylam's published PBPK model for cemdisiran covers liver/kidney but not peripheral nerve. For CIDP, the therapeutic target is the nerve, and blood-nerve barrier (BNB) penetration is unmodeled. David Ngai raised this at the roundtable.

**Query (paste exactly):**
```
Model GalNAc-siRNA distribution to peripheral nerve in a CIDP patient. 
Subcutaneous dose 3 mg/kg. Molecular weight 13,500 Da. 
The blood-nerve barrier in CIDP is compromised — increase BNB permeability 3-fold 
compared to healthy. Show me the nerve-to-plasma AUC ratio and 
what the spinal cord and DRG concentrations look like.
```

**Data:** No files needed — parameters are specified in the query

**Chain:**
```
pbpk_peripheral_nerve
  ├── 10-compartment ODE model (SciPy solve_ivp LSODA)
  │     blood → liver → kidney → muscle → fat
  │     → peripheral nerve → spinal cord → DRG → NMJ → CSF
  ├── Subcutaneous absorption (depot → blood, MW-based ka)
  ├── BNB permeability: Papp = 1e-7 cm/s × 3.0 (CIDP disease modifier)
  ├── Simulation: 672 hours (28 days)
  └── NCA per compartment: AUC, Cmax, nerve:plasma ratio
```

**Why compelling for David Ngai:**
- He specifically mentioned "macrophage metabolic state transitions in CIDP nerve repair" and "PBPK spinal access" at the roundtable — BioMate is answering both
- Alnylam has never modeled peripheral nerve pharmacokinetics for cemdisiran; this demonstrates a gap-filling capability
- The CIDP disease-state modifier (3× BNB permeability) is clinically grounded — inflammatory demyelination disrupts the BNB

**Expected output:**
- Concentration-time curves: plasma vs peripheral nerve vs spinal cord vs DRG
- NCA table per compartment: AUC_nerve, AUC_plasma, ratio = ~0.03–0.05 expected (BNB is still restrictive even with 3× increase)
- BNB penetration class: "Low penetration — nerve:plasma AUC < 0.1"
- Recommendation: what dose increase or formulation change would be needed to achieve therapeutic levels in nerve

---

## Demo E — "CIDP Macrophage Metabolic Profiling"
**Contact:** David Ngai (Alnylam — same conversation as Demo D)  
**Pitch:** *"Your scRNA-seq from CIDP nerve biopsies shows macrophages. Here's which metabolic states they're in and which are failing to make the repair transition."*

**Query (paste exactly):**
```
Analyze macrophage metabolic state transitions in CIDP nerve biopsy scRNA-seq data. 
Identify glycolytic M1-like vs oxidative M2-like macrophages, lipid-associated 
TREM2+ macrophages, and the repair/proliferative subset. 
Compare macrophage subset abundance between CIDP patients and healthy controls.
```

**Data:**
- Ideal: David Ngai's own CIDP nerve biopsy scRNA-seq h5ad file
- Demo fallback: BioMate simulates CIDP vs healthy macrophage profiles (clearly labeled as simulation)

**Chain:**
```
macrophage_metabolic_state_scrna
  ├── Scanpy normalization + log1p transformation
  ├── Leiden clustering (resolution 0.4) on macrophage/monocyte subset
  ├── Metabolic program scoring per cluster:
  │     glycolytic:  HK2, LDHA, PKM, PFKFB3 → M1-glycolytic
  │     oxidative:   SDHA, MDH2, PPARGC1A, IDH2 → M2-oxidative
  │     lipid-assoc: TREM2, LPL, APOE, FABP5 → LAM (lipid-associated)
  │     repair:      VEGFA, TGFB1, ARG1, MKI67 → repair/proliferative
  ├── Pseudotime trajectory: M1-glycolytic → repair pole (diffusion map)
  ├── Differential abundance: CIDP vs healthy per subtype (chi² test)
  └── DE markers per subtype (Wilcoxon)
```

**Why compelling:**
- David Ngai's stated question: "macrophage metabolic state transitions in CIDP nerve repair" — this IS the workflow
- M1-glycolytic macrophages stuck in inflammatory state = why CIDP becomes chronic
- LAM macrophages = TREM2+ myelin-debris scavengers — key to Schwann cell remyelination
- Pseudotime trajectory shows where the repair axis is blocked

**Expected output:**
- Subtype table: M1-glycolytic (25%), M2-oxidative (22.5%), LAM (20%), Repair (16.25%), Transitional (16.25%)
- Differential abundance: M1-glycolytic expanded in CIDP (chi² p < 0.01); Repair depleted in CIDP
- Metabolic score heatmap per subtype
- Pseudotime plot: CIDP cells cluster at early pseudotime (stuck in inflammatory state)
- Clinical interpretation: M1-glycolytic → repair transition is impaired; LAM present (myelin clearance ongoing)

---

## Demo F — "Multi-Omics Responder Stratification"
**Contacts:** Ruchi Gupta (Gilead/Alector), Beatrix Bartok (Biogen/Vividion)

**Pitch:** *"You have RNA-seq and protein biomarker data from the same patients. Here's the cross-modal picture."*

**Query (paste exactly):**
```
Integrate RNA-seq and Olink proteomics data from the same CIDP patients. 
I want to find cross-modal factors that stratify responders from non-responders. 
Focus on complement pathway and B-cell receptor signaling. 
Modalities: RNA-seq count matrix and Olink NPX protein data.
```

**Data:**
- RNA: count matrix (gene × sample TSV)
- Protein: Olink NPX matrix (protein × sample)
- Metadata: sample CSV with `responder` column
- Demo fallback: BioMate simulates matched matrices with known complement signal

**Chain:**
```
rnaseq_proteomics_multiomics_integration  [modalities=rna,protein]
  ├── RNA normalization: VST (log1p of size-factor normalized)
  ├── Protein normalization: log2 + quantile
  ├── Feature selection: top 500 variance features per modality
  ├── MOFA2 joint factor decomposition (10 factors)
  ├── Factor-phenotype AUROC vs responder label
  ├── Pathway enrichment (RNA weights): complement GO:0006958,
  │     FcRn/FCGRT, B-cell receptor GO:0050853, hallmark inflammatory
  └── Per-sample complement activity score (mean of complement gene z-scores)
```

**Why compelling:**
- Ruchi Gupta (Gilead): "transcriptomic mechanistic context layered on protein biomarker data" — literally the MOFA2 integration
- Beatrix Bartok (Biogen): "plasma cell burden profiling to predict felzartamab responders in AChR+/MuSK+/seroneg MG"
- Neither contact has a team doing this — it's a multi-week bioinformatics project compressed to one run

**Expected output:**
- Factor variance plot: 10 factors, Factor 1 explains ~35% cross-modal variance
- Top responder factor: AUROC > 0.70 vs responder label
- Pathway enrichment bar chart: complement activation at top (p < 0.01)
- Complement score box plot: responders lower complement score (consistent with drug mechanism — FcRn inhibitor reduces IgG-driven complement)
- `factor_weights_rna.csv` + `factor_weights_protein.csv` for downstream analysis

**For 3-way combination (Ruchi's follow-up):**
```
Now add the metabolomics data to the integration. 
I also have LC-MS metabolite intensities from the same samples. 
Modalities: RNA-seq, Olink, metabolomics.
```
BioMate re-runs with `modalities=rna,protein,metabolomics` — same workflow, automatic.

---

## Demo G — "Complement Pathway Enrichment"
**Contacts:** Martin Kolev (Apellis→Biogen), Salma Merchant (Alnylam)

**Pitch:** *"Here's whether your patient cohort is C3-dominant or C5-dominant, from RNA-seq alone."*

**Query (paste exactly):**
```
Run pathway enrichment analysis on complement pathway genes from PBMC RNA-seq. 
Include: C1QA, C1QB, C3, C4A, CFH, CFB, C5, CR1, C3AR1, C5AR1, CD55, CD59, SERPING1, CFD.
Test GO:0006958 complement activation and GO:0001906 complement-mediated cytotoxicity.
Use clusterProfiler enrichGO.
```

**Data:** DE gene list from prior RNA-seq run, or paste gene list inline

**Chain:**
```
clusterprofiler
  ├── ORA: Fisher/hypergeometric on complement gene set
  ├── GO BP: GO:0006958 complement activation → hits: C3, C5, CFB, CR1
  │           GO:0001906 complement-mediated cytotoxicity → hits: C5, C5AR1, C9
  ├── KEGG hsa04610: Complement and coagulation cascades
  └── Dot plot + bar chart of enriched terms
```

**Why compelling:**
- Martin Kolev (Apellis→Biogen): gefurulimab targets C5; his question is whether C5 or C3 inhibition is more appropriate for his patient cohort → pathway dominance from transcriptomics answers this
- Salma Merchant (Alnylam): cemdisiran (Factor D / CFD inhibitor) next indication; her question is CFD vs C3 complement arm in CIDP nerve

**Expected output:**
- Enrichment bar chart: GO:0006958 top hit (complement activation, q < 0.01)
- Gene hits: C3, C5, CFB, CFD, CR1, SERPING1 — which are elevated tells you C3 vs C5 arm
- C5-high vs C3-high patient classification possible from FPKM ratios

---

## Quick Reference — Demo Routing

| Contact | Company | Demo | Query keyword | Workflow routed | Confidence |
|---------|---------|------|--------------|-----------------|------------|
| Jessica VanBaaren | UCB | A (scRNA) | "single-cell RNA-seq clustering MG PBMC" | nf-core/scrnaseq | 53 |
| Jeremy Sokolove | Vor Bio | A (DESeq2) | "DESeq2 responders vs non-responders MG" | nf-core/differentialabundance | 66 |
| Martin Kolev | Apellis/Biogen | A (enrichGO) | "pathway enrichment complement genes clusterProfiler" | clusterprofiler | 51 |
| Tarek Samad | Lundbeck | B | "CD40L genetic evidence GWAS eQTL MG CIDP GBS" | gwas_scrna_eqtl_target_chain | 115 |
| Dina Schneider | Cartesian | C (ADMET) | "ADMET screening SMILES hERG BBB" | Predict ADMET Properties | 92 |
| James Hickman | Hesperos | C (audit) | "export audit trail SHA256 manifest IND" | run_audit_export | — |
| David Ngai | Alnylam | D (PBPK) | "GalNAc-siRNA PBPK peripheral nerve CIDP BNB" | pbpk_peripheral_nerve | 158 |
| David Ngai | Alnylam | E (macro) | "macrophage metabolic CIDP TREM2 M1 glycolytic" | macrophage_metabolic_state_scrna | 171 |
| Ruchi Gupta | Gilead | F (multi-omics) | "integrate RNA-seq Olink proteomics MOFA2 complement" | rnaseq_proteomics_multiomics_integration | 86 |
| Beatrix Bartok | Biogen | F (multi-omics) | "multi-omics integration RNA plasma cell responder" | rnaseq_proteomics_multiomics_integration | 80 |
| Salma Merchant | Alnylam | G (complement) | "complement pathway enrichment CIDP clusterProfiler CFD" | clusterprofiler | 51 |

---

## Critical demo rules

1. **Phrase as execution, not research.** "Run the GWAS target chain" → workflow card. "Tell me about CD40L genetics" → text answer. Always start with a verb: Run, Analyze, Integrate, Model, Profile.

2. **The wf-chip appears after the AI text.** After the AI finishes streaming its explanation, a workflow card appears below it. Click "Open in panel" to see the full parameter view.

3. **Data files.** For scRNA demos without real data, say `pbmc3k` or `GSE142256` — BioMate resolves both. For PBPK, parameters are enough (no file needed). For ADMET, paste SMILES inline.

4. **Running on AWS Batch takes 8–15 minutes for scRNA, 2–5 minutes for DESeq2, <2 minutes for PBPK/ADMET.** For live demos, pre-run the scRNA-seq step before the meeting and show the completed results. Do ADMET/PBPK live — they're fast.

5. **The panel must show the correct workflow name** (not "undefined"). If it shows "undefined", the session needs a refresh. This has not been observed since the 2026-07-02 parseActions fix.

6. **Multi-step demos:** After Step 1 completes, the next query in the same chat session carries context. BioMate remembers which workflow just ran and can prefill parameters for the next step from the prior run's outputs.

---

## Gold standard validation datasets (for pre-demo testing)

| Dataset | Accession | Omics | Ground truth to verify | Demo relevant to |
|---------|-----------|-------|------------------------|-----------------|
| MG GWAS+eQTL (Nature Comms 2024) | GCST90093061 | GWAS + eQTL | CTSH in TH2, PP4=0.854 | Demo B (Tarek) |
| MG CFD+CD14+ monocytes (2026) | GSE227835 | scRNA + GWAS | CFD top marker in pathogenic monocytes | Demo G (Martin/Salma) |
| SLE Banchereau 2016 | GSE65391 | RNA + cytokines | IFN signature Factor 1, AUROC > 0.85 | Demo F (Ruchi) |
| CLL MOFA canonical | BloodCancerMultiOmics2017 (R) | RNA + methylation | Factor 1 = IGHV status, AUROC ≈ 0.98 | Methods validation |
| SLE telitacicept | PXD073923 + OMIX014815-01 | Protein + metabolomics | XPNPEP3 AUC=0.891; pyruvate in responders | Demo F (3-way) |
