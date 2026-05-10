# BioMate Licensed / Key-Gated Tools Inventory — 2026-05-09

Purpose: every workflow that requires an external license, API key, or BYOL credential. These tools must be either (a) provided by the customer (BYOL — bring your own license), (b) priced into a managed-service tier, or (c) replaced by an open-source alternative when the customer has no access. This document is the source of truth for cost integration in pricing tiers.

---

## Tier 1 — Commercial Licenses (high cost, BYOL required)

### Schrödinger Glide / Maestro Suite
- **BioMate workflow**: `Schrodinger Glide Docking`
- **Workflow folder**: `nextflow_nfcore/subworkflows/drug_discovery/schrodinger_glide_docking/`
- **License model**: FlexNet floating license; user provides `SCHRODINGER_HOST` + license file
- **Description**: Industry-standard high-accuracy docking (HTVS/SP/XP precision modes), GlideScore + LipophilicEvolution rescoring; the de-facto reference for pharma virtual screening
- **Docs**: https://www.schrodinger.com/products/glide
- **Startup pricing (per-seat, indicative list — actual via direct sales)**:
  - Single-user Glide SP: ~$30K/year
  - Glide XP + LigPrep + Maestro: ~$65K/year
  - Small Drug Discovery Suite: ~$140K/year (5 seats)
- **BioMate fallback if no license**: `Docking Autodock Vina` (open-source, free)

### Schrödinger REINVENT (proprietary commercial branch)
- **BioMate workflow**: `REINVENT4 Generative Lead Design` — uses **open-source REINVENT4** from MolecularAI (Apache 2.0); commercial Schrödinger branch is NOT required
- **Workflow folder**: `nextflow_nfcore/subworkflows/drug_discovery/reinvent4_lead_design/`
- **Container**: `ghcr.io/molecularai/reinvent4:4.4.14` (open-source)
- **Note**: BioMate uses the AstraZeneca open-source release. Schrödinger sells a wrapped enterprise version (~$80K/year) — not needed.

### MOE (Molecular Operating Environment)
- **BioMate workflow**: `MOE Covalent Docking Pipeline`
- **Workflow folder**: `nextflow_nfcore/subworkflows/drug_discovery/moe_covalent_docking/`
- **License model**: FlexNet floating license; user provides `MOE_LICENSE_FILE`
- **Description**: Chemical Computing Group MOE — covalent docking with explicit warhead-residue bond formation, GBVI/WSA dG rescoring; only major commercial covalent docking tool
- **Docs**: https://www.chemcomp.com/Products.htm
- **Startup pricing**: ~$25K/year per user (academic ~$2K)
- **BioMate fallback**: AutoDock Vina with covalent docking patch (manual setup, less accurate)

### Simcyp (Certara) PBPK Simulator
- **BioMate workflow**: `simcyp_pbpk` (BYOL with native fallback)
- **Workflow folder**: `drug_discovery/simcyp_pbpk/`
- **License model**: BYOL — provide `SIMCYP_LICENSE_FILE` or `SIMCYP_LICENSE_SERVER`
- **Description**: Regulatory gold standard for PBPK (EMA Qualification Opinion Aug 2025; FDA-accepted). DDI prediction, special populations, pediatric/pregnancy/disease-state.
- **Docs**: https://www.certara.com/software/simcyp-pbpk/
- **Startup pricing**: Simcyp Discovery ~$40K/year; full Simcyp Simulator ~$120K/year
- **BioMate fallback**: `pk_sim_pbpk` — Open Systems Pharmacology PK-Sim (LGPL, EMA-accepted, free, ships in BioMate container) **+ BioMate native PBPK** (10-compartment ODE)

### NONMEM (Icon plc)
- **BioMate workflow**: `nonmem_poppk` (BYOL only)
- **Workflow folder**: `drug_discovery/nonmem_poppk/`
- **License model**: BYOL — provide `NONMEM_HOME` + `NONMEM_LICENSE_FILE`
- **Description**: Industry-standard population PK FOCE-I/LAPLACE estimator; required for some FDA NDA submissions
- **Docs**: https://www.iconplc.com/solutions/technologies/nonmem
- **Startup pricing**: ~$30K/year single user; ~$70K/year team
- **BioMate fallback**: `nlmixr2_population_pk` — open-source SAEM + FOCE+, validated against NONMEM (Fidler 2019 CPT:PSP); ships in BioMate R container

### AMBER (single-license barrier for some uses)
- **BioMate workflow**: `AMBER pmemd GPU Molecular Dynamics`
- **Workflow folder**: `nextflow_nfcore/subworkflows/drug_discovery/amber_pmemd_md/`
- **License model**: AMBER24+ is **free for academic and commercial use** (license agreement required but no fee); pmemd CUDA GPU build needs single-machine acknowledgement
- **Docs**: https://ambermd.org/
- **Startup cost**: $0 (post AMBER24)
- **Note**: Pre-AMBER24 (≤AMBER22), pmemd CUDA was $750/site for industry — no longer applicable.

### CryoSPARC (Structura Bio)
- **BioMate workflows**: `CryoSPARC Standard Single-Particle Analysis`, `Helical SPA Pipeline`, `Focused Refinement Pipeline`, `3D Variability Pipeline`, `GPCR Complex SPA`, `Saposin Nanodisc SPA`, `Liposome Pore Forming SPA`, `Subtomogram Averaging`, `Multi Drug Atlas`
- **Workflow folder**: `nextflow_nfcore/subworkflows/cryo_em/` and `biomni_workflows/pipeline_composition/pipelines/`
- **License model**: Free for academic, commercial license required for industry use; Structura Bio direct sales
- **Docs**: https://cryosparc.com/
- **Startup pricing**: Industry license ~$8K-15K/year per node; site license higher
- **BioMate fallback**: RELION (open-source, GPL-2) for most steps; `RELION Multi-Body Refinement` workflow exists in DB

---

## Tier 2 — Cloud API / Token-Gated

### Together AI (Evo 2 inference)
- **BioMate workflow**: `evo2_variant_effect`
- **Workflow folder**: `genomics/evo2_variant_effect/`
- **License model**: API token; pay-per-token
- **Description**: Arc Institute Evo 2 40B-parameter DNA language model for variant effect prediction (LLR scores)
- **Docs**: https://docs.together.ai/docs/models
- **Startup pricing**: ~$0.0006/1K tokens for Evo-2; one VCF (10K variants) ~ $5-50
- **BioMate fallback**: Local HuggingFace Evo-2 weights (requires GPU; no API cost but high compute)

### Google AlphaGenome API
- **BioMate workflow**: `alphagenome_track_prediction`
- **Workflow folder**: `genomics/alphagenome_track_prediction/`
- **License model**: API key (Google Cloud); pay-per-call
- **Description**: DeepMind 2025 1Mb-context genomic functional track predictor (5000+ tracks: ATAC, ChIP, RNA-seq, splicing, CTCF)
- **Docs**: https://deepmind.google/discover/blog/alphagenome
- **Startup pricing**: TBD (early access program; expected $0.01-0.10 per genomic region)
- **BioMate fallback**: `Enformer` (open-source, free; smaller context window 200kb)

### TxGNN (Harvard)
- **BioMate workflow**: `Retrieve Topk Repurposing Drugs From Disease Txgnn`
- **Workflow folder**: `pharmacology/retrieve_topk_repurposing_drugs_from_disease_txgnn/`
- **License model**: Free academic API; rate-limited
- **Docs**: https://txgnn.org/
- **Startup pricing**: $0 (free tier sufficient for most use)

### CZI TranscriptFormer / scFoundation / scGPT
- **BioMate workflow**: `transcriptformer_cell_state_gpu`
- **Workflow folder**: `virtual_cell/transcriptformer_gpu/`
- **License model**: Apache 2.0 (open-source weights); requires GPU
- **Docs**: https://github.com/czi-ai/transcriptformer
- **Startup pricing**: $0 license; GPU compute cost ~$2-5/hour (BioMate AWS Batch)

---

## Tier 3 — Free / Open Source (no license barrier)

These workflows have no license cost — BioMate users access them at zero marginal cost beyond compute:

| Workflow | License | Where it lives |
|---|---|---|
| `boltz_structure_prediction` | MIT | `structural_biology/boltz_structure_prediction/` |
| `nf-core/proteinfold` (AF2/ESMFold/OmegaFold/RoseTTAFold) | Apache 2.0 / MIT mix | `nfcore/proteinfold/` |
| `Predict ADMET Properties (AI)` | open-source models | `drug_discovery/predict_admet_properties_ai/` |
| `OpenFE Relative Binding Free Energy (RBFE)` | MIT | `drug_discovery/openfe_rbfe/` |
| `nlmixr2_population_pk` | GPL-2 | `pharmacology/nlmixr2_population_pk/` |
| `pk_sim_pbpk` | LGPL | `drug_discovery/pk_sim_pbpk/` |
| `state_perturbation_prediction` | Apache 2.0 (Arc) | `single_cell/state_perturbation_prediction/` |
| `gears_perturbation_prediction` | MIT | `drug_discovery/gears_perturbation_prediction/` |
| `Aizynthfinder Retrosynthesis` | Apache 2.0 (AstraZeneca) | `drug_discovery/aizynthfinder_retrosynthesis/` |
| `crisprDesign` | Artistic-2.0 (Bioconductor) | `nextflow_nfcore/subworkflows/bioconductor/crisprdesign/` |
| `nf-core/raredisease` / `nf-core/sarek` / `nf-core/rnaseq` | MIT | `nfcore/*/` |
| All 6 new modality workflows (ADC, PROTAC, mRNA, AAV, CAR-T, ASO) | BioMate-internal Apache 2.0 | `backend/nf-core-workflows/modules/biomate-ai-tools/*/` |

---

## Cost Integration Strategy

### Recommended pricing tier model

**Free tier** — Tier 3 workflows only; AWS compute capped at $10/month
- Target: students, evaluators
- BioMate cost: ~$5/month (free-tier AWS + cached results)

**Researcher tier ($299/month)** — All Tier 3 + Tier 2 workflows (BioMate-managed API keys for Evo-2, AlphaGenome, TxGNN); $50/month compute included; pay-per-use overage
- Target: R01 PIs, academic spinouts
- BioMate cost: ~$80-150/user/month; gross margin ~50-70%

**Professional tier ($1,999/month)** — All Tier 2 + AMBER + CryoSPARC academic-equivalent pipelines; $500/month compute included
- Target: Series A/B biotech (1-5 users)
- BioMate cost: ~$700-1,000/user/month; gross margin ~50%

**Enterprise tier (BYOL, custom $50K+/year)** — Customer brings their own Schrödinger / Simcyp / NONMEM / MOE / commercial CryoSPARC licenses; BioMate provides the orchestration layer, AI assistant, audit trail, SSO, 21 CFR Part 11
- Target: mid-large pharma
- BioMate cost: largely engineering / support; gross margin ~80%

### Why BYOL works for pharma (Enterprise tier)

Pharma already pays $500K-2M/year for the Schrödinger / Simcyp / NONMEM stack. They will not pay BioMate again for the same software. The BioMate value at enterprise tier is:
1. **AI orchestration layer** that knows when to call which tool
2. **Workflow chaining** between previously siloed tools (Schrödinger → Simcyp → NONMEM in one conversation)
3. **Audit trail + 21 CFR Part 11 compliance** layered on top of all tool calls
4. **Conversational interpretation** of outputs with regulatory context
5. **Knowledge multiplication** — junior scientists become productive without 10-year specialist mentoring

### Why fallbacks matter for Researcher tier

When a researcher asks for "high-accuracy docking" without a Schrödinger license, BioMate routes to `Docking Autodock Vina` and clearly labels: *"Used AutoDock Vina (free, open-source). For pharma-grade accuracy, Schrödinger Glide is recommended; bring your license to the Enterprise tier."* This honesty preserves trust while creating natural upgrade pressure.

---

## Cost Summary by Modality

| Modality | Open-source pipeline available? | License needed for "best in class"? |
|---|---|---|
| Small molecule docking | Yes (AutoDock Vina, DiffDock) | Glide for SP/XP precision |
| Generative drug design | Yes (REINVENT4 open) | None — open version is the same code |
| Free energy perturbation | Yes (OpenFE) | None — OpenFE matches FEP+ on most benchmarks |
| Population PK | Yes (nlmixr2) | NONMEM for some FDA submissions |
| PBPK | Yes (PK-Sim, BioMate native) | Simcyp for regulatory gold standard |
| Cryo-EM reconstruction | Yes (RELION) | CryoSPARC for usability + speed |
| Protein structure prediction | Yes (Boltz-2, ESMFold, AF2 via nf-core/proteinfold) | None — open versions are state-of-art |
| ADMET prediction | Yes (BioMate AI ADMET) | StarDrop / ChemAxon for some descriptors |
| ADC / PROTAC / mRNA / AAV / CAR-T / ASO | Yes (BioMate native) | No commercial equivalent exists |
| MD simulation | Yes (GROMACS, AMBER post-AMBER24) | None |
| CRISPR design | Yes (crisprDesign Bioconductor) | None |

**Key insight**: For 6 of the 11 modality categories, BioMate's open-source-or-internal stack matches commercial gold standard. For the 5 where commercial leads (Glide, Simcyp, NONMEM, MOE, CryoSPARC industry), BYOL routing is in place. Customers can start with the open-source path and bring commercial licenses when they need regulatory-grade outputs.

---

## Action Items

1. **Pricing page**: Build a clear comparison table on the website showing what's included in each tier vs. what requires BYOL
2. **In-app license status indicator**: When a workflow runs, the AI should disclose which engine is being used and offer the BYOL upgrade path
3. **Procurement template**: Provide a one-page document to enterprise buyers explaining how their existing Schrödinger / Simcyp / NONMEM licenses plug into BioMate (this lowers the friction for pharma IT/procurement)
4. **Negotiate volume discounts**: For Tier 2 API tools (Together AI Evo-2, AlphaGenome), BioMate as an aggregator should negotiate enterprise volume discounts and pass partial savings through to the Researcher tier
