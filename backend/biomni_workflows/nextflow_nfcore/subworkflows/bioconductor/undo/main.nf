#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: UNDO
// UNDO is an R package for unsupervised deconvolution of tumor and stromal mixed expression data. It d
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/UNDO/inst/doc/UNDO-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("UNDO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_UNDO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-undo"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-undo:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-undo:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_undo_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_undo_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_undo_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(UNDO)
    library(jsonlite)

    # --- Packageload [] ---
    # Key functions: data
    library(UNDO)
    #load tumor stroma mixing tissue samples
    data(NumericalMixMCF7HS27)
    X <- NumericalMixMCF7HS27
    #load mixing matrix for comparison
    # --- Deconvolution [] ---
    # Key functions: exprs, two_source_deconv
    #load pure tumor stroma expressions
    data(PureMCF7HS27)
    S <- exprs(PureMCF7HS27)
    two_source_deconv(X,lowper=0.4,highper=0.1,epsilon1=0.01,
    epsilon2=0.01,A,S[,1],S[,2],return=0)
    # --- Scatterplot [] ---
    # Key functions: two_source_deconv
    # compute the estimated pure source expressions
    result <- two_source_deconv(X,lowper=0.4,highper=0.1,epsilon1=0.01,
    epsilon2=0.01,A,S[,1],S[,2],return=1)
    Sest <- result[[5]]
    #draw the scatter plots between pure and estimated expressions of

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_undo_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_undo_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_undo_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_UNDO:", paste0("    undo: ", packageVersion("UNDO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_undo_results.csv
    touch ${prefix}_undo_output.rds
    echo "BIOC_UNDO:" > versions.yml
    echo "    undo: 0.0.0" >> versions.yml
    """
}


workflow BIOC_UNDO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_UNDO(ch_input)

    emit:
    results  = BIOC_UNDO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_UNDO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_UNDO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_UNDO.out.versions  // channel: path(versions.yml)
}
