#!/usr/bin/env nextflow
/*
 * MOLECULAR CLONING PIPELINE
 *
 * End-to-end workflow for in silico molecular cloning:
 * 1. Get gene coding sequence from NCBI
 * 2. Design Golden Gate oligos for assembly
 * 3. Simulate Golden Gate assembly
 * 4. Annotate the resulting plasmid
 * 5. Perform restriction digest verification
 *
 * Usage:
 *   nextflow run workflows/molecular_cloning/main.nf \
 *     --gene_name "GFP" \
 *     --organism "Aequorea victoria" \
 *     --backbone_sequence "ATGC..." \
 *     --enzyme_name "BsaI" \
 *     -profile docker
 */

nextflow.enable.dsl = 2

// Include subworkflows
include { GET_GENE_CODING_SEQUENCE } from '../../subworkflows/molecular_biology/get_gene_coding_sequence/main'
include { DESIGN_GOLDEN_GATE_OLIGOS } from '../../subworkflows/molecular_biology/design_golden_gate_oligos/main'
include { GOLDEN_GATE_ASSEMBLY } from '../../subworkflows/molecular_biology/golden_gate_assembly/main'
include { ANNOTATE_PLASMID } from '../../subworkflows/molecular_biology/annotate_plasmid/main'
include { DIGEST_SEQUENCE } from '../../subworkflows/molecular_biology/digest_sequence/main'

// Pipeline parameters
params.outdir = './results/molecular_cloning'

// Input parameters
params.gene_name = null
params.organism = 'human'
params.backbone_sequence = null
params.enzyme_name = 'BsaI'
params.verification_enzymes = ['EcoRI', 'BamHI']
params.is_circular = true

// Validate required parameters
if (!params.gene_name) {
    error "Please provide --gene_name parameter"
}
if (!params.backbone_sequence) {
    error "Please provide --backbone_sequence parameter"
}

workflow MOLECULAR_CLONING_PIPELINE {
    take:
    ch_input  // channel: [ val(meta) ]

    main:
    // Step 1: Get gene coding sequence
    GET_GENE_CODING_SEQUENCE(ch_input)

    // Step 2: Design Golden Gate oligos
    // Parse the gene sequence from step 1 results
    ch_gene_seq = GET_GENE_CODING_SEQUENCE.out.results
        .map { meta, json_file ->
            def result = new groovy.json.JsonSlurper().parse(json_file)
            if (result.success && result.result?.coding_sequence) {
                return [meta, result.result.coding_sequence]
            }
            return [meta, null]
        }
        .filter { meta, seq -> seq != null }

    DESIGN_GOLDEN_GATE_OLIGOS(ch_gene_seq.map { meta, seq -> meta })

    // Step 3: Simulate Golden Gate assembly
    ch_oligos = DESIGN_GOLDEN_GATE_OLIGOS.out.results
        .map { meta, json_file ->
            def result = new groovy.json.JsonSlurper().parse(json_file)
            if (result.success && result.result?.oligos) {
                return [meta, result.result.oligos]
            }
            return [meta, null]
        }
        .filter { meta, oligos -> oligos != null }

    GOLDEN_GATE_ASSEMBLY(ch_oligos.map { meta, oligos -> meta })

    // Step 4: Annotate the assembled plasmid
    ch_assembled = GOLDEN_GATE_ASSEMBLY.out.results
        .map { meta, json_file ->
            def result = new groovy.json.JsonSlurper().parse(json_file)
            if (result.success && result.result?.assembled_sequence) {
                return [meta, result.result.assembled_sequence]
            }
            return [meta, null]
        }
        .filter { meta, seq -> seq != null }

    ANNOTATE_PLASMID(ch_assembled.map { meta, seq -> meta })

    // Step 5: Restriction digest verification
    DIGEST_SEQUENCE(ANNOTATE_PLASMID.out.results.map { meta, json -> meta })

    emit:
    gene_sequence = GET_GENE_CODING_SEQUENCE.out.results
    oligos = DESIGN_GOLDEN_GATE_OLIGOS.out.results
    assembly = GOLDEN_GATE_ASSEMBLY.out.results
    annotation = ANNOTATE_PLASMID.out.results
    digest = DIGEST_SEQUENCE.out.results
    versions = DIGEST_SEQUENCE.out.versions
}

// Entry workflow
workflow {
    // Create input channel with metadata
    ch_input = Channel.of([
        id: params.gene_name ?: 'cloning_run',
        gene_name: params.gene_name,
        organism: params.organism
    ])

    // Run pipeline
    MOLECULAR_CLONING_PIPELINE(ch_input)

    // Display outputs
    MOLECULAR_CLONING_PIPELINE.out.digest.view { meta, file ->
        "Final digest results: ${file}"
    }
}
