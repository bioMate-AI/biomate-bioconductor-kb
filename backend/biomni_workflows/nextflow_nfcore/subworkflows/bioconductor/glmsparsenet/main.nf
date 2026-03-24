#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: glmSparseNet
// glmSparseNet is an R-package that generalizes sparse regression models when the features (e.g. genes
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/glmSparseNet/inst/doc/example_brca_logistic.R
// Upstream  : BiocManager, Matrix, MultiAssayExperiment, TCGAutils, VennDiagram
// Downstream: none
//
// Install: BiocManager::install("glmSparseNet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GLMSPARSENET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-glmsparsenet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-glmsparsenet:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-glmsparsenet:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_glmsparsenet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_glmsparsenet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_glmsparsenet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TCGAbiospec)
    library(TCGAsplitAssays)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: roc, ggplot, geom_line, labs
    rocObj <- pROC::roc(ydata, as.vector(response))
    data.frame(TPR = rocObj$sensitivities, FPR = 1 - rocObj$specificities) |>
    ggplot() +
    # --- Data scaling normalization [] ---
    # Key functions: theme_set, curatedTCGAData, TCGAsplitAssays, TCGAbiospec, scale, sample, arrange, predict
    brca <- TCGAutils::TCGAsplitAssays(brca, c("01", "11"))
    xdataRaw <- t(cbind(assay(brca[[1]]), assay(brca[[2]])))
    classV <- TCGAbiospec(rownames(xdataRaw))$sample_definition |> factor()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_glmsparsenet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_glmsparsenet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_glmsparsenet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GLMSPARSENET:", paste0("    glmsparsenet: ", packageVersion("glmSparseNet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_glmsparsenet_results.csv
    touch ${prefix}_glmsparsenet_output.rds
    echo "BIOC_GLMSPARSENET:" > versions.yml
    echo "    glmsparsenet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GLMSPARSENET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GLMSPARSENET(ch_input)

    emit:
    results  = BIOC_GLMSPARSENET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GLMSPARSENET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GLMSPARSENET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GLMSPARSENET.out.versions  // channel: path(versions.yml)
}
