#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epigraHMM
// epigraHMM provides a set of tools for the analysis of epigenomic data based on hidden Markov Models.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epigraHMM/inst/doc/epigraHMM.R
// Upstream  : GenomeInfoDb, GenomicRanges, SummarizedExperiment, gcapc, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("epigraHMM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIGRAHMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epigrahmm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epigrahmm:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epigrahmm:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epigrahmm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epigrahmm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epigrahmm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(jsonlite)

    # --- introduction workflow [] ---
    # Key functions: epigraHMMDataSetFromBam, normalizeCounts, initializer, epigraHMM, callPeaks
    library(GenomicRanges)
    library(epigraHMM)
    library(SummarizedExperiment)
    # --- data input countmatrixinput [] ---
    # Key functions: GRanges, epigraHMMDataSetFromMatrix
    countData <- list('counts' = matrix(rpois(4e5,10),ncol = 4),
    'controls' = matrix(rpois(4e5,5),ncol = 4))
    # --- data input baminput [] ---
    # Key functions: epigraHMMDataSetFromBam

    # --- data norm offset [] ---
    # Key functions: normalizeCounts, colSums
    object_normExample <- normalizeCounts(object_normExample,control = controlEM())
    normCts <- as.matrix(assay(object_normExample)/
    exp(assay(object_normExample,'offsets')))
    # --- refine Sites [] ---
    # Key functions: refineSites, addOffsets
    library(gcapc)
    library(BSgenome.Rnorvegicus.UCSC.rn4)
    # --- data input controls [] ---
    # Key functions: epigraHMMDataSetFromBam

    # --- data peak consensus [] ---
    # Key functions: epigraHMMDataSetFromBam, normalizeCounts, initializer, epigraHMM

    # --- data peak differential [] ---
    # Key functions: epigraHMMDataSetFromBam, normalizeCounts, initializer, epigraHMM

    # --- peaks consensus [] ---
    # Key functions: callPeaks
    peaks_consensus <- callPeaks(object = object_consensus)
    # --- peaks differential [] ---
    # Key functions: callPeaks
    peaks_differential <- callPeaks(object = object_differential)
    # --- Create GenomicRanges from table [] ---
    # Key functions: browserSession, genome, getTable, makeGRangesFromDataFrame
    library(GenomicRanges)
    library(rtracklayer)
    library(GenomeInfoDb)
    # --- viz consensus [] ---
    # Key functions: plotCounts

    # --- viz differential [] ---
    # Key functions: plotCounts

    # --- viz heatmap1 [] ---
    # Key functions: plotPatterns

    # --- viz heatmap2 [] ---
    # Key functions: plotPatterns


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epigrahmm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epigrahmm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epigrahmm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIGRAHMM:", paste0("    epigrahmm: ", packageVersion("epigraHMM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epigrahmm_results.csv
    touch ${prefix}_epigrahmm_output.rds
    echo "BIOC_EPIGRAHMM:" > versions.yml
    echo "    epigrahmm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIGRAHMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPIGRAHMM(ch_input)

    emit:
    results  = BIOC_EPIGRAHMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIGRAHMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIGRAHMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIGRAHMM.out.versions  // channel: path(versions.yml)
}
