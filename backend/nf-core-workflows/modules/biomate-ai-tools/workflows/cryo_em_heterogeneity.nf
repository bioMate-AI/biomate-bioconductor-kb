#!/usr/bin/env nextflow
/*
 * Cryo-EM Conformational Heterogeneity Analysis Workflow
 *
 * 1. Train cryoDRGN VAE on particle stack (GPU)
 * 2. Analyze latent space: UMAP embedding + k-means → representative volumes
 * 3. Scan conformational ensemble for druggable pockets via fpocket
 * 4. Generate heterogeneity summary report
 *
 * Inputs:
 *   --particles   Path to particle stack (.mrcs)
 *   --ctf         Path to CTF parameters (.pkl)
 *   --n_zdim      Latent dimensionality          (default: 8)
 *   --n_epochs    Training epochs                (default: 20)
 *   --n_clusters  Conformational states to sample (default: 10)
 *   --epoch       Epoch to analyze (null = last) (default: null)
 *   --outdir      Output directory               (default: ./results)
 */

nextflow.enable.dsl=2

// ─── Parameter defaults ──────────────────────────────────────────────────────
params.particles  = null
params.ctf        = null
params.n_zdim     = 8
params.n_epochs   = 20
params.n_clusters = 10
params.epoch      = 'auto'   // 'auto' = detect last saved epoch
params.outdir     = './results'

// ─── Module imports ──────────────────────────────────────────────────────────
include { CRYODRGN_TRAIN       } from '../cryo_heterogeneity/main'
include { CRYODRGN_ANALYZE     } from '../cryo_heterogeneity/main'
include { POCKET_SCAN_ENSEMBLE } from '../cryo_heterogeneity/main'
include { HETEROGENEITY_REPORT } from '../cryo_heterogeneity/main'

// ─────────────────────────────────────────────────────────────────────────────
// WORKFLOW: CRYO_EM_HETEROGENEITY
// ─────────────────────────────────────────────────────────────────────────────
workflow CRYO_EM_HETEROGENEITY {

    take:
    particles_ch   // channel: [ val(meta), path(particles_mrcs) ]
    ctf_ch         // channel: path(ctf_pkl)
    n_zdim         // val
    n_epochs       // val
    epoch          // val (nullable)
    n_clusters     // val

    main:

    // Step 1: Train cryoDRGN VAE
    CRYODRGN_TRAIN(
        particles_ch,
        ctf_ch,
        n_zdim,
        n_epochs
    )

    // Step 2: Analyze latent space — UMAP + k-means → volumes
    CRYODRGN_ANALYZE(
        CRYODRGN_TRAIN.out.model_dir,
        epoch,
        n_clusters
    )

    // Step 3: Scan reconstructed ensemble for druggable pockets
    POCKET_SCAN_ENSEMBLE(
        CRYODRGN_ANALYZE.out.volumes
    )

    // Step 4: Compile heterogeneity report
    HETEROGENEITY_REPORT(
        CRYODRGN_ANALYZE.out.analysis_dir,
        POCKET_SCAN_ENSEMBLE.out.pockets
    )

    emit:
    model_dir   = CRYODRGN_TRAIN.out.model_dir        // [ meta, path ]
    analysis_dir= CRYODRGN_ANALYZE.out.analysis_dir   // [ meta, path ]
    umap        = CRYODRGN_ANALYZE.out.umap            // [ meta, path ]
    volumes     = CRYODRGN_ANALYZE.out.volumes         // [ meta, path ]
    pockets     = POCKET_SCAN_ENSEMBLE.out.pockets     // [ meta, path ]
    report      = HETEROGENEITY_REPORT.out.report      // [ meta, path ]
    versions    = CRYODRGN_TRAIN.out.versions          // path
}

// ─────────────────────────────────────────────────────────────────────────────
// STANDALONE ENTRY POINT (nextflow run workflows/cryo_em_heterogeneity.nf ...)
// ─────────────────────────────────────────────────────────────────────────────
workflow {

    // Validate required inputs
    if (!params.particles) {
        error "ERROR: --particles is required (path to .mrcs particle stack)"
    }
    if (!params.ctf) {
        error "ERROR: --ctf is required (path to CTF parameters .pkl file)"
    }

    log.info """
    ╔══════════════════════════════════════════════════════════╗
    ║    Cryo-EM Conformational Heterogeneity Analysis         ║
    ╠══════════════════════════════════════════════════════════╣
    ║  particles  : ${params.particles}
    ║  ctf        : ${params.ctf}
    ║  n_zdim     : ${params.n_zdim}
    ║  n_epochs   : ${params.n_epochs}
    ║  n_clusters : ${params.n_clusters}
    ║  epoch      : ${params.epoch ?: 'auto (last saved)'}
    ║  outdir     : ${params.outdir}
    ╚══════════════════════════════════════════════════════════╝
    """.stripIndent()

    // Build input channels
    particles_ch = Channel.of([[id: 'sample'], file(params.particles)])
    ctf_ch       = Channel.fromPath(params.ctf)

    // Run workflow
    CRYO_EM_HETEROGENEITY(
        particles_ch,
        ctf_ch,
        params.n_zdim,
        params.n_epochs,
        params.epoch,
        params.n_clusters
    )

    // Summary subscriptions
    CRYO_EM_HETEROGENEITY.out.umap
        .subscribe { meta, umap ->
            log.info "UMAP embedding: ${umap}"
        }

    CRYO_EM_HETEROGENEITY.out.volumes
        .subscribe { meta, vols ->
            def volList = vols instanceof List ? vols : [vols]
            log.info "Reconstructed ${volList.size()} conformational state volume(s)"
        }

    CRYO_EM_HETEROGENEITY.out.report
        .subscribe { meta, rpt ->
            log.info "Heterogeneity report: ${rpt}"
        }
}
