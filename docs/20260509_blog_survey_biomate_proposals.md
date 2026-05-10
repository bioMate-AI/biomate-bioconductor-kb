# BioMate Proposals from Blog Survey — 2026-05-09

Synthesized from 25 blog screenshots. **Verified against actual DB contents** (2,455 workflows across 34 domains).

---

## What BioMate Already Has (relevant to blog topics)

### Drug Discovery / Pharmacology (83 + 22 workflows)
- **ADMET**: `Predict ADMET Properties (AI)`, `herg_cardiac_safety_qsar`, `cns_penetration_prediction`, `dart_toxicity_prediction`, `genotoxicity_ames_prediction`, `repeated_dose_tox_prediction`, `membrane_permeability_prediction`
- **Generative design**: `REINVENT4 Generative Lead Design`, `scaffold_hopping`, `covalent_warhead_design`, `bispecific_antibody_design`, `scfv_antibody_design`
- **Docking / binding**: `Docking Autodock Vina`, `Schrodinger Glide Docking`, `Run Diffdock With Smiles`, `drugclip_virtual_screening`, `MOE Covalent Docking Pipeline`, `Pharmacophore Filtering`, `Pocket Detection Druggability`
- **Free energy**: `OpenFE Relative Binding Free Energy (RBFE)` ← **already exists**
- **PK/PD/PBPK**: `pbpk_simulation`, `pk_sim_pbpk`, `simcyp_pbpk`, `nlmixr2_population_pk`, `nonmem_poppk`, `nca_pknca`, `oral_absorption_bcs_model`, `pbpk_pediatric`, `pbpk_disease_state`, `nanoparticle_pk_biodistribution`
- **Clinical trials**: `clinical_trial_simulation`, `adaptive_trial_design`, `biomarker_patient_enrichment`, `phase2_dose_justification`, `virtual_patient_cohort`, `exposure_response_modeling`
- **Drug repurposing**: `Retrieve Topk Repurposing Drugs From Disease Txgnn` ← **TxGNN already exists**
- **Retrosynthesis**: `Aizynthfinder Retrosynthesis`, `syncraft_synthesizability`
- **MD simulation**: `GROMACS Protein-Ligand MD + MM-GBSA`, `AMBER pmemd GPU Molecular Dynamics`
- **Rare disease**: `nf-core/raredisease`, `nf-core/longraredisease`
- **siRNA**: `sirna_offtarget_analysis`, `synlet`, `lnp_formulation_optimization` ← partial coverage

### Single Cell / Virtual Cell
- `state_perturbation_prediction` — Arc Institute STATE model, trained on 270M+ cells, predicts perturbation responses ← **already exists**
- `gears_perturbation_prediction` + GPU variant ← **already exists**
- `transcriptformer_cell_state` + GPU variant
- Full Bioconductor single-cell suite (28 workflows: Seurat, SCE, CITE-seq, multiome, spatial, etc.)

### Cryo-EM
- CryoSPARC SPA, RELION multi-body, Helical SPA, cryoDRGN, 3D variability, Focused Refinement, Subtomogram averaging, Cryo-ET, DeepEMhancer post-processing
- No atomic model building (Phenix/COOT) — **confirmed gap**

### Protein Design
- `AlphaFold DB Search`, `Predict Binding Affinity Protein 1D Sequence`, `scfv_antibody_design`, `bispecific_antibody_design`, `fcrn_antibody_pk`, `proteome_selectivity_profiling`

---

## Real Gaps (not currently in DB)

### Gap 1: siRNA Design (generation + ranking)
`sirna_offtarget_analysis` exists but only does **off-target analysis** on an existing siRNA. There is no **siRNA generation** workflow: given an mRNA sequence → generate all 19-21mer candidates → score efficacy (thermodynamic asymmetry, Ui-Tei/Reynolds rules, GC content) → rank top 10% → pass to off-target analysis.

**Proposal**: Add `sirna_design_full` workflow that covers generation + efficacy scoring, then chains to existing `sirna_offtarget_analysis`. This closes the full design loop.

---

### Gap 2: Cryo-EM Atomic Model Building (Phenix / ModelAngelo)
Reconstruction (CryoSPARC, RELION) ends at a density map. The next step — fitting an atomic model into the map — is absent. Standard tools: `ModelAngelo` (ML-based automated model building, Cambridge 2023), `Phenix real_space_refine`, MolProbity validation.

**Proposal**: Add `cryoem_model_building` workflow:
- Input: `.mrc` density map + protein sequence (FASTA)
- Step 1: `ModelAngelo` — ML automated model building from map + sequence
- Step 2: `phenix.real_space_refine` — geometry-restrained refinement into density
- Step 3: MolProbity validation — Ramachandran, rotamer, clash score
- Output: refined `.pdb` + validation report JSON

This fills the reconstruction → depositable structure gap and is the most requested cryo-EM downstream step.

---

### Gap 3: ADMET → REINVENT Closed-Loop MPO
`Predict ADMET Properties (AI)` and `REINVENT4 Generative Lead Design` both exist but are not connected. Users get ADMET violations with no generative remediation path from within BioMate. The blog insight: the biggest drug discovery failure mode is treating ADMET as a gate not an optimization target.

**Proposal**: Add an `admet_mpo_optimization` workflow that:
1. Runs ADMET screening on input SMILES
2. Identifies failing endpoints (hERG, DILI, Ames, Ro5)
3. Passes violation reason + SMILES to REINVENT4 in `scaffold_decoration` or `linker_design` mode with ADMET multi-objective scoring function
4. Returns 5-10 optimized SMILES with predicted improvement
5. Runs ADMET on all outputs to confirm improvement

This is the true MPO loop and directly closes the feedback gap.

---

### Gap 4: FDA Clinical Trial Audit Trail
`clinical_trial_simulation` and `adaptive_trial_design` exist but output standard CSV/JSON. The FDA RFI 2026-08281 is specifically asking for AI decision systems with **audit-compliant decision logs** (decision + model version + input data + timestamp + rationale).

**Proposal**: Extend clinical trial workflows to emit an FDA audit JSON alongside standard outputs:
- Structured fields: `decision` (GO/NO-GO/PAUSE), `decision_basis` (model name, version, key metrics), `input_data_hash`, `timestamp_utc`, `regulatory_guidance_cited` (e.g., "FDA BOIN 2021 Guidance"), `analyst_override` (boolean)
- The IND §2.6 LLM narrative already exists — this adds the machine-readable audit record that goes alongside it
- Enables BioMate to credibly say "our AI decision artifacts are FDA-inspection-ready"

---

### Gap 5: Rare Disease: Variant → Repurposing Chain
`nf-core/raredisease` handles variant calling. `Retrieve Topk Repurposing Drugs From Disease Txgnn` handles repurposing by disease name. But there is no **chain** connecting them: variant → gene → disease phenotype (HPO) → TxGNN query → repurposing candidates.

**Proposal**: Build a routing rule and optional chain:
- After `raredisease` completes, offer: "Would you like to identify potential repurposable treatments for the identified variants?"
- Chain: extract affected genes from VCF → map to HPO terms (via `patient_gene` BioMate classifier) → query `Retrieve Topk Repurposing Drugs From Disease Txgnn` with the disease phenotype
- Output: integrated report combining variant findings + repurposing candidates

This is primarily a routing/chain addition, not new workflow development.

---

### Gap 6: Small RNA / RNA Aptamer Design
Beyond siRNA, there is no aptamer or ribozyme design workflow. The `large_molecul_design.jpg` blog noted RNA aptamers (SELEX-derived) and ribozymes as growing therapeutic modalities.

**Lower priority** — market is smaller and tooling (NUPACK, Vienna RNA, RNAframework) is more specialized. Flag for future addition when customer demand is confirmed.

---

## No Gap Found (proposals retracted after DB check)

| Blog Proposal | DB Reality |
|---|---|
| FEP workflow | `OpenFE Relative Binding Free Energy (RBFE)` already indexed |
| Drug repurposing (TxGNN) | `Retrieve Topk Repurposing Drugs From Disease Txgnn` already indexed |
| Virtual cell / perturbation prediction | `state_perturbation_prediction` (STATE, Arc Institute) + `gears_perturbation_prediction` already indexed |
| Generative lead design / REINVENT | `REINVENT4 Generative Lead Design` already indexed |
| Adaptive trial design | `adaptive_trial_design` (MAMS + RAR + O'Brien-Fleming stopping) already indexed |
| PBPK disease state / special populations | `pbpk_disease_state`, `pbpk_pediatric_pregnancy` already indexed |

---

## Strategic Observations (not requiring new workflows)

### Routing Visibility Problem
BioMate has **remarkable depth** that most users don't discover. `OpenFE RBFE`, `TxGNN repurposing`, `STATE virtual cell`, `REINVENT4`, `GEARS` — these are frontier tools. The problem is discoverability: a user asking "can you check if there are repurposable drugs for this rare disease?" may not receive `Retrieve Topk Repurposing Drugs From Disease Txgnn` because routing rules don't associate that intent with the workflow name.

**Action**: Add routing rules and description patches for these high-value, poorly-discoverable workflows. Specifically:
- `Retrieve Topk Repurposing Drugs From Disease Txgnn` → trigger on: "drug repurposing", "rare disease treatment", "existing drugs for condition X"
- `OpenFE RBFE` → trigger on: "binding free energy", "confirm affinity", "lead optimization FEP", "relative binding"
- `state_perturbation_prediction` / `gears_perturbation_prediction` → trigger on: "virtual cell", "perturbation prediction", "cell response to drug", "CRISPR prediction"

### ADMET → REINVENT Loop is the Most Impactful Near-Term Work
Both tools exist. Connecting them into a closed MPO loop is primarily a workflow chain + routing change, not new algorithm development. This directly addresses the biggest drug discovery failure mode identified across multiple blog posts.

### FDA Audit Trail Positions BioMate as Regulatory-Grade
The FDA RFI signal + clinical trial simulation depth already in BioMate means this is a positioning opportunity achievable with a relatively small engineering investment (extend output schema + add audit JSON emitter). No pharma-focused AI platform currently offers FDA-inspection-ready audit logs on AI clinical decisions.

---

## Priority Table (updated after DB audit)

| Priority | Proposal | Effort | Impact |
|----------|----------|--------|--------|
| P0-1 | siRNA generation workflow (chains to existing off-target analysis) | Small (3-5 days) | Medium |
| P0-2 | Routing rules for TxGNN/OpenFE/STATE/GEARS/REINVENT | Very small (1-2 days) | High (immediate discoverability) |
| P0-3 | Rare disease: variant → HPO → TxGNN routing chain | Small (3-5 days) | High |
| P1-1 | ADMET → REINVENT4 closed MPO loop workflow | Medium (2-3 wk) | Very High |
| P1-2 | Cryo-EM atomic model building (ModelAngelo + Phenix) | Medium (2-3 wk) | High (completes cryo-EM pipeline) |
| P1-3 | FDA audit trail JSON for clinical trial workflows | Small (1 wk) | Very High (positioning) |
| P2-1 | Enterprise ROI calculator + Model-3 pricing | Small (1 wk) | High (revenue) |
| P2-2 | Company Brain: client SOP/protocol ingestion (RAG) | Medium (3-4 wk) | High (stickiness) |
