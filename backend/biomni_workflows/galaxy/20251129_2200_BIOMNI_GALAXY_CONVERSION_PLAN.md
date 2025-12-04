# Biomni to Galaxy Subworkflow Conversion Plan

**Date:** November 29, 2025, 22:00 UTC
**Author:** BioMate Development Team
**Status:** Active Development

---

## Executive Summary

This document outlines the comprehensive plan to convert all 185+ Biomni functions into Galaxy subworkflows. Based on the key insight that **every Biomni function represents a biological logic unit** (regardless of complexity), each function will be converted to a Galaxy subworkflow that can be composed into larger workflows.

### Key Principle

> **Biological Logic = Subworkflow Name**
>
> Each Biomni function encapsulates a biological logic step. In Galaxy, this becomes a subworkflow that:
> 1. Has a name describing the biological logic (e.g., `annotate_open_reading_frames`)
> 2. Contains internal tool calls as workflow steps
> 3. Can be nested within larger workflows (Galaxy 25.0+ feature)

---

## 1. Function Inventory by Domain

### 1.1 Genomics (21 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `unsupervised_celltype_transfer_between_scRNA_datasets` | 18 | scvi, scanpy | High |
| `interspecies_gene_conversion` | 108 | gget, BioMart API | Medium |
| `generate_gene_embeddings_with_ESM_models` | 314 | ESM, torch | High |
| `annotate_celltype_scRNA` | 463 | LLM, scanpy | High |
| `annotate_celltype_with_panhumanpy` | 600 | panhumanpy | Medium |
| `create_scvi_embeddings_scRNA` | 801 | scvi | Medium |
| `create_harmony_embeddings_scRNA` | 842 | harmony | Medium |
| `get_uce_embeddings_scRNA` | 861 | UCE model | High |
| `map_to_ima_interpret_scRNA` | 914 | IMA | High |
| `get_rna_seq_archs4` | 974 | ARCHS4 API | Low |
| `get_gene_set_enrichment_analysis_supported_database_list` | 1017 | gseapy | Low |
| `gene_set_enrichment_analysis` | 1021 | gseapy, gget | Medium |
| `analyze_chromatin_interactions` | 1091 | cooler, hicstraw | High |
| `analyze_comparative_genomics_and_haplotypes` | 1424 | bwa, samtools | High |
| `perform_chipseq_peak_calling_with_macs2` | 1617 | MACS2 | Medium |
| `find_enriched_motifs_with_homer` | 1794 | HOMER | Medium |
| `analyze_genomic_region_overlap` | 1965 | bedtools | Medium |
| `generate_embeddings_with_state` | 2167 | STATE model | High |
| `generate_transcriptformer_embeddings` | 2422 | Transcriptformer | High |

### 1.2 Database (45+ functions)
| Function | Line | External API | Complexity |
|----------|------|--------------|------------|
| `get_hpo_names` | 17 | HPO data lake | Low |
| `query_uniprot` | 448 | UniProt REST | Medium |
| `query_alphafold` | 544 | AlphaFold API | Medium |
| `query_interpro` | 693 | InterPro API | Medium |
| `query_pdb` | 800 | PDB REST | Medium |
| `query_pdb_identifiers` | 917 | PDB REST | Low |
| `query_kegg` | 1030 | KEGG API | Medium |
| `query_stringdb` | 1119 | STRING API | Medium |
| `query_iucn` | 1286 | IUCN API | Medium |
| `query_paleobiology` | 1393 | PBDB API | Medium |
| `query_jaspar` | 1521 | JASPAR API | Medium |
| `query_worms` | 1625 | WoRMS API | Medium |
| `query_cbioportal` | 1722 | cBioPortal API | Medium |
| `query_clinvar` | 1824 | ClinVar API | Medium |
| `query_geo` | 1907 | GEO API | Medium |
| `query_dbsnp` | 2005 | dbSNP API | Medium |
| `query_ucsc` | 2093 | UCSC API | Medium |
| `query_ensembl` | 2195 | Ensembl REST | Medium |
| `query_opentarget` | 2315 | OpenTargets API | Medium |
| `query_monarch` | 2416 | Monarch API | Medium |
| `query_openfda` | 2530 | OpenFDA API | Medium |
| `query_gwas_catalog` | 2652 | GWAS Catalog | Medium |
| `query_gnomad` | 2753 | gnomAD API | Medium |
| `blast_sequence` | 2852 | NCBI BLAST | High |
| `query_reactome` | 2954 | Reactome API | Medium |
| `query_regulomedb` | 3120 | RegulomeDB API | Medium |
| `query_pride` | 3208 | PRIDE API | Medium |
| `query_gtopdb` | 3307 | GtoPdb API | Medium |
| `region_to_ccre_screen` | 3409 | SCREEN API | Medium |
| `get_genes_near_ccre` | 3516 | SCREEN API | Low |
| `query_remap` | 3575 | ReMap API | Medium |
| `query_mpd` | 3676 | MPD API | Medium |
| `query_emdb` | 3777 | EMDB API | Medium |
| `query_synapse` | 3882 | Synapse API | Medium |
| `query_pubchem` | 4032 | PubChem API | Medium |
| `query_chembl` | 4134 | ChEMBL API | Medium |
| `query_unichem` | 4374 | UniChem API | Medium |
| `query_clinicaltrials` | 4486 | ClinicalTrials API | Medium |
| `query_dailymed` | 4602 | DailyMed API | Medium |
| `query_quickgo` | 4706 | QuickGO API | Medium |
| `query_encode` | 4819 | ENCODE API | Medium |

### 1.3 Molecular Biology (18 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `annotate_open_reading_frames` | 15 | Biopython | Low |
| `annotate_plasmid` | 167 | Biopython | Medium |
| `get_gene_coding_sequence` | 252 | NCBI Entrez | Medium |
| `get_plasmid_sequence` | 330 | Addgene API | Medium |
| `align_sequences` | 422 | Biopython | Low |
| `pcr_simple` | 496 | align_sequences (internal) | Medium |
| `digest_sequence` | 602 | Biopython | Low |
| `find_restriction_sites` | 725 | Biopython | Low |
| `find_restriction_enzymes` | 791 | Biopython | Low |
| `find_sequence_mutations` | 822 | Biopython | Low |
| `design_knockout_sgrna` | 876 | Biopython | Medium |
| `get_oligo_annealing_protocol` | 951 | Static | Low |
| `get_golden_gate_assembly_protocol` | 1006 | Static | Low |
| `get_bacterial_transformation_protocol` | 1196 | Static | Low |
| `design_primer` | 1277 | primer3 | Medium |
| `design_verification_primers` | 1353 | primer3 | Medium |
| `design_golden_gate_oligos` | 1699 | Biopython | Medium |
| `golden_gate_assembly` | 1849 | Biopython | High |

### 1.4 Pharmacology (25+ functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `run_diffdock_with_smiles` | 13 | DiffDock | High |
| `docking_autodock_vina` | 96 | AutoDock Vina | High |
| `run_autosite` | 136 | AutoSite | Medium |
| `retrieve_topk_repurposing_drugs_from_disease_txgnn` | 184 | TxGNN | High |
| `predict_admet_properties` | 249 | DeepPurpose | High |
| `predict_binding_affinity_protein_1d_sequence` | 364 | DeepPurpose | High |
| `analyze_accelerated_stability_of_pharmaceutical_formulations` | 414 | scipy | Medium |
| `run_3d_chondrogenic_aggregate_assay` | 577 | skimage | Medium |
| `grade_adverse_events_using_vcog_ctcae` | 682 | pandas | Medium |
| `analyze_radiolabeled_antibody_biodistribution` | 1073 | scipy | Medium |
| `estimate_alpha_particle_radiotherapy_dosimetry` | 1209 | scipy | High |
| `perform_mwas_cyp2c19_metabolizer_status` | 1321 | statsmodels | High |
| `calculate_physicochemical_properties` | 1523 | RDKit | Low |
| `analyze_xenograft_tumor_growth_inhibition` | 1616 | scipy | Medium |
| `analyze_western_blot` | 1864 | skimage | Medium |
| `query_drug_interactions` | 2311 | DDInter data | Medium |
| `check_drug_combination_safety` | 2442 | DDInter | Medium |
| `analyze_interaction_mechanisms` | 2607 | DDInter | Medium |
| `find_alternative_drugs_ddinter` | 2763 | DDInter | High |
| `query_fda_adverse_events` | 3571 | OpenFDA API | Medium |
| `get_fda_drug_label_info` | 3654 | OpenFDA API | Medium |
| `check_fda_drug_recalls` | 3692 | OpenFDA API | Medium |
| `analyze_fda_safety_signals` | 3741 | OpenFDA API | Medium |

### 1.5 Immunology (10 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `analyze_atac_seq_differential_accessibility` | 1 | pyatac, scanpy | High |
| `analyze_bacterial_growth_curve` | 185 | scipy | Medium |
| `isolate_purify_immune_cells` | 311 | Protocol | Low |
| `estimate_cell_cycle_phase_durations` | 448 | scipy | High |
| `track_immune_cells_under_flow` | 633 | TrackMate | High |
| `analyze_cfse_cell_proliferation` | 969 | flowkit | High |
| `analyze_cytokine_production_in_cd4_tcells` | 1178 | flowkit | High |
| `analyze_ebv_antibody_titers` | 1331 | scipy | Medium |
| `analyze_cns_lesion_histology` | 1490 | skimage, SAM | High |
| `analyze_immunohistochemistry_image` | 1848 | skimage | High |

### 1.6 Genetics (9 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `liftover_coordinates` | 1 | liftover | Low |
| `bayesian_finemapping_with_deep_vi` | 80 | DeepVI | High |
| `analyze_cas9_mutation_outcomes` | 323 | Biopython | Medium |
| `analyze_crispr_genome_editing` | 510 | Biopython | Medium |
| `simulate_demographic_history` | 646 | msprime | High |
| `identify_transcription_factor_binding_sites` | 851 | MEME | High |
| `fit_genomic_prediction_model` | 975 | sklearn | High |
| `perform_pcr_and_gel_electrophoresis` | 1237 | skimage | Medium |
| `analyze_protein_phylogeny` | 1445 | BioPython, MAFFT | High |

### 1.7 Microbiology (12 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `optimize_anaerobic_digestion_process` | 1 | scipy | High |
| `analyze_arsenic_speciation_hplc_icpms` | 256 | pandas | Medium |
| `count_bacterial_colonies` | 393 | skimage | Medium |
| `annotate_bacterial_genome` | 529 | Prokka | High |
| `enumerate_bacterial_cfu_by_serial_dilution` | 662 | pandas | Low |
| `model_bacterial_growth_dynamics` | 808 | scipy | Medium |
| `quantify_biofilm_biomass_crystal_violet` | 897 | scipy | Medium |
| `segment_and_analyze_microbial_cells` | 999 | skimage | Medium |
| `segment_cells_with_deep_learning` | 1113 | Cellpose | High |
| `simulate_generalized_lotka_volterra_dynamics` | 1265 | scipy | High |
| `predict_rna_secondary_structure` | 1355 | RNAfold | Medium |
| `simulate_microbial_population_dynamics` | 1431 | scipy | High |

### 1.8 Bioengineering (7 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `analyze_cell_migration_metrics` | 1 | skimage | Medium |
| `perform_crispr_cas9_genome_editing` | 234 | Biopython | High |
| `analyze_calcium_imaging_data` | 402 | scipy, skimage | High |
| `analyze_in_vitro_drug_release_kinetics` | 595 | scipy | Medium |
| `analyze_myofiber_morphology` | 893 | skimage | High |
| `decode_behavior_from_neural_trajectories` | 1062 | sklearn, scipy | High |
| `simulate_whole_cell_ode_model` | 1243 | scipy | High |

### 1.9 Synthetic Biology (8 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `engineer_bacterial_genome_for_therapeutic_delivery` | 1 | Biopython | High |
| `analyze_bacterial_growth_rate` | 225 | scipy | Medium |
| `analyze_barcode_sequencing_data` | 356 | pandas | Medium |
| `analyze_bifurcation_diagram` | 515 | scipy | High |
| `create_biochemical_network_sbml_model` | 706 | libsbml | High |
| `optimize_codons_for_heterologous_expression` | 860 | Biopython | Medium |
| `simulate_gene_circuit_with_growth_feedback` | 973 | scipy | High |
| `identify_fas_functional_domains` | 1152 | Biopython | Medium |

### 1.10 Cancer Biology (6 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `analyze_ddr_network_in_cancer` | 1 | pandas, networkx | High |
| `analyze_cell_senescence_and_apoptosis` | 268 | flowkit | High |
| `detect_and_annotate_somatic_mutations` | 422 | VEP, Biopython | High |
| `detect_and_characterize_structural_variations` | 571 | pysam | High |
| `perform_gene_expression_nmf_analysis` | 821 | sklearn | High |
| `analyze_copy_number_purity_ploidy_and_focal_events` | 953 | ASCAT-like | High |

### 1.11 Physiology (11 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `reconstruct_3d_face_from_mri` | 1 | nibabel, skimage | High |
| `analyze_abr_waveform_p1_metrics` | 150 | scipy | Medium |
| `analyze_ciliary_beat_frequency` | 217 | scipy, skimage | High |
| `analyze_protein_colocalization` | 365 | skimage | Medium |
| `perform_cosinor_analysis` | 516 | scipy | Medium |
| `calculate_brain_adc_map` | 613 | nibabel | High |
| `analyze_endolysosomal_calcium_dynamics` | 738 | scipy | High |
| `analyze_fatty_acid_composition_by_gc` | 889 | pandas | Medium |
| `analyze_hemodynamic_data` | 1015 | scipy | Medium |
| `simulate_thyroid_hormone_pharmacokinetics` | 1099 | scipy | High |
| `quantify_amyloid_beta_plaques` | 1251 | skimage | High |

### 1.12 Pathology (7 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `analyze_aortic_diameter_and_geometry` | 1 | skimage | High |
| `analyze_atp_luminescence_assay` | 206 | scipy | Medium |
| `analyze_thrombus_histology` | 352 | skimage | High |
| `analyze_intracellular_calcium_with_rhod2` | 507 | skimage | High |
| `quantify_corneal_nerve_fibers` | 605 | skimage | High |
| `segment_and_quantify_cells_in_multiplexed_images` | 745 | skimage | High |
| `analyze_bone_microct_morphometry` | 896 | nibabel | High |

### 1.13 Biochemistry (6 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `analyze_circular_dichroism_spectra` | 1 | scipy | Medium |
| `analyze_rna_secondary_structure_features` | 160 | Biopython | Medium |
| `analyze_protease_kinetics` | 307 | scipy | Medium |
| `analyze_enzyme_kinetics_assay` | 458 | scipy | Medium |
| `analyze_itc_binding_thermodynamics` | 670 | scipy | High |
| `analyze_protein_conservation` | 872 | Biopython, MAFFT | High |

### 1.14 Systems Biology (7 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `query_chatnt` | 1 | ChatNT API | Medium |
| `perform_flux_balance_analysis` | 33 | COBRApy | High |
| `model_protein_dimerization_network` | 150 | scipy | High |
| `simulate_metabolic_network_perturbation` | 294 | COBRApy | High |
| `simulate_protein_signaling_network` | 460 | scipy | High |
| `compare_protein_structures` | 605 | pymol, biotite | High |
| `simulate_renin_angiotensin_system_dynamics` | 775 | scipy | High |

### 1.15 Cell Biology (5 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `quantify_cell_cycle_phases_from_microscopy` | 1 | skimage | High |
| `quantify_and_cluster_cell_motility` | 162 | trackpy, sklearn | High |
| `perform_facs_cell_sorting` | 369 | Protocol | Low |
| `analyze_flow_cytometry_immunophenotyping` | 473 | flowkit | High |
| `analyze_mitochondrial_morphology_and_potential` | 574 | skimage | High |

### 1.16 Biophysics (3 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `predict_protein_disorder_regions` | 1 | IUPred2A | Medium |
| `analyze_cell_morphology_and_cytoskeleton` | 124 | skimage | High |
| `analyze_tissue_deformation_flow` | 324 | scikit-image, opencv | High |

### 1.17 Glycoengineering (3 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `find_n_glycosylation_motifs` | 9 | regex | Low |
| `predict_o_glycosylation_hotspots` | 49 | ML model | Medium |
| `list_glycoengineering_resources` | 115 | Static | Low |

### 1.18 Literature & Protocols (10 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `fetch_supplementary_info_from_doi` | 13 | requests | Medium |
| `query_arxiv` | 90 | arxiv API | Low |
| `query_scholar` | 114 | scholarly | Medium |
| `query_pubmed` | 144 | NCBI Entrez | Low |
| `search_google` | 186 | googlesearch | Medium |
| `advanced_web_search_claude` | 218 | Claude API | High |
| `extract_url_content` | 303 | requests, BeautifulSoup | Medium |
| `extract_pdf_content` | 343 | PyPDF2 | Medium |
| `search_protocols` | 29 | protocols.io API | Low |
| `get_protocol_details` | 134 | protocols.io API | Low |

### 1.19 Support & Lab Automation (5+ functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `run_python_repl` | 13 | exec() | High |
| `read_function_source_code` | 141 | inspect | Low |
| `download_synapse_data` | 199 | synapseclient | Medium |
| `get_pylabrobot_documentation_liquid` | 209 | GitHub API | Low |
| `test_pylabrobot_script` | 232 | PyLabRobot | High |

### 1.20 Bioimaging (10 functions)
| Function | Line | Internal Tools | Complexity |
|----------|------|----------------|------------|
| `split_modalities` | 965 | nibabel | Low |
| `prepare_input_for_nnunet` | 971 | nibabel | Medium |
| `segment_with_nn_unet` | 977 | nnU-Net | High |
| `create_segmentation_visualization` | 1007 | matplotlib | Low |
| `preprocess_image` | 1014 | skimage | Medium |
| `quick_rigid_registration` | 1034 | ants | High |
| `quick_affine_registration` | 1110 | ants | High |
| `quick_deformable_registration` | 1186 | ants | High |
| `batch_register_images` | 1264 | ants | High |
| `calculate_similarity_metrics` | 1380 | skimage | Medium |

---

## 2. Conversion Architecture

### 2.1 Galaxy Subworkflow Structure

Each Biomni function will be converted to a Galaxy subworkflow with this structure:

```json
{
  "a_galaxy_workflow": "true",
  "format-version": "0.1",
  "name": "biomni_{domain}_{function_name}",
  "tags": ["biomni", "{domain}", "subworkflow"],
  "annotation": "{function_docstring}",
  "steps": {
    "0": {"type": "data_input", "label": "input_1"},
    "1": {"type": "tool", "tool_id": "{internal_tool_id}"},
    "...": "additional steps as needed"
  }
}
```

### 2.2 Tool Mapping Categories

| Category | Count | Conversion Strategy |
|----------|-------|---------------------|
| **CLI Wrappers** | ~20 | Map to existing Galaxy tools (MACS2, samtools, etc.) |
| **Python Libraries** | ~100 | Create Galaxy tool wrappers with Python scripts |
| **REST APIs** | ~45 | Create Galaxy data source tools |
| **LLM-Dependent** | ~10 | Integrate with BioMate AI assistant |
| **Static/Protocol** | ~10 | Create Galaxy text output tools |

### 2.3 Internal Tool Call Patterns

Functions that call other Biomni functions internally:

| Parent Function | Calls | Domain |
|-----------------|-------|--------|
| `pcr_simple` | `align_sequences` | molecular_biology |
| `golden_gate_assembly` | `digest_sequence`, `find_restriction_sites` | molecular_biology |
| `gene_set_enrichment_analysis` | `gget.enrichr` | genomics |
| `annotate_celltype_scRNA` | LLM + `scanpy` functions | genomics |

These become **nested subworkflows** in Galaxy.

---

## 3. Implementation Phases

### Phase 1: Core Infrastructure (Week 1)
- [ ] Create biomni_galaxy tool wrapper template
- [ ] Implement automatic XML generator from function signatures
- [ ] Set up Galaxy tool repository structure
- [ ] Create data type mappings (Python types → Galaxy types)

### Phase 2: Low Complexity Functions (Weeks 2-3)
- [ ] Convert 50 "Low" complexity functions
- [ ] Focus on: molecular_biology, glycoengineering, protocols
- [ ] Test in BioMate Galaxy instance

### Phase 3: Medium Complexity Functions (Weeks 4-6)
- [ ] Convert 80 "Medium" complexity functions
- [ ] Focus on: database queries, biochemistry, basic genomics
- [ ] Implement REST API wrappers

### Phase 4: High Complexity Functions (Weeks 7-10)
- [ ] Convert 55 "High" complexity functions
- [ ] Focus on: deep learning models, multi-step analyses
- [ ] GPU support for ML tools

### Phase 5: Integration & Composition (Weeks 11-12)
- [ ] Create composite workflows from subworkflows
- [ ] Test nested subworkflow functionality
- [ ] Document all converted tools

---

## 4. Conversion Script Design

### 4.1 Automatic XML Generator

```python
# biomni_to_galaxy_converter.py
def generate_galaxy_tool_xml(function_name, domain, params, docstring):
    """Generate Galaxy tool XML from Biomni function signature."""
    return f'''<tool id="biomni_{domain}_{function_name}"
               name="Biomni: {function_name.replace('_', ' ').title()}"
               version="1.0.0">
    <description>{docstring}</description>
    <requirements>
        <requirement type="package">biomni</requirement>
    </requirements>
    <command><![CDATA[
        python '$__tool_directory__/{function_name}.py'
        {generate_param_cli(params)}
        --output '$output'
    ]]></command>
    <inputs>
        {generate_inputs_xml(params)}
    </inputs>
    <outputs>
        <data name="output" format="json" label="{function_name} results"/>
    </outputs>
</tool>'''
```

### 4.2 Subworkflow Generator

```python
def generate_galaxy_subworkflow(function_name, domain, internal_calls):
    """Generate Galaxy subworkflow JSON from Biomni function."""
    steps = {}
    for i, call in enumerate(internal_calls):
        steps[str(i)] = {
            "type": "subworkflow" if is_biomni_function(call) else "tool",
            "tool_id": get_tool_id(call),
            "position": {"left": 200 * i, "top": 200}
        }
    return {
        "a_galaxy_workflow": "true",
        "name": f"biomni_{domain}_{function_name}",
        "steps": steps
    }
```

---

## 5. Data Type Mapping

| Python Type | Galaxy Data Type | Notes |
|-------------|------------------|-------|
| `str` (sequence) | `fasta` | DNA/RNA/Protein sequences |
| `str` (path to h5ad) | `h5ad` | scRNA-seq AnnData |
| `str` (path to bam) | `bam` | Alignment files |
| `str` (path to vcf) | `vcf` | Variant files |
| `str` (path to pdb) | `pdb` | Protein structures |
| `list[str]` (genes) | `txt` | Gene lists |
| `pd.DataFrame` | `tabular` | Tabular data |
| `dict` (results) | `json` | Structured output |
| `np.ndarray` (image) | `png/tiff` | Image data |
| `float/int` | `integer/float` | Numeric parameters |
| `bool` | `boolean` | Boolean flags |

---

## 6. Quality Assurance

### 6.1 Testing Strategy
1. **Unit Tests**: Each converted tool tested individually
2. **Integration Tests**: Subworkflow composition verified
3. **Regression Tests**: Compare Biomni vs Galaxy outputs
4. **User Acceptance**: Biologist validation of workflows

### 6.2 Documentation Requirements
- Tool help text from function docstrings
- Input/output format specifications
- Example datasets for each domain
- Workflow composition tutorials

---

## 7. Timeline Summary

| Phase | Duration | Deliverables |
|-------|----------|--------------|
| Phase 1 | Week 1 | Infrastructure, templates, converter script |
| Phase 2 | Weeks 2-3 | 50 low-complexity tools converted |
| Phase 3 | Weeks 4-6 | 80 medium-complexity tools converted |
| Phase 4 | Weeks 7-10 | 55 high-complexity tools converted |
| Phase 5 | Weeks 11-12 | Integration, testing, documentation |

**Total: 185+ Biomni functions → 185+ Galaxy subworkflows**

---

## 8. Files to Create

```
biomni_galaxy/
├── 20251129_2200_BIOMNI_GALAXY_CONVERSION_PLAN.md (this file)
├── 20251129_2200_FUNCTION_INVENTORY.csv
├── converter/
│   ├── biomni_to_galaxy_converter.py
│   ├── xml_generator.py
│   ├── subworkflow_generator.py
│   └── type_mapper.py
├── tools/
│   ├── genomics/
│   ├── database/
│   ├── molecular_biology/
│   └── ... (18 domains)
├── subworkflows/
│   └── ... (nested subworkflow definitions)
└── tests/
    └── ... (test cases)
```

---

## 9. Next Actions

1. **Immediate**: Create function inventory CSV with all 185+ functions
2. **Today**: Implement basic XML generator script
3. **This Week**: Convert first 10 functions as proof of concept
4. **Validation**: Test in BioMate Galaxy instance

---

*Document Version: 1.0*
*Last Updated: November 29, 2025, 22:00 UTC*
