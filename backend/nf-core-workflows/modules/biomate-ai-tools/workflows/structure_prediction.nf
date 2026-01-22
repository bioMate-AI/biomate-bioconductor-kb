#!/usr/bin/env nextflow
/*
 * Structure Prediction Pipeline
 * Uses ESMFold (API), Boltz, or Chai-1
 *
 * Model weights are mounted from S3 or local storage
 */

nextflow.enable.dsl=2

// Parameters
params.input = null                    // Input FASTA file or samplesheet
params.outdir = './results'
params.models_dir = 's3://biomate-models'  // or '/shared/models'
params.method = 'esmfold'              // esmfold, boltz, chai1

// Include modules
include { ESMFOLD } from '../esmfold/main'
include { BOLTZ } from '../boltz/main'
include { CHAI1 } from '../chai1/main'

// Download models if needed (runs once)
process DOWNLOAD_MODELS {
    label 'process_low'
    storeDir "${params.models_dir}"

    output:
    path "boltz/*", emit: boltz_model, optional: true
    path "chai1/*", emit: chai1_model, optional: true

    script:
    """
    # Boltz downloads automatically on first run
    # Chai-1 downloads automatically on first run
    echo "Models will be downloaded on first use"
    mkdir -p boltz chai1
    touch boltz/.ready chai1/.ready
    """
}

// Main workflow
workflow STRUCTURE_PREDICTION {
    take:
    fasta_ch   // channel: [ val(meta), path(fasta) ]

    main:
    // Route to appropriate method
    if (params.method == 'esmfold') {
        // ESMFold - FREE API, no models needed
        ESMFOLD(fasta_ch)
        pdb_ch = ESMFOLD.out.pdb
    }
    else if (params.method == 'boltz') {
        // Boltz - needs GPU, auto-downloads models
        BOLTZ(fasta_ch, [])
        pdb_ch = BOLTZ.out.pdb
    }
    else if (params.method == 'chai1') {
        // Chai-1 - needs GPU, auto-downloads models
        CHAI1(fasta_ch, [])
        pdb_ch = CHAI1.out.pdb
    }

    emit:
    pdb = pdb_ch
}

// Entry point
workflow {
    // Parse input
    if (params.input.endsWith('.csv')) {
        // Samplesheet mode
        Channel.fromPath(params.input)
            .splitCsv(header: true)
            .map { row -> [[id: row.sample], file(row.fasta)] }
            .set { input_ch }
    } else {
        // Single file mode
        Channel.of([[id: file(params.input).baseName], file(params.input)])
            .set { input_ch }
    }

    // Run prediction
    STRUCTURE_PREDICTION(input_ch)

    // Collect results
    STRUCTURE_PREDICTION.out.pdb
        .map { meta, pdb -> pdb }
        .collect()
        .subscribe { println "Predicted ${it.size()} structures" }
}
