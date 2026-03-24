#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sevenC
// Chromatin looping is an essential feature of eukaryotic genomes and can bring regulatory sequences, 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sevenC/inst/doc/sevenC.R
// Upstream  : GenomicInteractions
// Downstream: none
//
// Install: BiocManager::install("sevenC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEVENC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sevenc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sevenc:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sevenc:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sevenc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sevenc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sevenc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sevenC)
    library(jsonlite)

    # --- Predloops [] ---
    # Key functions: predLoops
    ---------------------------------------------------------------------
    # predict looping interactions among all motif pairs
    loops <- predLoops(gi)
    # --- Preparecispairs [] ---
    # Key functions: prepareCisPairs
    ---------------------------------------------------------------------
    gi <- prepareCisPairs(motifs, maxDist = 10^6)
    gi
    # --- Addcovcor [] ---
    # Key functions: addCovCor
    ---------------------------------------------------------------------
    # add ChIP-seq coverage and compute correaltion at motif pairs
    gi <- addCovCor(gi)
    # --- Predloops [] ---
    # Key functions: predLoops
    ---------------------------------------------------------------------
    loops <- predLoops(gi)
    loops
    # --- Addinteractionsupport [] ---
    # Key functions: addInteractionSupport
    ---------------------------------------------------------------------
    # add known loops
    gi <- addInteractionSupport(gi, knownLoops)
    # --- Glm [] ---
    # Key functions: glm, mcols, binomial
    ---------------------------------------------------------------------
    fit <- glm(
      formula = loop ~ cor_chip + dist + strandOrientation,
      data = mcols(gi),
      family = binomial()
    # --- Predloops [] ---
    # Key functions: predLoops, coef
    ---------------------------------------------------------------------
    # add predict loops
    gi <- predLoops(
      gi,
      formula = loop ~ cor_chip + dist + strandOrientation,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sevenc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sevenc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sevenc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEVENC:", paste0("    sevenc: ", packageVersion("sevenC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sevenc_results.csv
    touch ${prefix}_sevenc_output.rds
    echo "BIOC_SEVENC:" > versions.yml
    echo "    sevenc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEVENC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEVENC(ch_input)

    emit:
    results  = BIOC_SEVENC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEVENC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEVENC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEVENC.out.versions  // channel: path(versions.yml)
}
