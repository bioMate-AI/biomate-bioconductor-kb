#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RNAmodR.AlkAnilineSeq
// RNAmodR.AlkAnilineSeq implements the detection of m7G, m3C and D modifications on RNA from experimen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RNAmodR.AlkAnilineSeq/inst/doc/RNAmodR.AlkAnilineSeq.R
// Upstream  : GenomicRanges, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("RNAmodR.AlkAnilineSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNAMODR_ALKANILINESEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnamodr_alkanilineseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnamodr.alkanilineseq:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnamodr.alkanilineseq:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rnamodr_alkanilineseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnamodr_alkanilineseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnamodr_alkanilineseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RNAmodR.AlkAnilineSeq)
    library(jsonlite)

    # --- Modification Detection and Extraction [] ---
    # Key functions: modifications
    mod <- modifications(msaas)
    coord <- mod[[1L]]
    alias <- data.frame(
        tx_id = c(1L, 3L, 5L, 6L, 7L, 8L, 10L, 11L),
        name = c("18S rRNA", "tF(GAA)B", "tG(GCC)B", "tT(AGT)B",
                 "tQ(TTG)B", "tC(GCA)B", "tS(CGA)C", "tV(AAC)E1"),
        stringsAsFactors = FALSE
    )


    # --- Visualization of Modification Data [] ---
    # Key functions: plotCompareByCoord, plotData
    plotCompareByCoord(msaas, coord, score = "scoreSR", alias = alias,
                       normalize = TRUE)
    plotCompareByCoord(msaas, coord[1L], score = "scoreSR", alias = alias)
    plotData(msaas, "1", from = 1550L, to = 1600L)
    plotData(msaas[1L:2L], "1", from = 1550L, to = 1600L,
             showSequenceData = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnamodr_alkanilineseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnamodr_alkanilineseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnamodr_alkanilineseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNAMODR_ALKANILINESEQ:", paste0("    rnamodr_alkanilineseq: ", packageVersion("RNAmodR.AlkAnilineSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnamodr_alkanilineseq_results.csv
    touch ${prefix}_rnamodr_alkanilineseq_output.rds
    echo "BIOC_RNAMODR_ALKANILINESEQ:" > versions.yml
    echo "    rnamodr_alkanilineseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNAMODR_ALKANILINESEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RNAMODR_ALKANILINESEQ(ch_input)

    emit:
    results  = BIOC_RNAMODR_ALKANILINESEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNAMODR_ALKANILINESEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNAMODR_ALKANILINESEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNAMODR_ALKANILINESEQ.out.versions  // channel: path(versions.yml)
}
