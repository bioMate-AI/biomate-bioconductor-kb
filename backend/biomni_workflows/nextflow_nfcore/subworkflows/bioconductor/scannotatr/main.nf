#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scAnnotatR
// The package comprises a set of pretrained machine learning models to predict basic immune cell types
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scAnnotatR/inst/doc/classifying-cells.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("scAnnotatR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCANNOTATR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scannotatr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scannotatr:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scannotatr:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scannotatr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scannotatr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scannotatr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scAnnotatR)
    library(jsonlite)

    # --- Load Models [] ---
    # Key functions: load_models
    ---------------------------------------------------------------------
    default_models <- load_models("default")
    names(default_models)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    # load the example dataset
    data("tirosh_mel80_example")
    tirosh_mel80_example
    # --- Classify Cells [] ---
    # Key functions: classify_cells
    ---------------------------------------------------------------------
    seurat.obj <- classify_cells(classify_obj = tirosh_mel80_example,
                                 assay = 'RNA', slot = 'counts',
                                 cell_types = c('B cells', 'NK', 'T cells'),
                                 path_to_models = 'default')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scannotatr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scannotatr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scannotatr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCANNOTATR:", paste0("    scannotatr: ", packageVersion("scAnnotatR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scannotatr_results.csv
    touch ${prefix}_scannotatr_output.rds
    echo "BIOC_SCANNOTATR:" > versions.yml
    echo "    scannotatr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCANNOTATR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCANNOTATR(ch_input)

    emit:
    results  = BIOC_SCANNOTATR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCANNOTATR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCANNOTATR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCANNOTATR.out.versions  // channel: path(versions.yml)
}
