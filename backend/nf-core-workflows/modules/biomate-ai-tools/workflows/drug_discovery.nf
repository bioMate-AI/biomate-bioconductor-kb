#!/usr/bin/env nextflow
/*
 * Drug Discovery Pipeline
 * 1. Screen compounds with DrugCLIP (10M× faster than docking)
 * 2. Plan synthesis routes with SynCraft
 *
 * Requires: GEMINI_API_KEY for SynCraft
 */

nextflow.enable.dsl=2

params.target_fasta = null        // Target protein FASTA
params.compounds = null           // Compound library (SDF or SMILES)
params.outdir = './results'
params.top_k = 100                // Number of top hits to return
params.plan_synthesis = true      // Run SynCraft on top hits

include { DRUGCLIP } from '../drugclip/main'
include { SYNCRAFT } from '../syncraft/main'

workflow DRUG_DISCOVERY {
    take:
    target_ch      // channel: [ val(meta), path(fasta) ]
    compounds_ch   // channel: path(compounds)

    main:
    // Step 1: Virtual screening with DrugCLIP
    DRUGCLIP(target_ch, compounds_ch)

    // Step 2: Plan synthesis for top hits (optional)
    if (params.plan_synthesis) {
        // Extract SMILES from top hits
        top_smiles_ch = DRUGCLIP.out.top_hits
            .splitCsv(header: true)
            .map { row -> [[id: row.compound_id], row.smiles] }
            .take(10)  // Top 10 for synthesis planning

        SYNCRAFT(top_smiles_ch)
        synthesis_ch = SYNCRAFT.out.route
    } else {
        synthesis_ch = Channel.empty()
    }

    emit:
    screening_results = DRUGCLIP.out.scores
    top_hits = DRUGCLIP.out.top_hits
    synthesis_routes = synthesis_ch
}

workflow {
    // Input channels
    target_ch = Channel.of([[id: 'target'], file(params.target_fasta)])
    compounds_ch = Channel.fromPath(params.compounds)

    // Run pipeline
    DRUG_DISCOVERY(target_ch, compounds_ch)

    // Summary
    DRUG_DISCOVERY.out.top_hits
        .subscribe { meta, hits ->
            println "Top ${params.top_k} hits saved to: ${hits}"
        }
}
