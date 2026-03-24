#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: msImpute
// MsImpute is a package for imputation of peptide intensity in proteomics experiments. It additionally
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/msImpute/inst/doc/msImpute-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("msImpute")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSIMPUTE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msimpute"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msimpute:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msimpute:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msimpute_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msimpute_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msimpute_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(QRILC)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(pxd014777)
    y <- pxd014777
    # --- Table [] ---
    # Key functions: infinite
    ---------------------------------------------------------------------
    table(is.infinite(data.matrix(log2(y))))
    # --- Normalizebetweenarrays [] ---
    # Key functions: normalizeBetweenArrays
    ---------------------------------------------------------------------
    # quantile normalisation
    y <- normalizeBetweenArrays(y, method = "quantile")
    # --- Factor [] ---
    # Key functions: factor, selectFeatures, nan, ifelse, na
    ---------------------------------------------------------------------
    batch <- as.factor(gsub("(2018.*)_RF.*","\\1", colnames(y)))
    experiment <- as.factor(gsub(".*(S[1-9]).*","\\1", colnames(y)))
    hdp <- selectFeatures(y, method = "ebm", group = batch)
    # peptides missing in one or more experimental group will have a NaN EBM, which is a measure of entropy of
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(pxd007959)
    sample_annot <- pxd007959$samples
    y <- pxd007959$y
    y <- log2(y)
    # --- Normalizebetweenarrays [] ---
    # Key functions: normalizeBetweenArrays
    ---------------------------------------------------------------------
    y <- normalizeBetweenArrays(y, method = "cyclicloess")
    # --- Qrilc [] ---
    # Key functions: QRILC, msImpute, factor
    ---------------------------------------------------------------------
    # imputation
    y_qrilc <- impute.QRILC(y)[[1]]
    y_msImpute <- msImpute(y, method = "v2-mnar", group = group)
    group <- as.factor(sample_annot$group)
    # --- Data [] ---
    # Key functions: infinite, normalizeBetweenArrays
    ---------------------------------------------------------------------
    data(pxd010943)
    y <- pxd010943
    # no problematic values for log- transformation
    table(is.infinite(data.matrix(log2(y))))
    # --- Factor [] ---
    # Key functions: factor, selectFeatures, nan, cases
    ---------------------------------------------------------------------
    group <- as.factor(gsub("_[1234]", "", colnames(y)))
    group
    hdp <- selectFeatures(y, method = "ebm", group = group)
    table(hdp$msImpute_feature)
    # --- Msimpute [] ---
    # Key functions: msImpute
    ---------------------------------------------------------------------
    y_msImpute_mar <- msImpute(y, method = "v2") # no need to specify group if data is MAR.
    y_msImpute_mnar <- msImpute(y, method = "v2-mnar", group = group)
    # --- Computestructuralmetrics [] ---
    # Key functions: computeStructuralMetrics
    ---------------------------------------------------------------------
    computeStructuralMetrics(y_msImpute_mar, group, y=NULL)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msimpute_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msimpute_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msimpute_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSIMPUTE:", paste0("    msimpute: ", packageVersion("msImpute"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msimpute_results.csv
    touch ${prefix}_msimpute_output.rds
    echo "BIOC_MSIMPUTE:" > versions.yml
    echo "    msimpute: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSIMPUTE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSIMPUTE(ch_input)

    emit:
    results  = BIOC_MSIMPUTE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSIMPUTE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSIMPUTE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSIMPUTE.out.versions  // channel: path(versions.yml)
}
