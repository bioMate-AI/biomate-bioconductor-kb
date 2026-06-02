#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: annotationTools
// Functions to annotate microarrays, find orthologs, and integrate heterogeneous gene expression profi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/annotationTools/inst/doc/annotationTools.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("annotationTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANNOTATIONTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-annotationtools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-annotationtools:1.80.0--r44_0' :
        'quay.io/biocontainers/bioconductor-annotationtools:1.80.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_annotationtools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_annotationtools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_annotationtools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(annotationTools)
    library(I)
    library(jsonlite)

    # --- Cross-Species Comparison Plotting [] ---
    # Key functions: getOrthologousProbesets
    orthops_maxAbsT_ind <- match(
        unlist(orthops_maxAbsT[[1]]),
        table_human[, 1]
    )
    plot(
        table_mouse[selection, 2],
        table_human[orthops_maxAbsT_ind, 2],
        pch = 19,
        col = "gray",
        xlab = "log fold change in mouse",
        ylab = "log fold change in human"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_annotationtools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_annotationtools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_annotationtools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANNOTATIONTOOLS:", paste0("    annotationtools: ", packageVersion("annotationTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_annotationtools_results.csv
    touch ${prefix}_annotationtools_output.rds
    echo "BIOC_ANNOTATIONTOOLS:" > versions.yml
    echo "    annotationtools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANNOTATIONTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANNOTATIONTOOLS(ch_input)

    emit:
    results  = BIOC_ANNOTATIONTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANNOTATIONTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANNOTATIONTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANNOTATIONTOOLS.out.versions  // channel: path(versions.yml)
}
