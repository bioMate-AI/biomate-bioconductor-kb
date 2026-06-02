#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RSVSim
// RSVSim is a package for the simulation of deletions, insertions, inversion, tandem-duplications and 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RSVSim/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RSVSim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSVSIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rsvsim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rsvsim:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rsvsim:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rsvsim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rsvsim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rsvsim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RSVSim)
    library(DNAStringSet)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Insertion and Inversion Simulation [] ---
    # Key functions: simulateSV
    sim_ins <- simulateSV(
        output = NA, genome = genome, ins = 3,
        sizeIns = 5, bpSeqSize = 6, seed = 246, verbose = FALSE
    )
    sim_inv <- simulateSV(
        output = NA, genome = genome, invs = 3,
        sizeInvs = c(2, 4, 6), bpSeqSize = 6, seed = 456, verbose = FALSE
    )


    # --- Structural Variant Size Estimation [] ---
    # Key functions: estimateSVSizes
    svSizes <- c(10, 20, 30, 40, 60, 80, 100, 150, 200, 250, 300)
    simSizes <- estimateSVSizes(
        n = 1000, svSizes = svSizes,
        minSize = 10, maxSize = 1000, hist = FALSE
    )
    delSizes <- estimateSVSizes(
        n = 1000, minSize = 500, maxSize = 10000,
        default = "deletions", hist = FALSE
    )


    # --- Structural Variant Comparison [] ---
    # Key functions: simulateSV, compareSV
    sim <- simulateSV(
        output = NA, genome = genome, dels = 5,
        sizeDels = 5, bpSeqSize = 10, seed = 2345, verbose = FALSE
    )
    simSVs <- GenomicRanges::metadata(sim)$deletions
    querySVs <- data.frame(
        chr = c("chr1", "chr1", "chr2"),
        start = c(12, 17, 2),
        end = c(15, 24, 6),
        bpSeq = c("AAAAAAAAAA", "AAAAAAATTT", "GGGGGGGGGG")
    )
    comparison <- compareSV(querySVs, simSVs, tol = 3)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rsvsim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rsvsim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rsvsim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RSVSIM:", paste0("    rsvsim: ", packageVersion("RSVSim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rsvsim_results.csv
    touch ${prefix}_rsvsim_output.rds
    echo "BIOC_RSVSIM:" > versions.yml
    echo "    rsvsim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RSVSIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RSVSIM(ch_input)

    emit:
    results  = BIOC_RSVSIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RSVSIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RSVSIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RSVSIM.out.versions  // channel: path(versions.yml)
}
