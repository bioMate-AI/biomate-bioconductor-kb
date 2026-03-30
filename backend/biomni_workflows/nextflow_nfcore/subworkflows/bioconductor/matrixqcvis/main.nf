#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MatrixQCvis
// Data quality assessment is an integral part of preparatory data analysis to ensure sound biological 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MatrixQCvis/inst/doc/MatrixQCvis.R
// Upstream  : ExperimentHub, knitr, limma
// Downstream: none
//
// Install: BiocManager::install("MatrixQCvis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MATRIXQCVIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-matrixqcvis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-matrixqcvis:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-matrixqcvis:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_matrixqcvis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_matrixqcvis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_matrixqcvis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ECDF)
    library(ExperimentHub)
    library(MAplot)
    library(MAvalues)
    library(jsonlite)

    # --- Access ExperimentHub data [] ---
    # Key functions: ExperimentHub
    library(ExperimentHub)
    eh <- ExperimentHub()
    se <- se[, seq_len(40)]
    # --- Define comparison contrasts [] ---
    # Key functions: makeContrasts, assay, normalizeAssay, transformAssay, imputeAssay, lmFit
    library(limma)
    cM <- makeContrasts(contrasts = "typeBRCA-typeLUAD", levels = mM)
    head(cM)
    # --- Mean-SD plot for transformed data [] ---
    # Key functions: meanSdPlot
    vsn::meanSdPlot(assay(se_t))
    # --- Assay data access [] ---
    # Key functions: hist_sample_num, partial_bundle, mosaic, createBoxplot, assay, normalizeAssay, batchCorrectionAssay, transformAssay
    l_assays <- list(raw = a, normalized = a_n, `batch.corrected` = a_b,
    df_feature <- createDfFeature(l_assays, feature = rownames(se)[1])
    featurePlot(df_feature)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_matrixqcvis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_matrixqcvis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_matrixqcvis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MATRIXQCVIS:", paste0("    matrixqcvis: ", packageVersion("MatrixQCvis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrixqcvis_results.csv
    touch ${prefix}_matrixqcvis_output.rds
    echo "BIOC_MATRIXQCVIS:" > versions.yml
    echo "    matrixqcvis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MATRIXQCVIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MATRIXQCVIS(ch_input)

    emit:
    results  = BIOC_MATRIXQCVIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MATRIXQCVIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MATRIXQCVIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MATRIXQCVIS.out.versions  // channel: path(versions.yml)
}
