#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: QTLExperiment
// QLTExperiment defines an S4 class for storing and manipulating summary statistics from QTL mapping e
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/QTLExperiment/inst/doc/QTLExperiment.R
// Upstream  : none
// Downstream: multistateQTL
//
// Install: BiocManager::install("QTLExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QTLEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-qtlexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-qtlexperiment:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-qtlexperiment:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_qtlexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_qtlexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_qtlexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(QTLExperiment)
    library(jsonlite)

    # --- Assay data access [] ---
    # Key functions: mockSummaryStats, QTLExperiment, mockQTLE, sumstats2qtle, mockMASHR, mash2qtle, state_id, feature_id
    mock_summary_stats <- mockSummaryStats(nStates=nStates, nQTL=nQTL, names=FALSE)
    qtle <- QTLExperiment(assays=list(betas=mock_summary_stats$betas,
    feature_id=paste0("gene_", 1:nQTL),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_qtlexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_qtlexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_qtlexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_QTLEXPERIMENT:", paste0("    qtlexperiment: ", packageVersion("QTLExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qtlexperiment_results.csv
    touch ${prefix}_qtlexperiment_output.rds
    echo "BIOC_QTLEXPERIMENT:" > versions.yml
    echo "    qtlexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_QTLEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_QTLEXPERIMENT(ch_input)

    emit:
    results  = BIOC_QTLEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_QTLEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_QTLEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_QTLEXPERIMENT.out.versions  // channel: path(versions.yml)
}
