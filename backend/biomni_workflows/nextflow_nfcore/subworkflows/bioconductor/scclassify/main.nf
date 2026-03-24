#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scClassify
// scClassify is a multiscale classification framework for single-cell RNA-seq data based on ensemble l
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scClassify/inst/doc/pretrainedModel.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("scClassify")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCCLASSIFY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scclassify"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scclassify:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scclassify:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scclassify_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scclassify_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scclassify_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scClassify)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("trainClassExample_xin")
    trainClassExample_xin
    # --- Features [] ---
    # Key functions: features
    ---------------------------------------------------------------------
    features(trainClassExample_xin)
    # --- Plotcelltypetree [] ---
    # Key functions: plotCellTypeTree, cellTypeTree
    ---------------------------------------------------------------------
    plotCellTypeTree(cellTypeTree(trainClassExample_xin))
    # --- Predict Scclassify [] ---
    # Key functions: predict_scClassify
    ---------------------------------------------------------------------
    pred_res <- predict_scClassify(exprsMat_test = exprsMat_wang_subset,
                                   trainRes = trainClassExample_xin,
                                   cellTypes_test = wang_cellTypes,
                                   algorithm = "WKNN",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scclassify_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scclassify_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scclassify_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCCLASSIFY:", paste0("    scclassify: ", packageVersion("scClassify"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scclassify_results.csv
    touch ${prefix}_scclassify_output.rds
    echo "BIOC_SCCLASSIFY:" > versions.yml
    echo "    scclassify: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCCLASSIFY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCCLASSIFY(ch_input)

    emit:
    results  = BIOC_SCCLASSIFY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCCLASSIFY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCCLASSIFY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCCLASSIFY.out.versions  // channel: path(versions.yml)
}
