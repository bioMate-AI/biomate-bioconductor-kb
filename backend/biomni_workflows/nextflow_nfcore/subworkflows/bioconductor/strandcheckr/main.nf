#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: strandCheckR
// This package aims to quantify and remove putative double strand DNA from a strand-specific RNA sampl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/strandCheckR/inst/doc/strandCheckR.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("strandCheckR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_STRANDCHECKR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-strandcheckr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-strandcheckr:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-strandcheckr:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_strandcheckr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_strandcheckr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_strandcheckr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(strandCheckR)
    library(jsonlite)

    # --- get Strand From Bam File [] ---
    # Key functions: getStrandFromBamFile
    library(strandCheckR)
    # --- transcripts [] ---
    # Key functions: transcripts, intersectWithFeature
    library(TxDb.Hsapiens.UCSC.hg38.knownGene)
    annot <- transcripts(TxDb.Hsapiens.UCSC.hg38.knownGene)
    win$Seq <- paste0("chr",win$Seq)
    # --- plot Hist [] ---
    # Key functions: plotHist

    # --- plot Win [] ---
    # Key functions: plotWin
    plotWin(win, groupBy = "File")
    # --- plot Hist [] ---
    # Key functions: plotHist, ggtitle
    win2$File <- basename(as.character(win2$File))
    win2$File <- factor(win2$File,levels = c("s2.sorted.bam","s2.filter.bam"))
    library(ggplot2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_strandcheckr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_strandcheckr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_strandcheckr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_STRANDCHECKR:", paste0("    strandcheckr: ", packageVersion("strandCheckR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_strandcheckr_results.csv
    touch ${prefix}_strandcheckr_output.rds
    echo "BIOC_STRANDCHECKR:" > versions.yml
    echo "    strandcheckr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_STRANDCHECKR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_STRANDCHECKR(ch_input)

    emit:
    results  = BIOC_STRANDCHECKR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_STRANDCHECKR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_STRANDCHECKR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_STRANDCHECKR.out.versions  // channel: path(versions.yml)
}
