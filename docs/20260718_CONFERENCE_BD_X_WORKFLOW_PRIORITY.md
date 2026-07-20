# Conference BD × Workflow Priority — Combined Analysis
**Source 1:** `docs/20260715_WORKFLOW_USECASE_PRIORITIZATION.xlsx`
**Source 2:** `docs/20260718_conference_bd_contact_profiles.md`
**Created:** 2026-07-18 | Conference: July 21–23, 2026

---

## Purpose

Map every conference contact's open scientific question to a specific BioMate workflow capability, its compute tier, and its current build status — so we know exactly what to implement and demo-test before July 21.

---

## Section 1 — Contact → Capability Map

| Contact | Company | Open Question They Have | BioMate Capability | Compute Tier | Build Status |
|---------|---------|------------------------|-------------------|--------------|--------------|
| Jessica VanBaaren | UCB | Responder/non-responder stratification in 13-cycle rozanolixizumab Phase 3 biobank | scRNA-seq immune profiling (Seurat) + DESeq2 responder DE | Medium P2 + Small P1 | nf-core/rnaseq ✅ · scRNA-seq P2 (needs test) · DESeq2 ✅ |
| Tony Shock | UCB | Cellular correlate of IgG response beyond antibody titer | Same as above; influence path to Jessica | Medium P2 | Same |
| Dina Schneider | Cartesian | Pre-treatment responder signature from Phase 2b samples before AURORA Q1 2027 topline | scRNA-seq (Seurat) → B-cell/plasma-cell profiling + pathway enrichment | Medium P2 + GPU P2 | nf-core/scrnaseq ⚠️ needs demo-test |
| David Pirman | Biohaven | IgG4-dominant patient subpopulation for BHV-1450 MuSK-MG Phase 2 design | scRNA-seq B-cell class-switching + metabolomics integration (his language) | Medium P2 + CPU P3 | scRNA-seq ⚠️; metabolomics chain P3 latent |
| Jeremy Sokolove | Vor Bio | Which immune subgroup within AChR+ drives BAFF/APRIL telitacicept MG-ADL response | scRNA-seq B-cell/plasma-cell subtype profiling + DESeq2 paired baseline/post-tx | Small P1 + Medium P2 | DESeq2 ✅; scRNA-seq ⚠️ |
| Ruchi Gupta | Gilead/Alector⚠️ | Transcriptomic mechanistic context layered on protein biomarker data for heterogeneous neuropathies | Multi-omics integration: bulk RNA-seq + clusterProfiler enrichment + complement pathway | Small P1/P2 | DESeq2 ✅; enrichGO ✅; multi-omics chain latent |
| Salma Merchant | Alnylam | Complement-CIDP biology; cemdisiran next indication | Pathway enrichment for complement cascade from blood/nerve biopsy | Small P2 | clusterProfiler/enrichGO ✅ |
| David Ngai | Alnylam | Macrophage metabolic state transitions in CIDP nerve repair; PBPK spinal access | scRNA-seq macrophage clustering + PBPK peripheral nerve compartment extension | Medium P2 + pharmacology chain | scRNA-seq ⚠️; PBPK ✅ (liver); peripheral nerve compartment gap |
| Tarek Samad | Lundbeck | CD40L indication mapping across MG/CIDP/GBS before becoming EVP Sept 1 | GWAS→scRNA→eQTL target-ID chain → CD40L pathway enrichment across disease cohorts | Complex Chain P2 | GWAS→scRNA→eQTL "Proposed" ❌ not built |
| Sanjay Rakhade | Alexion | Within-AChR+ complement stratification; gefurulimab PREVAIL responder prediction | scRNA-seq complement pathway profiling on PBMCs + DESeq2 complement-high vs low | Small P1 + Medium P2 | DESeq2 ✅; scRNA-seq ⚠️ |
| Julian Chandler | Alexion | FOP flare vs quiescent BMP/ACVR1 transcriptomics | DESeq2 flare vs quiescent + pathway enrichment (BMP cascade) + target evidence positioning | Small P1 + P2 | DESeq2 ✅; target_evidence_positioning ✅ |
| Bianca Balbino | argenx | Cell-type-resolved FcRn expression heterogeneity across immune subsets | scRNA-seq (Seurat) FcRn expression profiling across B-cells, monocytes, DCs | Medium P2 | scRNA-seq ⚠️ needs test |
| Delphine Masschaele | argenx | Baseline gene expression predictor of fixed vs on-demand efgartigimod dosing trajectory | DESeq2 on baseline PBMC RNA by dosing cohort arm | Small P1 | DESeq2 ✅ |
| Martin Kolev | Apellis→Biogen⚠️ | C5-variant patient identification; C3 vs C5 pathway dominance from transcriptomics | Complement pathway enrichment (clusterProfiler, C3/CFB/CFD/C5 gene sets) from PBMC RNA | Small P2 | clusterProfiler/enrichGO ✅ |
| Beatrix Bartok | Biogen/Vividion⚠️ | Plasma cell burden profiling to predict felzartamab responders in AChR+/MuSK+/seroneg MG | scRNA-seq plasma cell subset quantification + multi-omics responder prediction | Medium P2 + GPU P2 | scRNA-seq ⚠️; multi-omics chain latent |
| Richard Blumberg | Harvard/BWH | FcRn expression heterogeneity across tissues; transcriptomic non-responder explanation | scRNA-seq FcRn expression mapping across epithelial, vascular, immune cell types | Medium P2 | scRNA-seq ⚠️ |
| Thomas Bartlett | Amgen/MGFA | Predict CD19 depleter vs FcRn inhibitor responders from RNA-seq before first therapy failure | DESeq2 + scRNA-seq responder pre-stratification; rare disease power calculator | Small P1 + Medium P2 | DESeq2 ✅; rare_disease_power_calculator ✅ |
| James Hickman | Hesperos | Turn chip data into citable CTD package for smaller biotech clients | run_audit_export (audit manifest + claims index) + ADMET/PBPK analysis chain | Drug discovery chain | run_audit_export ✅ |

---

## Section 2 — Capability Demand Summary

Ranked by number of contacts who need each capability:

| Rank | Capability | Contacts | Tier | Current Status | Gap to Demo |
|------|-----------|----------|------|---------------|-------------|
| **1** | **scRNA-seq (Seurat) immune cell profiling** | Jessica, Dina, David P, Jeremy, David N, Sanjay, Bianca, Beatrix, Richard — **9 contacts** | Medium P2 | nf-core/scrnaseq in DB ⚠️ needs end-to-end demo test | Test with a real PBMC h5ad dataset; verify Seurat clustering + cell type annotation outputs |
| **2** | **DESeq2 count-matrix DE** | Jessica, Jeremy, Delphine, Sanjay, Julian, Thomas — **6 contacts** | Small P1 | ✅ Implemented | Confirm parameter prefill works for MG use case |
| **3** | **Pathway enrichment (clusterProfiler/enrichGO)** | Tarek, Martin, Ruchi, Salma, Julian — **5 contacts** | Small P2 | ✅ Implemented | Confirm complement gene set enrichment works |
| **4** | **Target evidence positioning** | Julian, David P (next MoDE targets), Tarek (CD40L expansion) — **3 contacts** | Large DB P1 | ✅ Built (this session) | Run smoke test against MG-relevant targets |
| **5** | **Patient recruitment feasibility** | Jeremy (UPSTREAM MG recruiting), Thomas — **2 contacts** | Custom | ✅ Built (this session) | Run smoke test for MG Phase 3 parameters |
| **6** | **Rare disease power calculator** | Thomas, clinical trial design contacts — **2 contacts** | Custom | ✅ Built (this session) | Run smoke test for MG trial scenario |
| **7** | **PBPK (peripheral nerve extension)** | David N (Alnylam) — **1 contact, high specificity** | Medium-pharmacology | Liver compartment ✅; peripheral nerve ❌ not built | Build peripheral nerve/spinal compartment model |
| **8** | **GWAS→scRNA→eQTL target-ID chain** | Tarek (Lundbeck CD40L) — **1 contact, highest BD value** | Complex Chain P2 | ❌ "Proposed" not built | Implement chain; 2-3 days effort |
| **9** | **run_audit_export (regulatory traceability)** | Hickman (Hesperos) | Custom | ✅ Built (this session) | Demo with sample ADMET output |
| **10** | **Metabolomics integration** | David P (Biohaven — his background) | Complex Chain P3 | Latent | Lower priority |

---

## Section 3 — Roadmap Cross-Reference

From `20260715_WORKFLOW_USECASE_PRIORITIZATION.xlsx` Roadmap sheet, mapped to conference BD demand:

| Roadmap Item | Original Priority | BD Demand | Conference Contacts Served | Action |
|-------------|-----------------|-----------|---------------------------|--------|
| Compound-library ADMET fan-out (Batch array) | P1 · Local-tested | High | Cartesian (IND chain), Hesperos clients | **Smoke-test on dev Batch before July 21** |
| Foldseek structure search + AFDB index | P1 · Implemented | Medium | Structural biology; Biohaven next MoDE targets (indirect) | Maintain; not conference-critical |
| Reference-DB lookup cache | P1 · Done 9/9 tests | Supporting | All contacts (enrichment, annotation lookups) | ✅ Already shipped |
| Bioconductor output_types backfill | P1 · Proposed | **Critical** | Unlocks scRNA→Bioc chains needed by 9 contacts | **Start immediately — 1 day effort, unlocks 950+ chains** |
| ADMET→REINVENT4→PBPK→IND §2.6 chain | P1 · Curated flagship | High | Cartesian (pre-IND), Hesperos clients | **Record end-to-end demo run before July 21** |
| FPSim2 chemical-similarity | P1 · Planned | Medium | Biohaven (next MoDE target search) | Post-conference; not blocking |
| Auto-update module CI | P1 · Needs secret | Infra | All | Merge before July 21 if < 1hr |
| Chain planner + PROCEED/REFINE/PIVOT loop | P2 · Dead code | Medium | Cross-specialty chains (Lundbeck, Cartesian) | Post-conference |
| MMseqs2-GPU sequence search | P2 · Planned | Low | Sequence homology; not conference-blocking | Post-conference |
| GWAS→scRNA→eQTL chain | P2 · Proposed | **High (Lundbeck)** | Tarek Samad (EVP in 6 weeks) | **Build this week; highest-value single target** |
| MD fast-modes | P2 · Planned | Low | Not conference-relevant | Post-conference |
| BioEmu protein-ensemble | P2 · Planned | Low | Not conference-relevant | Post-conference |
| Cryo-EM→pocket→screen→ADMET chain | P2 · Proposed | Medium | Structural biology contacts (indirect) | Post-conference |

---

## Section 4 — Demo Scenarios (Conference-Ready)

Three self-contained live demos covering the maximum number of contacts:

### Demo A — "MG Immune Profiling" (covers 9 contacts)
**Pitch:** *"You have PBMC samples from MG patients. Here's what BioMate does with them."*

**Flow in chat:**
1. Upload or reference a PBMC scRNA-seq h5ad file
2. BioMate routes to nf-core/scrnaseq (Seurat clustering + cell type annotation)
3. Returns: UMAP with immune cell populations labeled, top marker genes per cluster, FcRn expression overlay
4. Follow-up DE: DESeq2 on responder vs non-responder labels → ranked biomarker list
5. Pathway enrichment: clusterProfiler on top DE genes → complement/FcRn/B-cell pathway enrichment map

**Contacts this lands for:** Jessica (UCB), Dina (Cartesian), Bianca (argenx), Jeremy (Vor), Sanjay (Alexion), Richard (Harvard), Delphine (argenx — dosing angle), David P (Biohaven — B-cell class-switching), Thomas (Amgen — responder prediction)

**Data needed:** A small public MG PBMC dataset or published GSE. Can use GSE142256 (MG patient PBMCs, GEO) or similar.

---

### Demo B — "CD40L Indication Expansion" (covers Lundbeck + academic)
**Pitch:** *"You're wondering whether CD40L pathway activation is strong enough in CIDP and GBS to justify expanding. Here's how you answer that in one session."*

**Flow in chat:**
1. Input: "Analyze CD40L pathway activation in MG, CIDP, and GBS patient transcriptomics"
2. BioMate routes to: bulk RNA-seq DE (if expression matrix) or pathway enrichment if gene list provided
3. clusterProfiler enrichment against CD40/CD40L signaling gene set across disease cohorts
4. target_evidence_positioning for CD40L → OpenTargets association scores in MG/CIDP/GBS
5. Returns: disease-ranked CD40L pathway activity report + competitive landscape (how many CD40L inhibitors in each indication)

**Contacts this lands for:** Tarek Samad (Lundbeck — his exact decision), Richard Blumberg (academic CD40 biology)

**⚠️ Gap:** GWAS→scRNA→eQTL chain not yet built. For now, demo with target_evidence_positioning + enrichGO. Full chain demo possible post-build.

---

### Demo C — "IND-Ready Evidence Package" (covers Cartesian + Hesperos clients)
**Pitch:** *"From your Phase 2b scRNA-seq data to a citable CTD package — one workflow session."*

**Flow in chat:**
1. Run ADMET → PBPK → REINVENT4 remediation chain (existing flagship demo)
2. Cap with run_audit_export: SHA256-signed manifest, claims_index.json, cite-ready Markdown report
3. Show the §2.4/§2.6 cite-as string generated per output file

**Contacts this lands for:** Dina Schneider (Cartesian — they need this before Q1 2027), James Hickman (Hesperos — joint CRO offering to smaller biotech clients)

---

## Section 5 — Implementation Queue (Before July 21 — 3 Days)

### Day 1 (Today, July 18) — Test existing capabilities

**Priority 1: scRNA-seq end-to-end demo test**
- Find a small public MG PBMC scRNA-seq dataset (GEO or similar)
- Run through BioMate chat: "Run single-cell RNA-seq clustering on this PBMC data from MG patients"
- Verify: Seurat clustering runs, UMAP outputs, cell type annotation, marker genes
- If blocked: identify the failure point (parameter prefill? output display? step parsing?)

**Priority 2: Smoke-test the 3 newly built workflows**
- `target_evidence_positioning` — run for target="AChR" (CHRNA1) in MG, CIDP, GBS
- `patient_recruitment_feasibility` — run for MG Phase 3, 180 patients, 20 sites, 24 months
- `rare_disease_power_calculator` — run for MG Phase 3 power scenario (α=0.025, β=0.20, expected delta=1.5 MG-ADL points)
- `run_audit_export` — run with sample ADMET outputs to verify manifest + claims_index generation

**Priority 3: DESeq2 parameter prefill for MG**
- Confirm "Run differential expression on AChR+ vs MuSK+ MG patient PBMC RNA-seq data" routes correctly and prefills condition, design formula, reference level

---

### Day 2 (July 19) — Fill critical gaps

**Priority 4: Bioconductor output_types backfill** ✅ DONE 2026-07-18
- Rule-based backfill applied to all 871 empty workflows (nf-core subworkflows indexed without output_types)
- 4,030/4,030 workflows now have output_types — zero remaining
- scRNA→Bioconductor consumer chains now have type-flow connectivity

**Priority 5: ADMET→PBPK→IND §2.6 chain demo run**
- Run the full flagship chain end-to-end in a single chat session
- Record the session (screenshots or screen recording)
- Verify: ADMET outputs → REINVENT4 remediation → PBPK → IND §2.6 narrative
- This is the primary Demo C for Cartesian and Hesperos

**Priority 6: Complement pathway enrichment test**
- Run "Identify complement pathway activation in this CIDP patient gene expression data"
- Verify clusterProfiler enrichGO correctly loads complement gene sets (GO:0006958, GO:0001906, C3/C5/CFB gene sets)
- Output: enrichment bar chart + table for Martin Kolev (Apellis/Biogen) and Salma Merchant (Alnylam)

---

### Day 3 (July 20 — Day Before Conference) — Polish + prep

**Priority 7: GWAS→scRNA→eQTL chain (Lundbeck)**
- If bandwidth allows: implement the chain stub
- Inputs: GWAS summary stats + scRNA-seq h5ad + eQTL reference → target prioritization list
- Even a basic working version (GWAS loci → nearby genes → scRNA expression lookup → target_evidence_positioning) is enough for a credible demo
- This is the single most valuable new feature for the highest-value contact (Tarek Samad, Lundbeck EVP in 6 weeks)

**Priority 8: PBPK peripheral nerve compartment**
- Alnylam's specific gap: their published GalNAc-siRNA WB-PBPK-PD model covers liver; peripheral nerve unmodeled
- Add peripheral nerve/spinal compartment parameters to BioMate's existing PBPK workflow
- Even basic 2-compartment CNS extension would be a credible demo for David Ngai's roundtable topic

**Priority 9: Conference prep**
- Write one-sentence BioMate description per demo scenario (A/B/C)
- Verify dev-public.biomate.ai is running clean
- Load a public MG PBMC dataset into a demo project so live demo starts from a real data state

---

## Section 6 — Demo Data Sources

| Demo | Dataset | Where |
|------|---------|-------|
| Demo A (MG scRNA-seq) | GSE142256 — MG patient PBMCs (GSE, ~8 patients) | GEO; or use subset of Replogle K562 as fallback |
| Demo A (DESeq2) | Any published AChR+ vs MuSK+ bulk RNA-seq count matrix | Search GEO for "myasthenia gravis RNA-seq" |
| Demo B (CD40L indication mapping) | CD40L pathway gene set from MSigDB (HALLMARK_CD40_PATHWAY or curated) | MSigDB free |
| Demo B (target positioning) | target="CD40LG" or "TNFSF5"; disease=MG/CIDP/GBS | OpenTargets API (live in workflow) |
| Demo C (ADMET→IND chain) | 5-10 compound SMILES from published MG MOA literature | Manual — any known AChR modulator SMILES |

---

## Section 7 — Contacts Who Can Become Early Pilot Users

These contacts have the highest combination of: (a) a specific open question, (b) data they already hold, and (c) a team small enough that BioMate removes real friction vs. just adding another tool:

| Priority | Contact | Company | What They Bring | Pilot Offer |
|----------|---------|---------|----------------|-------------|
| **P1** | Dina Schneider | Cartesian | Phase 2b PBMC scRNA-seq + proteomics from Nature Medicine paper | Free pilot run of scRNA-seq responder profiling on their Phase 2b data |
| **P1** | Jeremy Sokolove | Vor Bio | Multi-omics biomarker scientist; 7 months into CMO role, building the analysis stack | "Run your UPSTREAM MG baseline biomarker hypothesis through BioMate — we'll turn it around in 48h" |
| **P2** | Jessica VanBaaren | UCB | 13-cycle Phase 3 biobank; needs the responder stratification hypothesis | Pilot DESeq2 + scRNA-seq on published UCB Phase 3 sample types |
| **P2** | David Ngai | Alnylam | Macrophage immunometabolism expertise; PBPK CNS gap is known | Show peripheral nerve PBPK extension + macrophage scRNA-seq pilot |
| **P3** | Martin Kolev | Apellis→Biogen | Scientifically sophisticated; programs at risk; relationship building | Complement pathway enrichment demo on published MG transcriptomics |

---

## Section 8 — What We Are NOT Building Before the Conference

Items from the Excel roadmap that are deprioritized given the BD context:

- **MD fast-modes (NNPOps/ANI-2x):** No MD-focused contacts at this neuromuscular conference
- **BioEmu protein ensemble:** No structural biology primary contacts
- **Cryo-EM→pocket→screen chain:** No cryo-EM primary contacts
- **SmallWorld/Enamine REAL:** No FBDD/virtual screening contacts
- **MMseqs2 sequence search service:** Sequence homology not the bottleneck for any contact
- **MedCPT + Qdrant literature retrieval:** Nice to have; not the demo blocker
- **HybridLLMRouter:** Already dropped per roadmap (user decision)
- **Nextflow process-level parallelism (DE ensemble):** Complex Chain P3, no catalog target
