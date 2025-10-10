# Galaxy Data Tools and Datasets Reference
**Generated:** 2025-10-09

## Table of Contents

1. [Overview](#overview)
2. [Galaxy Data Source Tools](#galaxy-data-source-tools)
3. [Local Datasets](#local-datasets)
4. [MetaboAnalyst SQLite Databases](#metaboanalyst-sqlite-databases)
5. [API Query Patterns](#api-query-patterns)
6. [Usage Guidelines](#usage-guidelines)

## Overview

This document provides comprehensive reference information for integrating chemical and biological databases into Galaxy workflows.

### Summary Statistics

- **Galaxy Data Tools:** 40
- **Local Datasets:** 115
- **MetaboAnalyst Databases:** 10
- **Total Data Resources:** 165

### Tools by Database Type

- **ChEMBL:** 3 tools
- **HMDB:** 3 tools
- **KEGG:** 12 tools
- **PubChem:** 5 tools
- **Reactome:** 5 tools
- **UniProt:** 5 tools

## Galaxy Data Source Tools

Detailed information about existing Galaxy tools that query chemical and biological databases.

### PubChem Tools (5 tools)

#### Repository Actions
PubChem Download

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/bgruening/chemical_data_sources/Repository_Actions
PubChem_Download`  
**Category:** Computational chemistry  
**Version:** 1.0.0  
**Repository:** bgruening/chemical_data_sources

**Description:** Data sources for small molecules


#### Repository Actions
PubChem Assay Downloader

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/bgruening/chemical_data_sources/Repository_Actions
PubChem_Assay_Downloader`  
**Category:** Computational chemistry  
**Version:** 1.0.0  
**Repository:** bgruening/chemical_data_sources

**Description:** Data sources for small molecules

**Key Parameters:**
  - `scoring_matrix` (text): Scoring matrix
  - `columns_in_the_result_file` (data): Columns in the result file
  - `column_1` (text): column 1
  - `column_1` (text): column 1
  - `column_2` (text): column 2
  - ... and 3 more parameters


#### Repository Actions
PLIDflow: PubChem SMI

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/bitlab/plidflow/Repository_Actions
PLIDflow:_PubChem_SMI`  
**Category:** Computational chemistry  
**Version:** 1.0.0  
**Repository:** bitlab/plidflow

**Description:** PLIDflow: an open-source workflow for the online analysis of protein-ligand docking using Galaxy

**Key Parameters:**
  - `plidflow` (text): PLIDflow
  - `drug_smi_file` (data): Drug SMI file


#### Repository Actions
PubChem Download

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/bgruening/get_pubchem/Repository_Actions
PubChem_Download`  
**Category:** Computational chemistry  
**Version:** 0.3  
**Repository:** bgruening/get_pubchem

**Description:** Access data from the PubChem database


#### Repository Actions
PubChem Assay Downloader

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/bgruening/get_pubchem/Repository_Actions
PubChem_Assay_Downloader`  
**Category:** Computational chemistry  
**Version:** 0.3  
**Repository:** bgruening/get_pubchem

**Description:** Access data from the PubChem database

**Key Parameters:**
  - `scoring_matrix` (text): Scoring matrix
  - `columns_in_the_result_file` (data): Columns in the result file
  - `column_1` (text): column 1
  - `column_1` (text): column 1
  - `column_2` (text): column 2
  - ... and 3 more parameters


### ChEMBL Tools (3 tools)

#### Repository Actions
ChEMBL structure pipeline

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/bgruening/chembl/Repository_Actions
ChEMBL_structure_pipeline`  
**Category:** Computational chemistry  
**Version:** 1.0.0+galaxy0  
**Repository:** bgruening/chembl

**Description:** Python library for accessing the ChEMBL database

**Key Parameters:**
  - `sdf/mol_input` (data): SDF/MOL input
  - `standardize` (text): Standardize
  - `get_parent` (text): Get parent
  - `check` (text): Check
  - `the_pipeline_consists_of_three_components` (text): The pipeline consists of three components


#### Repository Actions
Search ChEMBL database

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/bgruening/chembl/Repository_Actions
Search_ChEMBL_database`  
**Category:** Computational chemistry  
**Version:** 0.10.1+galaxy4  
**Repository:** bgruening/chembl

**Description:** Python library for accessing the ChEMBL database

**Key Parameters:**
  - `smiles_input_type` (data): SMILES input type
  - `smiles_input` (data): SMILES input
  - `search_type` (text): Search type
  - `tanimoto_cutoff_score` (float): Tanimoto cutoff score
  - `filter_to_return_only_approved_drugs` (text): Filter to return only approved drugs
  - ... and 3 more parameters


#### Repository Actions
ChEMBL structure pipeline

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/bgruening/chembl_structure_pipeline/Repository_Actions
ChEMBL_structure_pipeline`  
**Category:** Computational chemistry  
**Version:** 1.0.0+galaxy0  
**Repository:** bgruening/chembl_structure_pipeline

**Description:** ChEMBL structure pipeline tool

**Key Parameters:**
  - `sdf/mol_input` (data): SDF/MOL input
  - `standardize` (text): Standardize
  - `get_parent` (text): Get parent
  - `check` (text): Check
  - `the_pipeline_consists_of_three_components` (text): The pipeline consists of three components


### KEGG Tools (12 tools)

#### Repository Actions
Get gene sets from Msigdb/KEGG

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/mora-lab/geneset_from_msigdb_orkegg/Repository_Actions
Get_gene_sets_from_Msigdb/KEGG`  
**Category:** Genome annotation  
**Version:** 0.1.0  
**Repository:** mora-lab/geneset_from_msigdb_orkegg

**Description:** get gene sets from Msigdb/KEGG

**Key Parameters:**
  - `kegg_or_msigdb` (select): KEGG or MSigDB
  - `organism` (text): organism
  - `c1` (text): C1
  - `c5` (text): C5


#### Repository Actions
KOBAS Annotate

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/iuc/kobas/Repository_Actions
KOBAS_Annotate`  
**Category:** Systems Biology  
**Version:** 2.1.1  
**Repository:** iuc/kobas

**Description:** KOBAS KEGG Orthology Based Annotation System

**Key Parameters:**
  - `input_file` (data): Input file
  - `input_type` (data): Input type
  - `input_data_type,_default_fasta` (data): Input data type, default fasta
  - `blast_protein_database` (data): BLAST Protein database
  - `protein_blast_database` (data): Protein BLAST database
  - ... and 9 more parameters


#### Repository Actions
KOBAS Identify

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/iuc/kobas/Repository_Actions
KOBAS_Identify`  
**Category:** Systems Biology  
**Version:** 2.1.1  
**Repository:** iuc/kobas

**Description:** KOBAS KEGG Orthology Based Annotation System

**Key Parameters:**
  - `foreground` (text): Foreground
  - `species_abbreviation` (text): Species abbreviation
  - `kobas_database` (data): KOBAS database
  - `database` (data): Database
  - `background` (text): Background
  - ... and 4 more parameters


#### Repository Actions
GAP Cross-reference with KEGG databases

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/chrisb/gap_all_glycan_tools/Repository_Actions
GAP_Cross-reference_with_KEGG_databases`  
**Category:** Web Services  
**Version:** 0.3.2  
**Repository:** chrisb/gap_all_glycan_tools

**Description:** GAP glycan tools

**Key Parameters:**
  - `target_database` (data): Target Database
  - `source_database_or_entry` (data): Source database or entry
  - `target_and_source_sequence` (text): target and source sequence
  - `gl` (text): gl
  - `output_sequence` (text): output sequence
  - ... and 32 more parameters


#### Repository Actions
GAP Find KEGG glycans

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/chrisb/gap_all_glycan_tools/Repository_Actions
GAP_Find_KEGG_glycans`  
**Category:** Web Services  
**Version:** 0.4.0  
**Repository:** chrisb/gap_all_glycan_tools

**Description:** GAP glycan tools

**Key Parameters:**
  - `database` (data): Database
  - `query` (text): Query
  - `query_sequence` (text): Query sequence
  - `output_sequence` (text): output sequence
  - `gl` (text): gl
  - ... and 3 more parameters


#### Repository Actions
GAP Get KEGG glycans

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/chrisb/gap_all_glycan_tools/Repository_Actions
GAP_Get_KEGG_glycans`  
**Category:** Web Services  
**Version:** 0.3  
**Repository:** chrisb/gap_all_glycan_tools

**Description:** GAP glycan tools

**Key Parameters:**
  - `query_sequence` (text): Query sequence
  - `gl` (text): gl
  - `kcf_output_sequence` (text): kcf output sequence
  - `1_____2` (text): 1     2
  - `db_output_sequence` (text): db output sequence
  - ... and 5 more parameters


#### Repository Actions
Add KEGG Pathway Information

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/malex/gait_gm/Repository_Actions
Add_KEGG_Pathway_Information`  
**Category:** Metabolomics  
**Version:** 21.7.22  
**Repository:** malex/gait_gm

**Description:** Modeling Metabolites as a function of gene expression

**Key Parameters:**
  - `select_your_species_from_the_list` (select): Select your Species from the List
  - `gene_to_keggid_link_file` (data): Gene to KEGGID Link File
  - `gene_unique_featureid` (text): Gene unique FeatureID
  - `gene_symbol` (text): Gene Symbol
  - `gene_keggid` (text): Gene KEGGID
  - ... and 18 more parameters


#### Repository Actions
Link Name to KEGGID

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/malex/gait_gm/Repository_Actions
Link_Name_to_KEGGID`  
**Category:** Metabolomics  
**Version:** 21.7.22  
**Repository:** malex/gait_gm

**Description:** Modeling Metabolites as a function of gene expression

**Key Parameters:**
  - `select_species_from_the_list` (select): Select Species from the list
  - `select_annotation_dataset(s)` (data): Select Annotation Dataset(s)
  - `gene_unique_featureid` (text): Gene Unique FeatureID
  - `gene_symbol` (text): Gene Symbol
  - `metabolite_unique_featureid` (text): Metabolite Unique FeatureID
  - ... and 10 more parameters


#### Repository Actions
KEGG pathways mapping and coverage

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/proteore/proteore_kegg_pathways_coverage/Repository_Actions
KEGG_pathways_mapping_and_coverage`  
**Category:** Proteomics  
**Version:** 2021.04.12  
**Repository:** proteore/proteore_kegg_pathways_coverage

**Description:** give KEGG pathway(s) concerned by a given list of proteins or genes.

**Key Parameters:**
  - `select_your_file` (data): Select your file
  - `does_file_contain_header?` (data): Does file contain header?
  - `column_number_of_ids` (integer): Column number of IDs
  - `select_ids` (text): Select IDs
  - `species` (text): Species
  - ... and 1 more parameters


#### Repository Actions
KEGG pathways mapping and visualization

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/proteore/proteore_maps_visualization/Repository_Actions
KEGG_pathways_mapping_and_visualization`  
**Category:** Proteomics  
**Version:** 2020.03.05  
**Repository:** proteore/proteore_maps_visualization

**Description:** map a list of Uniprot Accession number or Entrez gene ID to KEGG pathway with pathview R package

**Key Parameters:**
  - `species_(human,_mouse,_rat)` (boolean): Species (human, mouse, rat)
  - `enter_your_pathway(s)` (text): Enter your pathway(s)
  - `select_pathway(s)_(by_clicking_in_the_box)` (select): Select pathway(s) (by clicking in the box)
  - `select_id_type_for_genes_to_map_to_the_pathway(s)` (text): Select ID type for genes to map to the pathway(s)
  - `enter_your_ids` (text): Enter your IDs
  - ... and 17 more parameters


### UniProt Tools (5 tools)

#### Repository Actions
UniProt Id Mapping through API

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/iquasere/upimapi/Repository_Actions
UniProt_Id_Mapping_through_API`  
**Category:** Genome annotation  
**Version:** 0.1.0  
**Repository:** iquasere/upimapi

**Description:** UniProt Id Mapping through API

**Key Parameters:**
  - `input_ids_file` (data): Input IDs file
  - `options` (text): options
  - `if_ids_in_database_are_in_'full'_format` (data): If IDs in database are in 'full' format
  - `diamond_arguments` (text): DIAMOND arguments
  - `special_functions` (text): Special functions


#### Repository Actions
freqSAP

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/recetox/freqsap/Repository_Actions
freqSAP`  
**Category:** Proteomics  
**Version:** 1.0.0+galaxy0  
**Repository:** recetox/freqsap

**Description:** Get frequencies of single amino-acid polymorphisms based on nucleid-acid polymorphism for different populations from UniProt and DbSNP.

**Key Parameters:**
  - `protein_accession_in_uniprot` (text): Protein Accession in UniProt
  - `regions_from_which_to_choose_the_populations` (text): Regions from which to choose the populations
  - `output_format` (text): Output Format
  - `freqsap` (text): freqSAP
  - `output_format` (select): Output Format


#### Repository Actions
Analyse your data with Reactome

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/lnguyen/link2reactome/Repository_Actions
Analyse_your_data_with_Reactome`  
**Category:** Proteomics  
**Version:** 0.1.0  
**Repository:** lnguyen/link2reactome

**Description:** A tool maps your IDs list (UniProt, Gene name) via analysis tools from Reactome database and visualize directly pathways in which your proteins are involved

**Key Parameters:**
  - `input_identifiers` (data): Input identifiers
  - `enter_list_of_identifiers` (text): Enter list of identifiers


#### Repository Actions
UniProt

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/bgruening/uniprot_rest_interface/Repository_Actions
UniProt`  
**Category:** Proteomics  
**Version:** 0.7  
**Repository:** bgruening/uniprot_rest_interface

**Description:** UniProt ID mapping and sequence retrieval

**Key Parameters:**
  - `input_file_with_ids` (data): Input file with IDs
  - `id_column` (text): ID column
  - `source_database` (data): Source database
  - `target_database` (data): Target database
  - `from_refseq_to_embl` (text): FROM refseq TO embl
  - ... and 3 more parameters


#### Repository Actions
UniProt

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/galaxyp/uniprotxml_downloader/Repository_Actions
UniProt`  
**Category:** Proteomics  
**Version:** 2.5.0  
**Repository:** galaxyp/uniprotxml_downloader

**Description:** Download UniProt proteome in XML or fasta format

**Key Parameters:**
  - `select` (text): Select
  - `common_organisms` (select): Common Organisms
  - `filter_by_reviewed_status` (text): filter by reviewed status
  - `uniprot_output_format` (text): uniprot output format
  - `available_proteomes` (text): Available proteomes
  - ... and 5 more parameters


### Reactome Tools (5 tools)

#### Repository Actions
ReactomePA

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/mora-lab/reactomepa/Repository_Actions
ReactomePA`  
**Category:** Ontology Manipulation  
**Version:** 0.1.0  
**Repository:** mora-lab/reactomepa

**Description:** ReactomePA

**Key Parameters:**
  - `differentially_expressed_gene_list` (text): Differentially expressed gene list
  - `organism` (select): Organism
  - `example___single_count_matrix` (integer): Example - Single Count Matrix


#### Repository Actions
View repository View change log Browse repository tip files Download as a .tar.gz file Download as a .tar.bz2 file Download as a zip file
ReactomePA

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/mora-lab/reactomepa/Repository_Actions
View_repository_View_change_log_Browse_repository_tip_files_Download_as_a_.tar.gz_file_Download_as_a_.tar.bz2_file_Download_as_a_zip_file
ReactomePA`  
**Category:** Ontology Manipulation  
**Version:** 0.1.0  
**Repository:** mora-lab/reactomepa

**Description:** ReactomePA

**Key Parameters:**
  - `differentially_expressed_gene_list` (text): Differentially expressed gene list
  - `organism` (select): Organism
  - `example___single_count_matrix` (integer): Example - Single Count Matrix


#### Repository Actions
Reactome Analysis

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/paul_wolfe/reactome_cli/Repository_Actions
Reactome_Analysis`  
**Category:** Proteomics  
**Version:** 1.2.0  
**Repository:** paul_wolfe/reactome_cli

**Description:** Official Reactome CLI tools used to query the reactome.org web api and run Reactome GSA tools.

**Key Parameters:**
  - `select_analysis_type` (text): Select analysis type
  - `choose_input_type` (data): Choose input type
  - `source_file` (data): Source File
  - `project_to_human?` (text): Project to Human?
  - `include_interactors?` (boolean): Include Interactors?
  - ... and 7 more parameters


#### Repository Actions
Reactome GSA Analysis

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/paul_wolfe/reactome_cli/Repository_Actions
Reactome_GSA_Analysis`  
**Category:** Proteomics  
**Version:** 1.2.0  
**Repository:** paul_wolfe/reactome_cli

**Description:** Official Reactome CLI tools used to query the reactome.org web api and run Reactome GSA tools.

**Key Parameters:**
  - `dataset` (data): Dataset
  - `data_type` (data): Data type
  - `annotations` (text): Annotations
  - `select_analysis_method` (text): Select analysis method
  - `sample_groups` (text): Sample groups
  - ... and 14 more parameters


#### Repository Actions
Pathway Matcher

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/galaxyp/reactome_pathwaymatcher/Repository_Actions
Pathway_Matcher`  
**Category:** Proteomics  
**Version:** 1.9.1.4  
**Repository:** galaxyp/reactome_pathwaymatcher

**Description:** Reactome Pathway Matcher

**Key Parameters:**
  - `the_input_can_be` (data): The input can be
  - `proteoforms` (text): Proteoforms
  - `p12318;00048` (text): P12318;00048
  - `p13569;01148` (text): P13569;01148
  - `p37088;01148` (text): P37088;01148
  - ... and 4 more parameters


### HMDB Tools (3 tools)

#### Repository Actions
Wishart bank downloader

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/fgiacomoni/downloader_bank_hmdb/Repository_Actions
Wishart_bank_downloader`  
**Category:** Metabolomics  
**Version:** 1.1.2  
**Repository:** fgiacomoni/downloader_bank_hmdb

**Description:** [W4M][Metabolomics][LC-MS] HMDB database downloader - Get Data/Annotation - Get a specific metabolite bank (as Urine...) from The Human Metabolome Database.

**Key Parameters:**
  - `what_is_the_specific_bank_you_want_to_download?` (text): What is the specific bank you want to download?
  - `which_output_format_do_you_need?` (text): Which output format do you need?
  - `level_of_script_verbose` (text): Level of script verbose
  - `download_a_bank_containing_information_(like` (text): Download a bank containing information (like
  - `choose_whether_specific_metabolite_banks` (text): Choose whether specific metabolite banks
  - ... and 5 more parameters


#### Repository Actions
HMDB MS search

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/fgiacomoni/hmdb_ms_search/Repository_Actions
HMDB_MS_search`  
**Category:** Metabolomics  
**Version:** 1.7.6  
**Repository:** fgiacomoni/hmdb_ms_search

**Description:** [W4M][Metabolomics][LC-MS] HMDB database MS Search Package - Annotation - Returns annotation results (adducts and metabolites) from The Human Metabolome Database.

**Key Parameters:**
  - `would_you_use_a_file` (data): Would you use a file
  - `file_of_masses_(variable_metadata)` (data): File of masses (Variable Metadata)
  - `generally_variable_metadata_file._please_note` (data): Generally variable metadata file. Please note
  - `do_you_have_a_header` (select): Do you have a header
  - `number_of_header_lines` (integer): Number of header lines
  - ... and 24 more parameters


#### Repository Actions
KMD HMDB Data Plot

**Tool ID:** `toolshed.g2.bx.psu.edu/repos/workflow4metabolomics/kmd_hmdb_data_plot/Repository_Actions
KMD_HMDB_Data_Plot`  
**Category:** Metabolomics  
**Version:** 1.0.0+galaxy0  
**Repository:** workflow4metabolomics/kmd_hmdb_data_plot

**Description:** retrieves data from KMD HMDB API and produce plot and csv file

**Key Parameters:**
  - `what_to_do` (text): What to do
  - `m/z_ratio` (select): M/z Ratio
  - `mass_tolerance` (select): Mass Tolerance
  - `which_database_to_interrogate` (data): Which database to interrogate
  - `adducts` (text): Adducts
  - ... and 4 more parameters


## Local Datasets

Information about 115 local datasets available for Galaxy workflows.

### Datasets by Format

- **PARQUET:** 41 datasets
- **UNKNOWN:** 31 datasets
- **CSV:** 21 datasets
- **ZIP:** 8 datasets
- **PKL:** 7 datasets
- **TXT:** 3 datasets
- **TSV:** 2 datasets
- **JSON:** 1 datasets
- **OBO:** 1 datasets

### Key Datasets

#### CSV Datasets (21 files)

- **DepMap_CRISPRGeneDependency.csv**
  - Size: 403.3MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/DepMap_CRISPRGeneDependency.csv`
  - Type: tabular
  - Header: True
  - Index columns: cell_line, gene, dependency_score, effect_score

- **DepMap_CRISPRGeneEffect.csv**
  - Size: 410.5MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/DepMap_CRISPRGeneEffect.csv`
  - Type: tabular
  - Header: True
  - Index columns: cell_line, gene, dependency_score, effect_score

- **DepMap_Model.csv**
  - Size: 678.0KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/DepMap_Model.csv`
  - Type: tabular
  - Header: True
  - Index columns: cell_line, gene, dependency_score, effect_score

- **DepMap_OmicsExpressionProteinCodingGenesTPMLogp1.csv**
  - Size: 497.4MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/DepMap_OmicsExpressionProteinCodingGenesTPMLogp1.csv`
  - Type: tabular
  - Header: True
  - Index columns: cell_line, gene, dependency_score, effect_score

- **ddinter_alimentary_tract_metabolism.csv**
  - Size: 3.2MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/ddinter_alimentary_tract_metabolism.csv`
  - Type: tabular
  - Header: True
  - Index columns: drug1, drug2, interaction_type, severity

- **ddinter_antineoplastic.csv**
  - Size: 3.7MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/ddinter_antineoplastic.csv`
  - Type: tabular
  - Header: True
  - Index columns: drug1, drug2, interaction_type, severity

- **ddinter_antiparasitic.csv**
  - Size: 310.0KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/ddinter_antiparasitic.csv`
  - Type: tabular
  - Header: True
  - Index columns: drug1, drug2, interaction_type, severity

- **ddinter_blood_organs.csv**
  - Size: 847.4KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/ddinter_blood_organs.csv`
  - Type: tabular
  - Header: True
  - Index columns: drug1, drug2, interaction_type, severity

- **ddinter_dermatological.csv**
  - Size: 1.5MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/ddinter_dermatological.csv`
  - Type: tabular
  - Header: True
  - Index columns: drug1, drug2, interaction_type, severity

- **ddinter_hormonal.csv**
  - Size: 688.6KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/ddinter_hormonal.csv`
  - Type: tabular
  - Header: True
  - Index columns: drug1, drug2, interaction_type, severity

- **ddinter_respiratory.csv**
  - Size: 1.7MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/ddinter_respiratory.csv`
  - Type: tabular
  - Header: True
  - Index columns: drug1, drug2, interaction_type, severity

- **ddinter_various.csv**
  - Size: 684.4KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/ddinter_various.csv`
  - Type: tabular
  - Header: True
  - Index columns: drug1, drug2, interaction_type, severity

- **evebio_assay_table.csv**
  - Size: 12.3KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/evebio_assay_table.csv`
  - Type: tabular
  - Header: True
  - Index columns: compound_id, assay_id, target, activity

- **evebio_bundle_table.csv**
  - Size: 8.0KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/evebio_bundle_table.csv`
  - Type: tabular
  - Header: True
  - Index columns: compound_id, assay_id, target, activity

- **evebio_compound_table.csv**
  - Size: 147.0KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/evebio_compound_table.csv`
  - Type: tabular
  - Header: True
  - Index columns: compound_id, assay_id, target, activity

*... and 6 more csv datasets*

#### TSV Datasets (2 files)

- **BindingDB_All_202409.tsv**
  - Size: 5.8GB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/BindingDB_All_202409.tsv`
  - Type: tabular
  - Header: True
  - Index columns: ligand, target, affinity, ki, kd

- **proteinatlas.tsv**
  - Size: 34.9MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/proteinatlas.tsv`
  - Type: tabular
  - Header: True
  - Index columns: gene, protein, tissue, expression_level

#### PARQUET Datasets (41 files)

- **DisGeNET.parquet**
  - Size: 2.8MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/DisGeNET.parquet`
  - Type: tabular
  - Header: True
  - Index columns: gene, disease, score, pmid

- **McPAS-TCR.parquet**
  - Size: 1011.0KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/McPAS-TCR.parquet`
  - Type: tabular
  - Header: True
  - Index columns: tcr_sequence, epitope, mhc, pathology

- **Virus-Host_PPI_P-HIPSTER_2020.parquet**
  - Size: 774.5KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/Virus-Host_PPI_P-HIPSTER_2020.parquet`
  - Type: tabular
  - Header: True
  - Index columns: virus_protein, host_protein, interaction_type

- **affinity_capture-ms.parquet**
  - Size: 5.3MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/affinity_capture-ms.parquet`
  - Type: tabular
  - Header: True
  - Index columns: id, name, value

- **affinity_capture-rna.parquet**
  - Size: 41.9KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/affinity_capture-rna.parquet`
  - Type: tabular
  - Header: True
  - Index columns: id, name, value

- **broad_repurposing_hub_molecule_with_smiles.parquet**
  - Size: 1.1MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/broad_repurposing_hub_molecule_with_smiles.parquet`
  - Type: tabular
  - Header: True
  - Index columns: compound, target, phase, moa

- **broad_repurposing_hub_phase_moa_target_info.parquet**
  - Size: 174.0KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/broad_repurposing_hub_phase_moa_target_info.parquet`
  - Type: tabular
  - Header: True
  - Index columns: compound, target, phase, moa

- **co-fractionation.parquet**
  - Size: 1.4MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/co-fractionation.parquet`
  - Type: tabular
  - Header: True
  - Index columns: id, name, value

- **czi_census_datasets_v4.parquet**
  - Size: 367.6KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/czi_census_datasets_v4.parquet`
  - Type: tabular
  - Header: True
  - Index columns: dataset_id, cell_type, tissue, organism

- **dosage_growth_defect.parquet**
  - Size: 21.1KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/dosage_growth_defect.parquet`
  - Type: tabular
  - Header: True
  - Index columns: id, name, value

- **gene_info.parquet**
  - Size: 3.8MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/gene_info.parquet`
  - Type: tabular
  - Header: True
  - Index columns: gene_id, symbol, description, organism

- **genetic_interaction.parquet**
  - Size: 8.1MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/genetic_interaction.parquet`
  - Type: tabular
  - Header: True
  - Index columns: gene1, gene2, interaction_type, score

- **gtex_tissue_gene_tpm.parquet**
  - Size: 10.4MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/gtex_tissue_gene_tpm.parquet`
  - Type: tabular
  - Header: True
  - Index columns: gene, tissue, tpm, expression

- **marker_celltype.parquet**
  - Size: 71.7KB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/marker_celltype.parquet`
  - Type: tabular
  - Header: True
  - Index columns: id, name, value

- **miRDB_v6.0_results.parquet**
  - Size: 65.5MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/miRDB_v6.0_results.parquet`
  - Type: tabular
  - Header: True
  - Index columns: mirna, target_gene, score, validation

*... and 26 more parquet datasets*

#### TXT Datasets (3 files)

- **miRTarBase_microRNA_target_interaction_pubmed_abtract.txt**
  - Size: 1.6MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/miRTarBase_microRNA_target_interaction_pubmed_abtract.txt`
  - Type: unknown
  - Index columns: mirna, target_gene, score, validation

- **sgRNA_KO_SP_human.txt**
  - Size: 361.6MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/sgRNA_KO_SP_human.txt`
  - Type: unknown
  - Index columns: data

- **sgRNA_KO_SP_mouse.txt**
  - Size: 355.0MB
  - Path: `/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/sgRNA_KO_SP_mouse.txt`
  - Type: unknown
  - Index columns: data

## MetaboAnalyst SQLite Databases

Detailed schema information for MetaboAnalyst MS/MS spectral databases.

### Database Overview

| Database | Size | Tables | Purpose |
|----------|------|--------|---------|
| FragsAnnotateDBNL_v02042024.sqlite | 1.2 GB | 25 | Fragment annotation (no lipids) |
| FragsAnnotateDB_v02042024.sqlite | 1.4 GB | 25 | Fragment annotation database |
| MS2ID_BioNL_v09102023.sqlite | 0.5 GB | 25 | Biological metabolites (no lipids) |
| MS2ID_Bio_v09102023.sqlite | 0.7 GB | 25 | Biological metabolites |
| MS2ID_ExposomicsNL_v09102023.sqlite | 1.0 GB | 25 | Exposomics (no lipids) |
| MS2ID_Exposomics_v09102023.sqlite | 1.4 GB | 25 | Exposomics compounds |
| MS2ID_LipidsNL_v09102023.sqlite | 1.1 GB | 25 | Lipid compounds (no lipids subset) |
| MS2ID_Lipids_v09102023.sqlite | 1.5 GB | 25 | Lipid compounds |
| MS2ID_PathwayNL_v09102023.sqlite | 0.1 GB | 25 | Pathway metabolites (no lipids) |
| MS2ID_Pathway_v09102023.sqlite | 0.1 GB | 25 | Pathway-focused metabolites |

### Database Schemas

#### FragsAnnotateDBNL_v02042024.sqlite

**Size:** 1.24 GB  
**Tables:** 25

**Table Schemas:**

##### BMDMS_PosDB
*Columns: 2*

| Column | Type |
|--------|------|
| ID | INTEGER |
| Fragments | TEXT |

##### GNPS_NegDB
*Columns: 2*

| Column | Type |
|--------|------|
| ID | INTEGER |
| Fragments | TEXT |

##### GNPS_PosDB
*Columns: 2*

| Column | Type |
|--------|------|
| ID | INTEGER |
| Fragments | TEXT |

##### HMDB_experimental_NADB
*Columns: 2*

| Column | Type |
|--------|------|
| ID | INTEGER |
| Fragments | TEXT |

##### HMDB_experimental_NegDB
*Columns: 2*

| Column | Type |
|--------|------|
| ID | INTEGER |
| Fragments | TEXT |

*... and 20 more tables*

#### FragsAnnotateDB_v02042024.sqlite

**Size:** 1.43 GB  
**Tables:** 25

**Table Schemas:**

##### BMDMS_PosDB
*Columns: 2*

| Column | Type |
|--------|------|
| ID | INTEGER |
| Fragments | TEXT |

##### GNPS_NegDB
*Columns: 2*

| Column | Type |
|--------|------|
| ID | INTEGER |
| Fragments | TEXT |

##### GNPS_PosDB
*Columns: 2*

| Column | Type |
|--------|------|
| ID | INTEGER |
| Fragments | TEXT |

##### HMDB_experimental_NADB
*Columns: 2*

| Column | Type |
|--------|------|
| ID | INTEGER |
| Fragments | TEXT |

##### HMDB_experimental_NegDB
*Columns: 2*

| Column | Type |
|--------|------|
| ID | INTEGER |
| Fragments | TEXT |

*... and 20 more tables*

*Note: Other databases follow similar schema patterns.*

## API Query Patterns

Reference patterns for querying chemical/biological databases programmatically.

### Common Query Pattern

```python
def query_database(prompt: str, database: str, max_results: int = 5):
    """Generic database query using LLM for API generation"""
    # 1. Query LLM to generate API endpoint from natural language
    endpoint = _query_llm_for_api(prompt, database)
    
    # 2. Execute REST API call
    response = _query_rest_api(endpoint)
    
    # 3. Parse and return results
    return parse_response(response, max_results)
```

### Database-Specific APIs

#### PubChem PUG REST API
- **Base URL:** `https://pubchem.ncbi.nlm.nih.gov/rest/pug/`
- **Documentation:** https://pubchem.ncbi.nlm.nih.gov/docs/pug-rest
- **Example:** `compound/name/aspirin/property/MolecularFormula,MolecularWeight/JSON`

#### ChEMBL API
- **Base URL:** `https://www.ebi.ac.uk/chembl/api/data/`
- **Documentation:** https://www.ebi.ac.uk/chembl/api/data/docs
- **Example:** `molecule/CHEMBL25?format=json`

#### KEGG REST API
- **Base URL:** `https://rest.kegg.jp/`
- **Documentation:** https://www.kegg.jp/kegg/rest/keggapi.html
- **Example:** `get/hsa:10458` (get entry), `find/compound/glucose` (search)

#### HMDB API
- **Base URL:** `https://hmdb.ca/`
- **Access:** Requires academic credentials
- **Documentation:** https://hmdb.ca/simple/api

## Usage Guidelines

### For LLM-Based Workflow Generation

1. **Dataset Selection:**
   - Use tool parameters for large local datasets (>100MB)
   - Use workflow inputs for small datasets (<100MB)
   - Use Data Source tools for API queries

2. **Format Conversion:**
   - Parquet/PKL files: Convert on-demand using conversion functions
   - SQLite databases: Use with compatible metabolomics tools (ipaPy2, CFM-ID, BEAMSpy)
   - CSV/TSV files: Galaxy-ready, use directly

3. **Tool Selection:**
   - Match database type to tool (e.g., PubChem tools for PubChem data)
   - Check tool parameters for database/reference file support
   - Verify input/output format compatibility

4. **API Integration:**
   - Use existing Galaxy Data Source tools when available
   - Follow biomni query patterns for LLM-assisted API generation
   - Cache API results when possible to reduce redundant queries

### Compatible Galaxy Tools

- **SQLite Databases:** ipaPy2, CFM-ID, BEAMSpy, MS2Compound
- **Chemical Data:** ChemicalToolBox, OpenBabel, RDKit tools
- **Metabolomics:** MetaboAnalyst, XCMS, mzML processing tools
- **Proteomics:** SearchGUI, PeptideShaker, MaxQuant
- **Pathway Analysis:** Reactome, KEGG mapper, PathwayEnrichment

---
*Document generated on 2025-10-09 for biomate backend integration*