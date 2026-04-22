#!/usr/bin/env nextflow
/*
 * Protein Dynamics Conformational Ensemble Pipeline
 *
 * Stages
 *   1. BIOEMU_SAMPLE          — GPU — sample ensemble with Microsoft BioEmu-1
 *   2. POCKET_MINER           — CPU — detect cryptic pockets per conformer
 *   3. CONFORMATIONAL_SUMMARY — CPU — RMSD/Rg statistics + UMAP figure
 *
 * Inputs
 *   --input_pdb       Path to input PDB or FASTA  (required)
 *   --n_samples       Number of conformations to generate  (default: 100)
 *   --ligand_smiles   Optional SMILES string (reserved for DynamicBind integration)
 *   --outdir          Output directory / S3 prefix  (default: ./results)
 *
 * Usage (local)
 *   nextflow run workflows/protein_dynamics_ensemble.nf \
 *       --input_pdb  1UBQ.pdb \
 *       --n_samples  50 \
 *       --outdir     ./results
 *
 * Usage (AWS Batch)
 *   nextflow run workflows/protein_dynamics_ensemble.nf \
 *       -profile aws \
 *       --input_pdb  s3://biomate-nextflow-work/inputs/1UBQ.pdb \
 *       --n_samples  100 \
 *       --outdir     s3://biomate-nextflow-work/outputs/protein-dynamics/
 */

nextflow.enable.dsl=2

// ── Parameter defaults ────────────────────────────────────────────────────────
params.input_pdb      = null
params.n_samples      = 100
params.ligand_smiles  = null   // reserved for future DynamicBind integration
params.outdir         = './results'

// ── Module imports ────────────────────────────────────────────────────────────
include { BIOEMU_SAMPLE          } from '../protein_dynamics/main'
include { POCKET_MINER           } from '../protein_dynamics/main'
include { CONFORMATIONAL_SUMMARY } from '../protein_dynamics/main'

// ─────────────────────────────────────────────────────────────────────────────
// PROTEIN_DYNAMICS_ENSEMBLE workflow
// ─────────────────────────────────────────────────────────────────────────────
workflow PROTEIN_DYNAMICS_ENSEMBLE {

    take:
    input_ch    // channel: [ val(meta), path(pdb_or_fasta) ]
    n_samples   // val: integer

    main:

    // ── Stage 1: Sample conformational ensemble ───────────────────────────────
    BIOEMU_SAMPLE(
        input_ch,
        n_samples
    )

    // ── Stage 2: Pocket mining across ensemble ────────────────────────────────
    POCKET_MINER(
        BIOEMU_SAMPLE.out.ensemble
    )

    // ── Stage 3: Compute statistics and render visualisation ──────────────────
    // Join ensemble + pockets on meta.id
    ensemble_and_pockets = BIOEMU_SAMPLE.out.ensemble
        .join(POCKET_MINER.out.pockets, by: 0)

    CONFORMATIONAL_SUMMARY(
        ensemble_and_pockets.map { meta, ens, pock -> [ meta, ens ] },
        ensemble_and_pockets.map { meta, ens, pock -> [ meta, pock ] }
    )

    // ── Publish all results ───────────────────────────────────────────────────
    BIOEMU_SAMPLE.out.ensemble
        .map { meta, f -> f }
        .collectFile(storeDir: "${params.outdir}/ensemble")

    POCKET_MINER.out.pockets
        .map { meta, f -> f }
        .collectFile(storeDir: "${params.outdir}/pockets")

    POCKET_MINER.out.pocket_viz
        .map { meta, f -> f }
        .collectFile(storeDir: "${params.outdir}/pockets")

    CONFORMATIONAL_SUMMARY.out.report
        .map { meta, f -> f }
        .collectFile(storeDir: "${params.outdir}/summary")

    CONFORMATIONAL_SUMMARY.out.umap
        .map { meta, f -> f }
        .collectFile(storeDir: "${params.outdir}/summary")

    emit:
    ensemble   = BIOEMU_SAMPLE.out.ensemble        // [ meta, *_ensemble.tar.gz ]
    pockets    = POCKET_MINER.out.pockets          // [ meta, *_pockets.json ]
    pocket_viz = POCKET_MINER.out.pocket_viz       // [ meta, *_pockets.pdb ] (optional)
    report     = CONFORMATIONAL_SUMMARY.out.report // [ meta, summary_report.json ]
    umap       = CONFORMATIONAL_SUMMARY.out.umap   // [ meta, conformational_umap.png ]
}

// ─────────────────────────────────────────────────────────────────────────────
// Standalone entry point
// ─────────────────────────────────────────────────────────────────────────────
workflow {

    // Validate required params
    if (!params.input_pdb) {
        error "ERROR: --input_pdb is required.\nUsage: nextflow run workflows/protein_dynamics_ensemble.nf --input_pdb <path|s3> --n_samples 100 --outdir ./results"
    }

    // Build sample ID from filename
    def sample_id = file(params.input_pdb).baseName

    // Build input channel: [ val(meta), path(pdb_or_fasta) ]
    input_ch = Channel.of([
        [id: sample_id],
        file(params.input_pdb)
    ])

    // Run workflow
    PROTEIN_DYNAMICS_ENSEMBLE(input_ch, params.n_samples)

    // Print result paths to stdout
    PROTEIN_DYNAMICS_ENSEMBLE.out.report
        .subscribe { meta, report ->
            println "=== CONFORMATIONAL ENSEMBLE COMPLETE ==="
            println "  Sample ID   : ${meta.id}"
            println "  Report      : ${params.outdir}/summary/${report.name}"
            println "  UMAP plot   : ${params.outdir}/summary/conformational_umap.png"
            println "  Ensemble    : ${params.outdir}/ensemble/${meta.id}_ensemble.tar.gz"
            println "  Pockets     : ${params.outdir}/pockets/${meta.id}_pockets.json"
            if (params.ligand_smiles) {
                println "  [NOTE] --ligand_smiles '${params.ligand_smiles}' stored; DynamicBind integration is planned for a future phase."
            }
        }
}
