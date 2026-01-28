#!/usr/bin/env nextflow
/*
 * DRUG DISCOVERY PIPELINE
 *
 * End-to-end workflow for in silico drug screening:
 * 1. Calculate physicochemical properties from SMILES
 * 2. Predict ADMET properties
 * 3. Run molecular docking (DiffDock)
 * 4. Check drug combination safety
 * 5. Check FDA drug recalls
 *
 * Usage:
 *   nextflow run workflows/drug_discovery/main.nf \
 *     --smiles "CCO" \
 *     --target_protein "EGFR" \
 *     -profile docker
 */

nextflow.enable.dsl = 2

// Include subworkflows
include { CALCULATE_PHYSICOCHEMICAL_PROPERTIES } from '../../subworkflows/pharmacology/calculate_physicochemical_properties/main'
include { PREDICT_ADMET_PROPERTIES } from '../../subworkflows/pharmacology/predict_admet_properties/main'
include { RUN_DIFFDOCK_WITH_SMILES } from '../../subworkflows/pharmacology/run_diffdock_with_smiles/main'
include { CHECK_DRUG_COMBINATION_SAFETY } from '../../subworkflows/pharmacology/check_drug_combination_safety/main'
include { CHECK_FDA_DRUG_RECALLS } from '../../subworkflows/pharmacology/check_fda_drug_recalls/main'
include { GET_FDA_DRUG_LABEL_INFO } from '../../subworkflows/pharmacology/get_fda_drug_label_info/main'

// Pipeline parameters
params.outdir = './results/drug_discovery'

// Input parameters - compound
params.smiles = null
params.compound_name = 'compound'

// Input parameters - target
params.target_protein = null
params.protein_sequence = null
params.pdb_id = null

// Input parameters - safety
params.drug_name = null
params.combination_drugs = []

// Validate required parameters
if (!params.smiles) {
    error "Please provide --smiles parameter (compound SMILES string)"
}

workflow DRUG_DISCOVERY_PIPELINE {
    take:
    ch_input  // channel: [ val(meta) ]

    main:
    // Step 1: Calculate physicochemical properties
    CALCULATE_PHYSICOCHEMICAL_PROPERTIES(ch_input)

    // Step 2: Predict ADMET properties (runs in parallel with step 1)
    PREDICT_ADMET_PROPERTIES(ch_input)

    // Step 3: Run molecular docking if target is provided
    if (params.target_protein || params.protein_sequence || params.pdb_id) {
        RUN_DIFFDOCK_WITH_SMILES(ch_input)
        ch_docking = RUN_DIFFDOCK_WITH_SMILES.out.results
    } else {
        ch_docking = Channel.empty()
    }

    // Step 4: Check drug combination safety if combination drugs provided
    if (params.combination_drugs && params.combination_drugs.size() > 0) {
        CHECK_DRUG_COMBINATION_SAFETY(ch_input)
        ch_safety = CHECK_DRUG_COMBINATION_SAFETY.out.results
    } else {
        ch_safety = Channel.empty()
    }

    // Step 5: Check FDA recalls and get label info if drug name provided
    if (params.drug_name) {
        CHECK_FDA_DRUG_RECALLS(ch_input)
        GET_FDA_DRUG_LABEL_INFO(ch_input)
        ch_fda = CHECK_FDA_DRUG_RECALLS.out.results
        ch_label = GET_FDA_DRUG_LABEL_INFO.out.results
    } else {
        ch_fda = Channel.empty()
        ch_label = Channel.empty()
    }

    emit:
    physicochemical = CALCULATE_PHYSICOCHEMICAL_PROPERTIES.out.results
    admet = PREDICT_ADMET_PROPERTIES.out.results
    docking = ch_docking
    safety = ch_safety
    fda_recalls = ch_fda
    fda_label = ch_label
    versions = CALCULATE_PHYSICOCHEMICAL_PROPERTIES.out.versions
}

// Entry workflow
workflow {
    // Create input channel with metadata
    ch_input = Channel.of([
        id: params.compound_name ?: 'drug_screen',
        smiles: params.smiles,
        compound_name: params.compound_name
    ])

    // Run pipeline
    DRUG_DISCOVERY_PIPELINE(ch_input)

    // Display outputs
    DRUG_DISCOVERY_PIPELINE.out.physicochemical.view { meta, file ->
        "Physicochemical properties: ${file}"
    }
    DRUG_DISCOVERY_PIPELINE.out.admet.view { meta, file ->
        "ADMET predictions: ${file}"
    }
}
