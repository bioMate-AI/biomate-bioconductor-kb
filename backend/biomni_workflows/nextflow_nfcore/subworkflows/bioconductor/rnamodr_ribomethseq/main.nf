#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RNAmodR.RiboMethSeq
// RNAmodR.RiboMethSeq implements the detection of 2'-O methylations on RNA from experimental data gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RNAmodR.RiboMethSeq/inst/doc/RNAmodR.RiboMethSeq.R
// Upstream  : GenomicRanges, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("RNAmodR.RiboMethSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNAMODR_RIBOMETHSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnamodr_ribomethseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnamodr.ribomethseq:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnamodr.ribomethseq:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rnamodr_ribomethseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnamodr_ribomethseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnamodr_ribomethseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RNAmodR.RiboMethSeq)
    library(jsonlite)

    # --- plot Compare By Coord [] ---
    # Key functions: plotCompareByCoord
    plotCompareByCoord(msrms[c(2L,1L)], coord, alias = alias)
    # --- plot Data By Coord [] ---
    # Key functions: plotDataByCoord
    plotDataByCoord(msrms, singleCoord)
    # --- plot R O C [] ---
    # Key functions: plotROC
    plotROC(msrms,coord)
    # --- settings [] ---
    # Key functions: settings
    settings(msrms) <- list(minScoreMean = 0.7)
    # --- modify [] ---
    # Key functions: modify
    msrms2 <- modify(msrms,force = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnamodr_ribomethseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnamodr_ribomethseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnamodr_ribomethseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNAMODR_RIBOMETHSEQ:", paste0("    rnamodr_ribomethseq: ", packageVersion("RNAmodR.RiboMethSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnamodr_ribomethseq_results.csv
    touch ${prefix}_rnamodr_ribomethseq_output.rds
    echo "BIOC_RNAMODR_RIBOMETHSEQ:" > versions.yml
    echo "    rnamodr_ribomethseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNAMODR_RIBOMETHSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RNAMODR_RIBOMETHSEQ(ch_input)

    emit:
    results  = BIOC_RNAMODR_RIBOMETHSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNAMODR_RIBOMETHSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNAMODR_RIBOMETHSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNAMODR_RIBOMETHSEQ.out.versions  // channel: path(versions.yml)
}
