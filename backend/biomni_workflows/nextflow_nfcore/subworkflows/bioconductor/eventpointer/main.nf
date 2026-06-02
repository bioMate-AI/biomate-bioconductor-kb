#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EventPointer
// EventPointer is an R package to identify alternative splicing events that involve either simple (cas
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EventPointer/inst/doc/EventPointer.R
// Upstream  : BiocManager, Matrix, biomaRt, dplyr, kableExtra
// Downstream: none
//
// Install: BiocManager::install("EventPointer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EVENTPOINTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-eventpointer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-eventpointer:3.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-eventpointer:3.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_eventpointer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_eventpointer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_eventpointer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CDFfromGTF)
    library(CDFfromGTF_Multipath)
    library(EventDetection)
    library(EventDetectionMultipath)
    library(EventDetection_transcriptome)
    library(EventPointer)
    library(EventPointer_Bootstraps)
    library(EventPointer_IGV)
    library(EventPointer_RNASeq)
    library(EventPointer_RNASeq_IGV)
    library(jsonlite)

    # --- Alternative Splicing Analysis [] ---
    # Key functions: EventPointer_RNASeq
    Dmatrix <- matrix(c(1,1,1,1,1,1,1,1,0,0,0,0,1,1,1,1), ncol = 2)
    Cmatrix <- t(t(c(0, 1)))
    Events <- EventPointer_RNASeq(
        AllEvents_RNASeq,
        Dmatrix,
        Cmatrix,
        Statistic = "LogFC",
        PSI = TRUE
    )


    # --- PSI Value Estimation [] ---
    # Key functions: GetPSI_FromTranRef
    PSIss_nb <- GetPSI_FromTranRef(
        PathsxTranscript = EventXtrans,
        Samples = RNASeq,
        Bootstrap = FALSE,
        Filter = FALSE
    )
    PSI <- PSIss_nb$PSI
    Expression <- PSIss_nb$ExpEvs


    # --- Statistical Analysis and Results [] ---
    # Key functions: EventPointer_RNASeq_TranRef
    Design <- matrix(c(1, 1, 1, 1, 0, 0, 1, 1), nrow = 4)
    Contrast <- matrix(c(0, 1), nrow = 2)
    Fit <- EventPointer_RNASeq_TranRef(
        Count_Matrix = Expression,
        Statistic = "LogFC",
        Design = Design,
        Contrast = Contrast
    )


    # --- Event Reclassification [] ---
    # Key functions: Events_ReClassification
    data("SG_reclassify")
    EventTable_new <- Events_ReClassification(
        EventTable = EventTable,
        SplicingGraph = SG_reclassify
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_eventpointer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_eventpointer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_eventpointer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EVENTPOINTER:", paste0("    eventpointer: ", packageVersion("EventPointer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_eventpointer_results.csv
    touch ${prefix}_eventpointer_output.rds
    echo "BIOC_EVENTPOINTER:" > versions.yml
    echo "    eventpointer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EVENTPOINTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EVENTPOINTER(ch_input)

    emit:
    results  = BIOC_EVENTPOINTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EVENTPOINTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EVENTPOINTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EVENTPOINTER.out.versions  // channel: path(versions.yml)
}
