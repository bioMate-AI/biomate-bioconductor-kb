# BioMate Workflow Registry — 2026-04-19
**Total workflows indexed:** 2473

## Summary by Source
- **bioconductor**: 1818 workflows
- **biomni_nextflow**: 277 workflows
- **nfcore**: 230 workflows
- **nfcore_subwf**: 93 workflows
- **nextflow**: 32 workflows
- **biomate**: 17 workflows
- **biomni**: 3 workflows
- **galaxy_biomni**: 2 workflows
- **biomate_test**: 1 workflows

## Summary by Domain
- **transcriptomics**: 862
- **general**: 536
- **genomics**: 303
- **epigenomics**: 133
- **proteomics**: 110
- **variant_calling**: 102
- **drug_discovery**: 66
- **imaging**: 45
- **metagenomics**: 42
- **molecular_biology**: 30
- **single_cell**: 22
- **bioimaging**: 22
- **metabolomics**: 21
- **microbiology**: 17
- **bioengineering**: 15
- **systems_biology**: 15
- **pharmacology**: 15
- **physiology**: 14
- **immunology**: 13
- **synthetic_biology**: 12
- **genetics**: 11
- **cryo_em**: 10
- **biochemistry**: 9
- **cancer_biology**: 8
- **lab_automation**: 7
- **pathology**: 7
- **database**: 6
- **cell_biology**: 5
- **literature**: 4
- **biophysics**: 3
- **glycoengineering**: 3
- **cryo_et**: 2
- **structural_biology**: 2
- **multi_omics**: 1

## Docker/Container Coverage
- Has explicit container: **309** workflows
- No container specified: **2164** (bioconductor/R workflows use conda env or public Bioconductor image)

### Unique container images in use
- `biomate/biomni-tools:latest` — 240 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86` — 24 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` — 12 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-pharma:x86` — 2 workflow(s)
- `docker.io/bioconductor/bioconductor_docker:RELEASE_3_18` — 2 workflow(s)
- `docker.io/rocker/r-ver:4.3.1` — 1 workflow(s)
- `docker.io/informaticsmatters/rdkit-python3-debian:latest` — 1 workflow(s)
- `docker.io/catgumag/alphafold3:latest` — 1 workflow(s)
- `nlmixr2/nlmixr2:latest` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/schrodinger2024:latest` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/amber24-cuda:latest` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/moe2024:latest` — 1 workflow(s)
- `docker.io/informaticsmatters/rdkit-python3:2023.09.4` — 1 workflow(s)
- `docker.io/fpocket/fpocket:4.1` — 1 workflow(s)
- `docker.io/molecularai/aizynthfinder:3.7.0` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-pharma:latest` — 1 workflow(s)
- `quay.io/biocontainers/bioconductor-geoquery:2.72.0--r44_0` — 1 workflow(s)
- `quay.io/biocontainers/mageck:0.5.9.5--py39h7cff6ad_2` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-microbiology:latest` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/drugclip:latest` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/scfv-pmpnn:latest` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/syncraft:latest` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek:latest` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/profam:latest` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:latest` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest` — 1 workflow(s)
- `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/chai1:latest` — 1 workflow(s)
- `nfcore/chipseq:2.0.0` — 1 workflow(s)
- `nfcore/methylseq:2.6.0` — 1 workflow(s)
- `nfcore/diaproteomics:1.2.4` — 1 workflow(s)
- `nfcore/proteomicslfq:1.0.0` — 1 workflow(s)
- `nfcore/rnaseq:3.14.0` — 1 workflow(s)
- `nfcore/differentialabundance:1.5.0` — 1 workflow(s)
- `nfcore/sarek:3.4.0` — 1 workflow(s)

## Biomni/BioMate Custom Workflows (by path)
*300 custom workflows*

| ID | Name | Path | Domain | Container |
|---|------|------|--------|----------|
| 12808 | Saposin Nanodisc SPA | `biomni_workflows/pipeline_composition/pipelines/saposin_nanodisc_spa/main.nf` | cryo_em | `—` |
| 12809 | GPCR Complex SPA | `biomni_workflows/pipeline_composition/pipelines/gpcr_complex_spa/main.nf` | cryo_em | `—` |
| 12810 | Multi Drug Atlas | `biomni_workflows/pipeline_composition/pipelines/multi_drug_atlas/main.nf` | cryo_em | `—` |
| 12811 | DeepEMhancer Post-Processing | `biomni_workflows/pipeline_composition/modules/cryo_em_tools/deepemhancer.nf` | cryo_em | `—` |
| 12812 | Liposome Pore Forming SPA | `biomni_workflows/pipeline_composition/pipelines/liposome_pore_forming_spa/main.nf` | cryo_em | `—` |
| 12813 | RELION Multi-Body Refinement | `biomni_workflows/pipeline_composition/pipelines/relion_multibody/main.nf` | cryo_em | `—` |
| 12833 | CryoSPARC Standard Single-Particle Analysis | `biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf` | cryo_em | `—` |
| 12836 | 3D Variability Pipeline | `nextflow_nfcore/subworkflows/cryo_em/3d_variability_pipeline/main.nf` | cryo_em | `—` |
| 12837 | Focused Refinement Pipeline | `nextflow_nfcore/subworkflows/cryo_em/focused_refinement_pipeline/main.nf` | cryo_em | `—` |
| 12852 | Helical SPA Pipeline | `nextflow_nfcore/subworkflows/cryo_em/helical_spa_pipeline/main.nf` | cryo_em | `—` |
| 12834 | Cryo-ET Full Pipeline | `biomni_workflows/nextflow_nfcore/subworkflows/cryo_et/et_full_pipeline/main.nf` | cryo_et | `—` |
| 12851 | Subtomogram Averaging | `nextflow_nfcore/subworkflows/cryo_et/subtomogram_averaging/main.nf` | cryo_et | `—` |
| 12799 | GROMACS Protein-Ligand MD + MM-GBSA | `nextflow_nfcore/subworkflows/drug_discovery/gromacs_protein_md/main.nf` | drug_discovery | `—` |
| 12800 | REINVENT4 Generative Lead Design | `nextflow_nfcore/subworkflows/drug_discovery/reinvent4_lead_design/main.nf` | drug_discovery | `—` |
| 12828 | P0 PKPD Semaglutide Validation | `nextflow_nfcore/subworkflows/drug_discovery/p0_pkpd_semaglutide/main.nf` | drug_discovery | `—` |
| 12830 | OpenFE Relative Binding Free Energy (RBFE) | `nextflow_nfcore/subworkflows/drug_discovery/openfe_rbfe/main.nf` | drug_discovery | `—` |
| 12831 | CYP450 DDI Panel + Hepatic Clearance | `nextflow_nfcore/subworkflows/drug_discovery/cyp_ddi_panel/main.nf` | drug_discovery | `—` |
| 12829 | HTML Output Test | `subworkflows/lab_automation/html_output_test/main.nf` | lab_automation | `—` |
| 12647 | AlphaFold DB Search | `nextflow_nfcore/subworkflows/drug_discovery/alphafold_db_search/main.nf` | drug_discovery | `—` |
| 12814 | Assay Ingestion And Ranking | `nextflow_nfcore/subworkflows/drug_discovery/assay_ingestion_and_ranking/main.nf` | drug_discovery | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-pharma:x86` |
| 12815 | Cro Submission Export | `nextflow_nfcore/subworkflows/drug_discovery/cro_submission_export/main.nf` | drug_discovery | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-pharma:x86` |
| 10559 | Analyze Circular Dichroism Spectra | `nextflow_nfcore/subworkflows/biochemistry/analyze_circular_dichroism_spectra/main.nf` | biochemistry | `biomate/biomni-tools:latest` |
| 10560 | Analyze Enzyme Kinetics Assay | `nextflow_nfcore/subworkflows/biochemistry/analyze_enzyme_kinetics_assay/main.nf` | biochemistry | `biomate/biomni-tools:latest` |
| 10561 | Analyze Itc Binding Thermodynamics | `nextflow_nfcore/subworkflows/biochemistry/analyze_itc_binding_thermodynamics/main.nf` | biochemistry | `biomate/biomni-tools:latest` |
| 10562 | Analyze Protease Kinetics | `nextflow_nfcore/subworkflows/biochemistry/analyze_protease_kinetics/main.nf` | biochemistry | `biomate/biomni-tools:latest` |
| 10563 | Analyze Protein Conservation | `nextflow_nfcore/subworkflows/biochemistry/analyze_protein_conservation/main.nf` | biochemistry | `biomate/biomni-tools:latest` |
| 10564 | Analyze Rna Secondary Structure Features | `nextflow_nfcore/subworkflows/biochemistry/analyze_rna_secondary_structure_features/main.nf` | biochemistry | `biomate/biomni-tools:latest` |
| 10565 | Dose Response | `nextflow_nfcore/subworkflows/biochemistry/dose_response/main.nf` | biochemistry | `biomate/biomni-tools:latest` |
| 10566 | Michaelis Menten | `nextflow_nfcore/subworkflows/biochemistry/michaelis_menten/main.nf` | biochemistry | `biomate/biomni-tools:latest` |
| 10567 | One Site Model | `nextflow_nfcore/subworkflows/biochemistry/one_site_model/main.nf` | biochemistry | `biomate/biomni-tools:latest` |
| 10568 | Analyze Calcium Imaging Data | `nextflow_nfcore/subworkflows/bioengineering/analyze_calcium_imaging_data/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 10569 | Analyze Cell Migration Metrics | `nextflow_nfcore/subworkflows/bioengineering/analyze_cell_migration_metrics/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 10570 | Analyze In Vitro Drug Release Kinetics | `nextflow_nfcore/subworkflows/bioengineering/analyze_in_vitro_drug_release_kinetics/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 10571 | Analyze Myofiber Morphology | `nextflow_nfcore/subworkflows/bioengineering/analyze_myofiber_morphology/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 10572 | Decode Behavior From Neural Trajectories | `nextflow_nfcore/subworkflows/bioengineering/decode_behavior_from_neural_trajectories/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 10573 | Default Whole Cell Model | `nextflow_nfcore/subworkflows/bioengineering/default_whole_cell_model/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 10574 | Exp Decay | `nextflow_nfcore/subworkflows/bioengineering/exp_decay/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 10575 | First Order | `nextflow_nfcore/subworkflows/bioengineering/first_order/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 10576 | Higuchi | `nextflow_nfcore/subworkflows/bioengineering/higuchi/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 10577 | Korsmeyer Peppas | `nextflow_nfcore/subworkflows/bioengineering/korsmeyer_peppas/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 10578 | Perform Crispr Cas9 Genome Editing | `nextflow_nfcore/subworkflows/bioengineering/perform_crispr_cas9_genome_editing/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 10579 | Simulate Whole Cell Ode Model | `nextflow_nfcore/subworkflows/bioengineering/simulate_whole_cell_ode_model/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 10580 | Zero Order | `nextflow_nfcore/subworkflows/bioengineering/zero_order/main.nf` | bioengineering | `biomate/biomni-tools:latest` |
| 12648 | Default Whole Cell Model | `nextflow_nfcore/bioengineering/default_whole_cell_model/main.nf` | bioengineering | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` |
| 12649 | First Order | `nextflow_nfcore/bioengineering/first_order/main.nf` | bioengineering | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` |
| 10581 | Batch Register Images | `nextflow_nfcore/subworkflows/bioimaging/batch_register_images/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10582 | Calculate Similarity Metrics | `nextflow_nfcore/subworkflows/bioimaging/calculate_similarity_metrics/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10583 | Check Model Files Exist | `nextflow_nfcore/subworkflows/bioimaging/check_model_files_exist/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10584 | Command Iteration | `nextflow_nfcore/subworkflows/bioimaging/command_iteration/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10585 | Create Affine Transform | `nextflow_nfcore/subworkflows/bioimaging/create_affine_transform/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10586 | Create Deformable Transform | `nextflow_nfcore/subworkflows/bioimaging/create_deformable_transform/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10587 | Create Rigid Transform | `nextflow_nfcore/subworkflows/bioimaging/create_rigid_transform/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10588 | Create Segmentation Visualization | `nextflow_nfcore/subworkflows/bioimaging/create_segmentation_visualization/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10589 | Load Image | `nextflow_nfcore/subworkflows/bioimaging/load_image/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10590 | Patched Torch Load | `nextflow_nfcore/subworkflows/bioimaging/patched_torch_load/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10591 | Prepare Input For Nnunet | `nextflow_nfcore/subworkflows/bioimaging/prepare_input_for_nnunet/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10592 | Preprocess Image | `nextflow_nfcore/subworkflows/bioimaging/preprocess_image/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10593 | Quick Affine Registration | `nextflow_nfcore/subworkflows/bioimaging/quick_affine_registration/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10594 | Quick Deformable Registration | `nextflow_nfcore/subworkflows/bioimaging/quick_deformable_registration/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10595 | Quick Rigid Registration | `nextflow_nfcore/subworkflows/bioimaging/quick_rigid_registration/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10596 | Register Images | `nextflow_nfcore/subworkflows/bioimaging/register_images/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10597 | Save Image | `nextflow_nfcore/subworkflows/bioimaging/save_image/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10598 | Segment With Nn Unet | `nextflow_nfcore/subworkflows/bioimaging/segment_with_nn_unet/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10599 | Setup Nnunet Environment | `nextflow_nfcore/subworkflows/bioimaging/setup_nnunet_environment/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10600 | Setup Registration Method | `nextflow_nfcore/subworkflows/bioimaging/setup_registration_method/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10601 | Split Modalities | `nextflow_nfcore/subworkflows/bioimaging/split_modalities/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10602 | Verify Nifti Input | `nextflow_nfcore/subworkflows/bioimaging/verify_nifti_input/main.nf` | bioimaging | `biomate/biomni-tools:latest` |
| 10603 | Analyze Cell Morphology And Cytoskeleton | `nextflow_nfcore/subworkflows/biophysics/analyze_cell_morphology_and_cytoskeleton/main.nf` | biophysics | `biomate/biomni-tools:latest` |
| 10604 | Analyze Tissue Deformation Flow | `nextflow_nfcore/subworkflows/biophysics/analyze_tissue_deformation_flow/main.nf` | biophysics | `biomate/biomni-tools:latest` |
| 10605 | Analyze Cell Senescence And Apoptosis | `nextflow_nfcore/subworkflows/cancer_biology/analyze_cell_senescence_and_apoptosis/main.nf` | cancer_biology | `biomate/biomni-tools:latest` |
| 10606 | Analyze Copy Number Purity Ploidy And Focal Events | `nextflow_nfcore/subworkflows/cancer_biology/analyze_copy_number_purity_ploidy_and_focal_events/main.nf` | cancer_biology | `biomate/biomni-tools:latest` |
| 10607 | Analyze Ddr Network In Cancer | `nextflow_nfcore/subworkflows/cancer_biology/analyze_ddr_network_in_cancer/main.nf` | cancer_biology | `biomate/biomni-tools:latest` |
| 10608 | Detect And Annotate Somatic Mutations | `nextflow_nfcore/subworkflows/cancer_biology/detect_and_annotate_somatic_mutations/main.nf` | cancer_biology | `biomate/biomni-tools:latest` |
| 10609 | Detect And Characterize Structural Variations | `nextflow_nfcore/subworkflows/cancer_biology/detect_and_characterize_structural_variations/main.nf` | cancer_biology | `biomate/biomni-tools:latest` |
| 10610 | Norm Chr | `nextflow_nfcore/subworkflows/cancer_biology/norm_chr/main.nf` | cancer_biology | `biomate/biomni-tools:latest` |
| 10611 | Perform Gene Expression Nmf Analysis | `nextflow_nfcore/subworkflows/cancer_biology/perform_gene_expression_nmf_analysis/main.nf` | cancer_biology | `biomate/biomni-tools:latest` |
| 12650 | Norm Chr | `nextflow_nfcore/cancer_biology/norm_chr/main.nf` | cancer_biology | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` |
| 10612 | Analyze Flow Cytometry Immunophenotyping | `nextflow_nfcore/subworkflows/cell_biology/analyze_flow_cytometry_immunophenotyping/main.nf` | cell_biology | `biomate/biomni-tools:latest` |
| 10613 | Analyze Mitochondrial Morphology And Potential | `nextflow_nfcore/subworkflows/cell_biology/analyze_mitochondrial_morphology_and_potential/main.nf` | cell_biology | `biomate/biomni-tools:latest` |
| 10614 | Perform Facs Cell Sorting | `nextflow_nfcore/subworkflows/cell_biology/perform_facs_cell_sorting/main.nf` | cell_biology | `biomate/biomni-tools:latest` |
| 10615 | Quantify And Cluster Cell Motility | `nextflow_nfcore/subworkflows/cell_biology/quantify_and_cluster_cell_motility/main.nf` | cell_biology | `biomate/biomni-tools:latest` |
| 10616 | Quantify Cell Cycle Phases From Microscopy | `nextflow_nfcore/subworkflows/cell_biology/quantify_cell_cycle_phases_from_microscopy/main.nf` | cell_biology | `biomate/biomni-tools:latest` |
| 10637 | Blast Sequence | `nextflow_nfcore/subworkflows/database/blast_sequence/main.nf` | database | `biomate/biomni-tools:latest` |
| 10638 | Get Genes Near Ccre | `nextflow_nfcore/subworkflows/database/get_genes_near_ccre/main.nf` | database | `biomate/biomni-tools:latest` |
| 10639 | Get Hpo Names | `nextflow_nfcore/subworkflows/database/get_hpo_names/main.nf` | database | `biomate/biomni-tools:latest` |
| 10640 | Reduce Tokens | `nextflow_nfcore/subworkflows/database/reduce_tokens/main.nf` | database | `biomate/biomni-tools:latest` |
| 10641 | Region To Ccre Screen | `nextflow_nfcore/subworkflows/database/region_to_ccre_screen/main.nf` | database | `biomate/biomni-tools:latest` |
| 12652 | Get Hpo Names | `nextflow_nfcore/database/get_hpo_names/main.nf` | database | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` |
| 10642 | Nca Pknca | `nextflow_nfcore/subworkflows/drug_discovery/nca_pknca/main.nf` | drug_discovery | `docker.io/rocker/r-ver:4.3.1` |
| 10643 | Scaffold Hopping | `nextflow_nfcore/subworkflows/drug_discovery/scaffold_hopping/main.nf` | drug_discovery | `docker.io/informaticsmatters/rdkit-python3-debian:latest` |
| 10644 | Structure Prediction Docking | `nextflow_nfcore/subworkflows/drug_discovery/structure_prediction_docking/main.nf` | drug_discovery | `docker.io/catgumag/alphafold3:latest` |
| 10761 | Admet Pred | `nextflow_nfcore/subworkflows/pharmacology/ADMET_pred/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10762 | Analyze Accelerated Stability Of Pharmaceutical Formulations | `nextflow_nfcore/subworkflows/pharmacology/analyze_accelerated_stability_of_pharmaceutical_formulations/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10763 | Analyze Fda Safety Signals | `nextflow_nfcore/subworkflows/pharmacology/analyze_fda_safety_signals/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10764 | Analyze Interaction Mechanisms | `nextflow_nfcore/subworkflows/pharmacology/analyze_interaction_mechanisms/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10765 | Analyze Radiolabeled Antibody Biodistribution | `nextflow_nfcore/subworkflows/pharmacology/analyze_radiolabeled_antibody_biodistribution/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10766 | Analyze Western Blot | `nextflow_nfcore/subworkflows/pharmacology/analyze_western_blot/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10767 | Analyze Xenograft Tumor Growth Inhibition | `nextflow_nfcore/subworkflows/pharmacology/analyze_xenograft_tumor_growth_inhibition/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10768 | Apply Vcog Grade | `nextflow_nfcore/subworkflows/pharmacology/apply_vcog_grade/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10769 | Bi Exp Model | `nextflow_nfcore/subworkflows/pharmacology/bi_exp_model/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10770 | Calculate Physicochemical Properties | `nextflow_nfcore/subworkflows/pharmacology/calculate_physicochemical_properties/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10771 | Check Drug Combination Safety | `nextflow_nfcore/subworkflows/pharmacology/check_drug_combination_safety/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10772 | Check Fda Drug Recalls | `nextflow_nfcore/subworkflows/pharmacology/check_fda_drug_recalls/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10773 | Docking Autodock Vina | `nextflow_nfcore/subworkflows/pharmacology/docking_autodock_vina/main.nf` | drug_discovery | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-structure-to-drug:x86` (local: `biomate/biomni-drug-discovery-nf:latest`) |
| 10774 | Estimate Alpha Particle Radiotherapy Dosimetry | `nextflow_nfcore/subworkflows/pharmacology/estimate_alpha_particle_radiotherapy_dosimetry/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10775 | Find Alternative Drugs Ddinter | `nextflow_nfcore/subworkflows/pharmacology/find_alternative_drugs_ddinter/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10776 | Get Fda Drug Label Info | `nextflow_nfcore/subworkflows/pharmacology/get_fda_drug_label_info/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10777 | Grade Adverse Events Using Vcog Ctcae | `nextflow_nfcore/subworkflows/pharmacology/grade_adverse_events_using_vcog_ctcae/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10778 | Ivive Hepatic Clearance | `nextflow_nfcore/subworkflows/pharmacology/ivive_hepatic_clearance/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10780 | Nlmixr2 Population Pk | `nextflow_nfcore/subworkflows/pharmacology/nlmixr2_population_pk/main.nf` | drug_discovery | `nlmixr2/nlmixr2:latest` |
| 10781 | Perform Mwas Cyp2C19 Metabolizer Status | `nextflow_nfcore/subworkflows/pharmacology/perform_mwas_cyp2c19_metabolizer_status/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10782 | Predict Admet Properties | `nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10783 | Predict Binding Affinity Protein 1D Sequence | `nextflow_nfcore/subworkflows/pharmacology/predict_binding_affinity_protein_1d_sequence/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10784 | Qsar Rf Model | `nextflow_nfcore/subworkflows/pharmacology/qsar_rf_model/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10785 | Retrieve Topk Repurposing Drugs From Disease Txgnn | `nextflow_nfcore/subworkflows/pharmacology/retrieve_topk_repurposing_drugs_from_disease_txgnn/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10786 | Run 3D Chondrogenic Aggregate Assay | `nextflow_nfcore/subworkflows/pharmacology/run_3d_chondrogenic_aggregate_assay/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10787 | Run Autosite | `nextflow_nfcore/subworkflows/pharmacology/run_autosite/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10788 | Run Diffdock With Smiles | `nextflow_nfcore/subworkflows/pharmacology/run_diffdock_with_smiles/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 10789 | Sigmoid | `nextflow_nfcore/subworkflows/pharmacology/sigmoid/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 12801 | Schrodinger Glide Docking | `nextflow_nfcore/subworkflows/drug_discovery/schrodinger_glide_docking/main.nf` | drug_discovery | `399683337364.dkr.ecr.us-west-2.amazonaws.com/schrodinger2024:latest` |
| 12802 | AMBER pmemd GPU Molecular Dynamics | `nextflow_nfcore/subworkflows/drug_discovery/amber_pmemd_md/main.nf` | drug_discovery | `399683337364.dkr.ecr.us-west-2.amazonaws.com/amber24-cuda:latest` |
| 12803 | MOE Covalent Docking Pipeline | `nextflow_nfcore/subworkflows/drug_discovery/moe_covalent_docking/main.nf` | drug_discovery | `399683337364.dkr.ecr.us-west-2.amazonaws.com/moe2024:latest` |
| 12804 | Pharmacophore Filtering | `nextflow_nfcore/subworkflows/drug_discovery/pharmacophore_filtering/main.nf` | drug_discovery | `docker.io/informaticsmatters/rdkit-python3:2023.09.4` |
| 12805 | Pocket Detection Druggability | `nextflow_nfcore/subworkflows/drug_discovery/pocket_detection_druggability/main.nf` | drug_discovery | `docker.io/fpocket/fpocket:4.1` |
| 12806 | Aizynthfinder Retrosynthesis | `nextflow_nfcore/subworkflows/drug_discovery/aizynthfinder_retrosynthesis/main.nf` | drug_discovery | `docker.io/molecularai/aizynthfinder:3.7.0` |
| 12807 | Drug Moa Rnaseq | `nextflow_nfcore/subworkflows/drug_discovery/drug_moa_rnaseq/main.nf` | drug_discovery | `docker.io/bioconductor/bioconductor_docker:RELEASE_3_18` |
| 12818 | P0 Docking Validation | `nextflow_nfcore/subworkflows/drug_discovery/p0_docking_validation/main.nf` | drug_discovery | `—` |
| 12819 | P0 Mrna Validation | `nextflow_nfcore/subworkflows/drug_discovery/p0_mrna_validation/main.nf` | drug_discovery | `—` |
| 12822 | Admet Pred | `nextflow_nfcore/subworkflows/drug_discovery/ADMET_pred/main.nf` | drug_discovery | `biomate/biomni-tools:latest` |
| 12823 | Apply Vcog Grade | `nextflow_nfcore/subworkflows/drug_discovery/apply_vcog_grade/main.nf` | drug_discovery | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-pharma:latest` |
| 12824 | Docking Autodock Vina | `nextflow_nfcore/subworkflows/pharmacology/docking_autodock_vina/main.nf` | drug_discovery | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-structure-to-drug:x86` (local: `biomate/biomni-drug-discovery-nf:latest`) |
| 12825 | Ivive Hepatic Clearance | `nextflow_nfcore/subworkflows/drug_discovery/ivive_hepatic_clearance/main.nf` | drug_discovery | `—` |
| 12826 | Predict Admet Properties | `nextflow_nfcore/subworkflows/drug_discovery/predict_admet_properties/main.nf` | drug_discovery | `—` |
| 12827 | P0 Pharmacophore Validation | `nextflow_nfcore/subworkflows/drug_discovery/p0_pharmacophore_validation/main.nf` | drug_discovery | `—` |
| 10645 | Analyze Cas9 Mutation Outcomes | `nextflow_nfcore/subworkflows/genetics/analyze_cas9_mutation_outcomes/main.nf` | genetics | `biomate/biomni-tools:latest` |
| 10646 | Analyze Crispr Genome Editing | `nextflow_nfcore/subworkflows/genetics/analyze_crispr_genome_editing/main.nf` | genetics | `biomate/biomni-tools:latest` |
| 10647 | Analyze Protein Phylogeny | `nextflow_nfcore/subworkflows/genetics/analyze_protein_phylogeny/main.nf` | genetics | `biomate/biomni-tools:latest` |
| 10648 | Bayesian Finemapping With Deep Vi | `nextflow_nfcore/subworkflows/genetics/bayesian_finemapping_with_deep_vi/main.nf` | genetics | `biomate/biomni-tools:latest` |
| 10649 | Elbo Loss | `nextflow_nfcore/subworkflows/genetics/elbo_loss/main.nf` | genetics | `biomate/biomni-tools:latest` |
| 10650 | Fit Genomic Prediction Model | `nextflow_nfcore/subworkflows/genetics/fit_genomic_prediction_model/main.nf` | genetics | `biomate/biomni-tools:latest` |
| 10651 | Forward | `nextflow_nfcore/subworkflows/genetics/forward/main.nf` | genetics | `biomate/biomni-tools:latest` |
| 10652 | Identify Transcription Factor Binding Sites | `nextflow_nfcore/subworkflows/genetics/identify_transcription_factor_binding_sites/main.nf` | genetics | `biomate/biomni-tools:latest` |
| 10653 | Liftover Coordinates | `nextflow_nfcore/subworkflows/genetics/liftover_coordinates/main.nf` | genetics | `biomate/biomni-tools:latest` |
| 10654 | Perform Pcr And Gel Electrophoresis | `nextflow_nfcore/subworkflows/genetics/perform_pcr_and_gel_electrophoresis/main.nf` | genetics | `biomate/biomni-tools:latest` |
| 10655 | Simulate Demographic History | `nextflow_nfcore/subworkflows/genetics/simulate_demographic_history/main.nf` | genetics | `biomate/biomni-tools:latest` |
| 10656 | Analyze Chromatin Interactions | `nextflow_nfcore/subworkflows/genomics/analyze_chromatin_interactions/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10657 | Analyze Comparative Genomics And Haplotypes | `nextflow_nfcore/subworkflows/genomics/analyze_comparative_genomics_and_haplotypes/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10658 | Analyze Genomic Region Overlap | `nextflow_nfcore/subworkflows/genomics/analyze_genomic_region_overlap/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10659 | Annotate Celltype Scrna | `nextflow_nfcore/subworkflows/genomics/annotate_celltype_scRNA/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10660 | Annotate Celltype With Panhumanpy | `nextflow_nfcore/subworkflows/genomics/annotate_celltype_with_panhumanpy/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10661 | Check Ensembl Patterns | `nextflow_nfcore/subworkflows/genomics/check_ensembl_patterns/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10662 | Conda Env Exists | `nextflow_nfcore/subworkflows/genomics/conda_env_exists/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10663 | Create Harmony Embeddings Scrna | `nextflow_nfcore/subworkflows/genomics/create_harmony_embeddings_scRNA/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10664 | Create Panhumanpy Env | `nextflow_nfcore/subworkflows/genomics/create_panhumanpy_env/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10665 | Create Scvi Embeddings Scrna | `nextflow_nfcore/subworkflows/genomics/create_scvi_embeddings_scRNA/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10666 | Custom Mode | `nextflow_nfcore/subworkflows/genomics/custom_mode/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10667 | Find Enriched Motifs With Homer | `nextflow_nfcore/subworkflows/genomics/find_enriched_motifs_with_homer/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10668 | Gene Set Enrichment Analysis | `nextflow_nfcore/subworkflows/genomics/gene_set_enrichment_analysis/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10669 | Generate Embeddings With State | `nextflow_nfcore/subworkflows/genomics/generate_embeddings_with_state/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10670 | Generate Gene Embeddings With Esm Models | `nextflow_nfcore/subworkflows/genomics/generate_gene_embeddings_with_ESM_models/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10671 | Generate Transcriptformer Embeddings | `nextflow_nfcore/subworkflows/genomics/generate_transcriptformer_embeddings/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10672 | Geo Data Connector | `nextflow_nfcore/subworkflows/genomics/geo_data_connector/main.nf` | genomics | `quay.io/biocontainers/bioconductor-geoquery:2.72.0--r44_0` |
| 10673 | Get Gene Set Enrichment Analysis Supported Database List | `nextflow_nfcore/subworkflows/genomics/get_gene_set_enrichment_analysis_supported_database_list/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10674 | Get Matrix | `nextflow_nfcore/subworkflows/genomics/get_matrix/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10675 | Get Rna Seq Archs4 | `nextflow_nfcore/subworkflows/genomics/get_rna_seq_archs4/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10676 | Get Uce Embeddings Scrna | `nextflow_nfcore/subworkflows/genomics/get_uce_embeddings_scRNA/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10677 | Interspecies Gene Conversion | `nextflow_nfcore/subworkflows/genomics/interspecies_gene_conversion/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10678 | Is Model Downloaded | `nextflow_nfcore/subworkflows/genomics/is_model_downloaded/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10679 | Map To Ima Interpret Scrna | `nextflow_nfcore/subworkflows/genomics/map_to_ima_interpret_scRNA/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10680 | Perform Chipseq Peak Calling With Macs2 | `nextflow_nfcore/subworkflows/genomics/perform_chipseq_peak_calling_with_macs2/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10681 | Perturb Seq Analysis | `nextflow_nfcore/subworkflows/genomics/perturb_seq_analysis/main.nf` | genomics | `quay.io/biocontainers/mageck:0.5.9.5--py39h7cff6ad_2` |
| 10682 | Trajectory Inference | `nextflow_nfcore/subworkflows/genomics/trajectory_inference/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10683 | Transcriptomic Biomarker | `nextflow_nfcore/subworkflows/genomics/transcriptomic_biomarker/main.nf` | genomics | `docker.io/bioconductor/bioconductor_docker:RELEASE_3_18` |
| 10684 | Unsupervised Celltype Transfer Between Scrna Datasets | `nextflow_nfcore/subworkflows/genomics/unsupervised_celltype_transfer_between_scRNA_datasets/main.nf` | genomics | `biomate/biomni-tools:latest` |
| 10685 | Wgs Germline Gatk | `nextflow_nfcore/subworkflows/genomics/wgs_germline_gatk/main.nf` | genomics | `—` |
| 12820 | Crispr Screen Mageck | `nextflow_nfcore/subworkflows/genomics/crispr_screen_mageck/main.nf` | genomics | `—` |
| 10686 | Find N Glycosylation Motifs | `nextflow_nfcore/subworkflows/glycoengineering/find_n_glycosylation_motifs/main.nf` | glycoengineering | `biomate/biomni-tools:latest` |
| 10687 | List Glycoengineering Resources | `nextflow_nfcore/subworkflows/glycoengineering/list_glycoengineering_resources/main.nf` | glycoengineering | `biomate/biomni-tools:latest` |
| 10688 | Predict O Glycosylation Hotspots | `nextflow_nfcore/subworkflows/glycoengineering/predict_o_glycosylation_hotspots/main.nf` | glycoengineering | `biomate/biomni-tools:latest` |
| 10689 | Analyze Atac Seq Differential Accessibility | `nextflow_nfcore/subworkflows/immunology/analyze_atac_seq_differential_accessibility/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10690 | Analyze Bacterial Growth Curve | `nextflow_nfcore/subworkflows/immunology/analyze_bacterial_growth_curve/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10691 | Analyze Cfse Cell Proliferation | `nextflow_nfcore/subworkflows/immunology/analyze_cfse_cell_proliferation/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10692 | Analyze Cns Lesion Histology | `nextflow_nfcore/subworkflows/immunology/analyze_cns_lesion_histology/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10693 | Analyze Cytokine Production In Cd4 Tcells | `nextflow_nfcore/subworkflows/immunology/analyze_cytokine_production_in_cd4_tcells/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10694 | Analyze Ebv Antibody Titers | `nextflow_nfcore/subworkflows/immunology/analyze_ebv_antibody_titers/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10695 | Analyze Immunohistochemistry Image | `nextflow_nfcore/subworkflows/immunology/analyze_immunohistochemistry_image/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10696 | Estimate Cell Cycle Phase Durations | `nextflow_nfcore/subworkflows/immunology/estimate_cell_cycle_phase_durations/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10697 | Isolate Purify Immune Cells | `nextflow_nfcore/subworkflows/immunology/isolate_purify_immune_cells/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10698 | Logistic Growth | `nextflow_nfcore/subworkflows/immunology/logistic_growth/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10699 | Objective Function | `nextflow_nfcore/subworkflows/immunology/objective_function/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10700 | Simulate Cell Population | `nextflow_nfcore/subworkflows/immunology/simulate_cell_population/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10701 | Track Immune Cells Under Flow | `nextflow_nfcore/subworkflows/immunology/track_immune_cells_under_flow/main.nf` | immunology | `biomate/biomni-tools:latest` |
| 10702 | Get Pylabrobot Documentation Liquid | `nextflow_nfcore/subworkflows/lab_automation/get_pylabrobot_documentation_liquid/main.nf` | lab_automation | `biomate/biomni-tools:latest` |
| 10703 | Get Pylabrobot Documentation Material | `nextflow_nfcore/subworkflows/lab_automation/get_pylabrobot_documentation_material/main.nf` | lab_automation | `biomate/biomni-tools:latest` |
| 10704 | Pick First | `nextflow_nfcore/subworkflows/lab_automation/pick_first/main.nf` | lab_automation | `biomate/biomni-tools:latest` |
| 10705 | Run Async | `nextflow_nfcore/subworkflows/lab_automation/run_async/main.nf` | lab_automation | `biomate/biomni-tools:latest` |
| 10706 | Target | `nextflow_nfcore/subworkflows/lab_automation/target/main.nf` | lab_automation | `biomate/biomni-tools:latest` |
| 10707 | Test Pylabrobot Script | `nextflow_nfcore/subworkflows/lab_automation/test_pylabrobot_script/main.nf` | lab_automation | `biomate/biomni-tools:latest` |
| 10708 | Advanced Web Search Claude | `nextflow_nfcore/subworkflows/literature/advanced_web_search_claude/main.nf` | literature | `biomate/biomni-tools:latest` |
| 10709 | Extract Pdf Content | `nextflow_nfcore/subworkflows/literature/extract_pdf_content/main.nf` | literature | `biomate/biomni-tools:latest` |
| 10710 | Extract Url Content | `nextflow_nfcore/subworkflows/literature/extract_url_content/main.nf` | literature | `biomate/biomni-tools:latest` |
| 10711 | Fetch Supplementary Info From Doi | `nextflow_nfcore/subworkflows/literature/fetch_supplementary_info_from_doi/main.nf` | literature | `biomate/biomni-tools:latest` |
| 10712 | Analyze Arsenic Speciation Hplc Icpms | `nextflow_nfcore/subworkflows/microbiology/analyze_arsenic_speciation_hplc_icpms/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10713 | Annotate Bacterial Genome | `nextflow_nfcore/subworkflows/microbiology/annotate_bacterial_genome/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10714 | Bacterial Dynamics | `nextflow_nfcore/subworkflows/microbiology/bacterial_dynamics/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10715 | Count Bacterial Colonies | `nextflow_nfcore/subworkflows/microbiology/count_bacterial_colonies/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10716 | Enumerate Bacterial Cfu By Serial Dilution | `nextflow_nfcore/subworkflows/microbiology/enumerate_bacterial_cfu_by_serial_dilution/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10717 | Glv Equations | `nextflow_nfcore/subworkflows/microbiology/glv_equations/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10718 | Methane Yield Model | `nextflow_nfcore/subworkflows/microbiology/methane_yield_model/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10719 | Model Bacterial Growth Dynamics | `nextflow_nfcore/subworkflows/microbiology/model_bacterial_growth_dynamics/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10720 | Optimize Anaerobic Digestion Process | `nextflow_nfcore/subworkflows/microbiology/optimize_anaerobic_digestion_process/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10721 | Predict Rna Secondary Structure | `nextflow_nfcore/subworkflows/microbiology/predict_rna_secondary_structure/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10722 | Quantify Biofilm Biomass Crystal Violet | `nextflow_nfcore/subworkflows/microbiology/quantify_biofilm_biomass_crystal_violet/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10723 | Segment And Analyze Microbial Cells | `nextflow_nfcore/subworkflows/microbiology/segment_and_analyze_microbial_cells/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10724 | Segment Cells With Deep Learning | `nextflow_nfcore/subworkflows/microbiology/segment_cells_with_deep_learning/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10725 | Simulate Generalized Lotka Volterra Dynamics | `nextflow_nfcore/subworkflows/microbiology/simulate_generalized_lotka_volterra_dynamics/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10726 | Simulate Microbial Population Dynamics | `nextflow_nfcore/subworkflows/microbiology/simulate_microbial_population_dynamics/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 10727 | Vfa Production Model | `nextflow_nfcore/subworkflows/microbiology/vfa_production_model/main.nf` | microbiology | `biomate/biomni-tools:latest` |
| 12656 | Simulate Microbial Population Dynamics | `nextflow_nfcore/microbiology/simulate_microbial_population_dynamics/main.nf` | microbiology | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-microbiology:latest` |
| 10728 | Align Sequences | `nextflow_nfcore/subworkflows/molecular_biology/align_sequences/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10729 | Annotate Open Reading Frames | `nextflow_nfcore/subworkflows/molecular_biology/annotate_open_reading_frames/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10730 | Annotate Plasmid | `nextflow_nfcore/subworkflows/molecular_biology/annotate_plasmid/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10731 | Design Golden Gate Oligos | `nextflow_nfcore/subworkflows/molecular_biology/design_golden_gate_oligos/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10732 | Design Knockout Sgrna | `nextflow_nfcore/subworkflows/molecular_biology/design_knockout_sgrna/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10733 | Design Primer | `nextflow_nfcore/subworkflows/molecular_biology/design_primer/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10734 | Design Verification Primers | `nextflow_nfcore/subworkflows/molecular_biology/design_verification_primers/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10735 | Digest Sequence | `nextflow_nfcore/subworkflows/molecular_biology/digest_sequence/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10736 | Find Orfs In Frame | `nextflow_nfcore/subworkflows/molecular_biology/find_orfs_in_frame/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10737 | Find Restriction Enzymes | `nextflow_nfcore/subworkflows/molecular_biology/find_restriction_enzymes/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10738 | Find Restriction Sites | `nextflow_nfcore/subworkflows/molecular_biology/find_restriction_sites/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10739 | Find Sequence Mutations | `nextflow_nfcore/subworkflows/molecular_biology/find_sequence_mutations/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10740 | Get Bacterial Transformation Protocol | `nextflow_nfcore/subworkflows/molecular_biology/get_bacterial_transformation_protocol/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10741 | Get Coding Sequences | `nextflow_nfcore/subworkflows/molecular_biology/get_coding_sequences/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10742 | Get Gene Coding Sequence | `nextflow_nfcore/subworkflows/molecular_biology/get_gene_coding_sequence/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10743 | Get Golden Gate Assembly Protocol | `nextflow_nfcore/subworkflows/molecular_biology/get_golden_gate_assembly_protocol/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10744 | Get Oligo Annealing Protocol | `nextflow_nfcore/subworkflows/molecular_biology/get_oligo_annealing_protocol/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10745 | Get Plasmid Sequence | `nextflow_nfcore/subworkflows/molecular_biology/get_plasmid_sequence/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10746 | Get Refseq Id | `nextflow_nfcore/subworkflows/molecular_biology/get_refseq_id/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10747 | Golden Gate Assembly | `nextflow_nfcore/subworkflows/molecular_biology/golden_gate_assembly/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10748 | Is Position Covered | `nextflow_nfcore/subworkflows/molecular_biology/is_position_covered/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10749 | Is Region Fully Covered | `nextflow_nfcore/subworkflows/molecular_biology/is_region_fully_covered/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10750 | Merge Overlapping Regions | `nextflow_nfcore/subworkflows/molecular_biology/merge_overlapping_regions/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10751 | Pcr Simple | `nextflow_nfcore/subworkflows/molecular_biology/pcr_simple/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10752 | Reverse Complement | `nextflow_nfcore/subworkflows/molecular_biology/reverse_complement/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 10753 | Search Gene | `nextflow_nfcore/subworkflows/molecular_biology/search_gene/main.nf` | molecular_biology | `biomate/biomni-tools:latest` |
| 12657 | Find Orfs In Frame | `nextflow_nfcore/molecular_biology/find_orfs_in_frame/main.nf` | molecular_biology | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` |
| 12658 | Get Coding Sequences | `nextflow_nfcore/molecular_biology/get_coding_sequences/main.nf` | molecular_biology | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` |
| 12659 | Is Position Covered | `nextflow_nfcore/molecular_biology/is_position_covered/main.nf` | molecular_biology | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` |
| 12660 | Is Region Fully Covered | `nextflow_nfcore/molecular_biology/is_region_fully_covered/main.nf` | molecular_biology | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` |
| 12821 | Lc Ms Proteomics Metabolomics | `nextflow_nfcore/subworkflows/multi_omics/lc_ms_proteomics_metabolomics/main.nf` | multi_omics | `—` |
| 10754 | Analyze Aortic Diameter And Geometry | `nextflow_nfcore/subworkflows/pathology/analyze_aortic_diameter_and_geometry/main.nf` | pathology | `biomate/biomni-tools:latest` |
| 10755 | Analyze Atp Luminescence Assay | `nextflow_nfcore/subworkflows/pathology/analyze_atp_luminescence_assay/main.nf` | pathology | `biomate/biomni-tools:latest` |
| 10756 | Analyze Bone Microct Morphometry | `nextflow_nfcore/subworkflows/pathology/analyze_bone_microct_morphometry/main.nf` | pathology | `biomate/biomni-tools:latest` |
| 10757 | Analyze Intracellular Calcium With Rhod2 | `nextflow_nfcore/subworkflows/pathology/analyze_intracellular_calcium_with_rhod2/main.nf` | pathology | `biomate/biomni-tools:latest` |
| 10758 | Analyze Thrombus Histology | `nextflow_nfcore/subworkflows/pathology/analyze_thrombus_histology/main.nf` | pathology | `biomate/biomni-tools:latest` |
| 10759 | Quantify Corneal Nerve Fibers | `nextflow_nfcore/subworkflows/pathology/quantify_corneal_nerve_fibers/main.nf` | pathology | `biomate/biomni-tools:latest` |
| 10760 | Segment And Quantify Cells In Multiplexed Images | `nextflow_nfcore/subworkflows/pathology/segment_and_quantify_cells_in_multiplexed_images/main.nf` | pathology | `biomate/biomni-tools:latest` |
| 10790 | Analyze Abr Waveform P1 Metrics | `nextflow_nfcore/subworkflows/physiology/analyze_abr_waveform_p1_metrics/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10791 | Analyze Ciliary Beat Frequency | `nextflow_nfcore/subworkflows/physiology/analyze_ciliary_beat_frequency/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10792 | Analyze Endolysosomal Calcium Dynamics | `nextflow_nfcore/subworkflows/physiology/analyze_endolysosomal_calcium_dynamics/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10793 | Analyze Fatty Acid Composition By Gc | `nextflow_nfcore/subworkflows/physiology/analyze_fatty_acid_composition_by_gc/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10794 | Analyze Hemodynamic Data | `nextflow_nfcore/subworkflows/physiology/analyze_hemodynamic_data/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10795 | Analyze Protein Colocalization | `nextflow_nfcore/subworkflows/physiology/analyze_protein_colocalization/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10796 | Calculate Brain Adc Map | `nextflow_nfcore/subworkflows/physiology/calculate_brain_adc_map/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10797 | Cosinor Model | `nextflow_nfcore/subworkflows/physiology/cosinor_model/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10798 | Mono Exp Model | `nextflow_nfcore/subworkflows/physiology/mono_exp_model/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10799 | Perform Cosinor Analysis | `nextflow_nfcore/subworkflows/physiology/perform_cosinor_analysis/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10800 | Pk Ode System | `nextflow_nfcore/subworkflows/physiology/pk_ode_system/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10801 | Quantify Amyloid Beta Plaques | `nextflow_nfcore/subworkflows/physiology/quantify_amyloid_beta_plaques/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10802 | Reconstruct 3D Face From Mri | `nextflow_nfcore/subworkflows/physiology/reconstruct_3d_face_from_mri/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10803 | Simulate Thyroid Hormone Pharmacokinetics | `nextflow_nfcore/subworkflows/physiology/simulate_thyroid_hormone_pharmacokinetics/main.nf` | physiology | `biomate/biomni-tools:latest` |
| 10804 | Chemoproteomics Pulldown | `nextflow_nfcore/subworkflows/proteomics/chemoproteomics_pulldown/main.nf` | proteomics | `biomate/biomni-tools:latest` |
| 10805 | Analyze Bacterial Growth Rate | `nextflow_nfcore/subworkflows/synthetic_biology/analyze_bacterial_growth_rate/main.nf` | synthetic_biology | `biomate/biomni-tools:latest` |
| 10806 | Analyze Barcode Sequencing Data | `nextflow_nfcore/subworkflows/synthetic_biology/analyze_barcode_sequencing_data/main.nf` | synthetic_biology | `biomate/biomni-tools:latest` |
| 10807 | Analyze Bifurcation Diagram | `nextflow_nfcore/subworkflows/synthetic_biology/analyze_bifurcation_diagram/main.nf` | synthetic_biology | `biomate/biomni-tools:latest` |
| 10808 | Create Biochemical Network Sbml Model | `nextflow_nfcore/subworkflows/synthetic_biology/create_biochemical_network_sbml_model/main.nf` | synthetic_biology | `biomate/biomni-tools:latest` |
| 10809 | Engineer Bacterial Genome For Therapeutic Delivery | `nextflow_nfcore/subworkflows/synthetic_biology/engineer_bacterial_genome_for_therapeutic_delivery/main.nf` | synthetic_biology | `biomate/biomni-tools:latest` |
| 10810 | Gene Circuit Odes | `nextflow_nfcore/subworkflows/synthetic_biology/gene_circuit_odes/main.nf` | synthetic_biology | `biomate/biomni-tools:latest` |
| 10811 | Gompertz Model | `nextflow_nfcore/subworkflows/synthetic_biology/gompertz_model/main.nf` | synthetic_biology | `biomate/biomni-tools:latest` |
| 10812 | Hamming Distance | `nextflow_nfcore/subworkflows/synthetic_biology/hamming_distance/main.nf` | synthetic_biology | `biomate/biomni-tools:latest` |
| 10813 | Optimize Codons For Heterologous Expression | `nextflow_nfcore/subworkflows/synthetic_biology/optimize_codons_for_heterologous_expression/main.nf` | synthetic_biology | `biomate/biomni-tools:latest` |
| 10814 | Simulate Gene Circuit With Growth Feedback | `nextflow_nfcore/subworkflows/synthetic_biology/simulate_gene_circuit_with_growth_feedback/main.nf` | synthetic_biology | `biomate/biomni-tools:latest` |
| 12665 | Analyze Bifurcation Diagram | `nextflow_nfcore/synthetic_biology/analyze_bifurcation_diagram/main.nf` | synthetic_biology | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` |
| 10815 | Compare Protein Structures | `nextflow_nfcore/subworkflows/systems_biology/compare_protein_structures/main.nf` | systems_biology | `biomate/biomni-tools:latest` |
| 10816 | Dimerization Odes | `nextflow_nfcore/subworkflows/systems_biology/dimerization_odes/main.nf` | systems_biology | `biomate/biomni-tools:latest` |
| 10817 | Hill Function | `nextflow_nfcore/subworkflows/systems_biology/hill_function/main.nf` | systems_biology | `biomate/biomni-tools:latest` |
| 10818 | Mass Action Kinetics | `nextflow_nfcore/subworkflows/systems_biology/mass_action_kinetics/main.nf` | systems_biology | `biomate/biomni-tools:latest` |
| 10819 | Model Protein Dimerization Network | `nextflow_nfcore/subworkflows/systems_biology/model_protein_dimerization_network/main.nf` | systems_biology | `biomate/biomni-tools:latest` |
| 10820 | Ode System | `nextflow_nfcore/subworkflows/systems_biology/ode_system/main.nf` | systems_biology | `biomate/biomni-tools:latest` |
| 10821 | Perform Flux Balance Analysis | `nextflow_nfcore/subworkflows/systems_biology/perform_flux_balance_analysis/main.nf` | systems_biology | `biomate/biomni-tools:latest` |
| 10822 | Query Chatnt | `nextflow_nfcore/subworkflows/systems_biology/query_chatnt/main.nf` | systems_biology | `biomate/biomni-tools:latest` |
| 10823 | Ras Ode System | `nextflow_nfcore/subworkflows/systems_biology/ras_ode_system/main.nf` | systems_biology | `biomate/biomni-tools:latest` |
| 10824 | Simulate Metabolic Network Perturbation | `nextflow_nfcore/subworkflows/systems_biology/simulate_metabolic_network_perturbation/main.nf` | systems_biology | `biomate/biomni-tools:latest` |
| 10825 | Simulate Protein Signaling Network | `nextflow_nfcore/subworkflows/systems_biology/simulate_protein_signaling_network/main.nf` | systems_biology | `biomate/biomni-tools:latest` |
| 10826 | Simulate Renin Angiotensin System Dynamics | `nextflow_nfcore/subworkflows/systems_biology/simulate_renin_angiotensin_system_dynamics/main.nf` | systems_biology | `biomate/biomni-tools:latest` |
| 12666 | Dimerization Odes | `nextflow_nfcore/systems_biology/dimerization_odes/main.nf` | systems_biology | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` |
| 12667 | Model Protein Dimerization Network | `nextflow_nfcore/systems_biology/model_protein_dimerization_network/main.nf` | systems_biology | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` |
| 12668 | Simulate Protein Signaling Network | `nextflow_nfcore/systems_biology/simulate_protein_signaling_network/main.nf` | systems_biology | `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest` |
| 10828 | biomni_biophysics_predict_protein_disorder_regions | `galaxy/subworkflows/biophysics/predict_protein_disorder_regions.ga` | biophysics | `—` |
| 10827 | biomni_synthetic_biology_identify_fas_functional_domains | `galaxy/subworkflows/synthetic_biology/identify_fas_functional_domains.ga` | synthetic_biology | `—` |

## Full CSV
Complete machine-readable registry: `docs/20260419_WORKFLOW_REGISTRY.csv`
Columns: id, name, path/filename, domain, category, source, format, docker_image, step_count, tools_used, input_types, output_types, executable, tags, description
