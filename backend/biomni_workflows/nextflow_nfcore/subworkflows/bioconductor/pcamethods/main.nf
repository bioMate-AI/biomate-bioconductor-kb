#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pcaMethods
// Provides Bayesian PCA, Probabilistic PCA, Nipals PCA, Inverse Non-Linear PCA and the conventional SV
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pcaMethods/inst/doc/missingValues.R
// Upstream  : Biobase, ggplot2
// Downstream: DeconRNASeq, crmn, DiffCorr, imputeLCMD
//
// Install: BiocManager::install("pcaMethods")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PCAMETHODS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pcamethods"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pcamethods:1.98.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pcamethods:1.98.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pcamethods_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pcamethods_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pcamethods_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pcaMethods)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: na
    data(metaboliteData)
    mD <- metaboliteData
    sum(is.na(mD))
    # --- Pca [] ---
    # Key functions: pca, completeObs
    pc <- pca(mD, nPcs=3, method="ppca")
    imputed <- completeObs(pc)
    # --- Data [] ---
    # Key functions: na
    data(metaboliteDataComplete)
    mdComp <- metaboliteDataComplete
    sum((mdComp[is.na(mD)] - imputed[is.na(mD)])^2) / sum(mdComp[is.na(mD)]^2)
    # --- Completeobs [] ---
    # Key functions: completeObs, pca, na
    imputedNipals <- completeObs(pca(mD, nPcs=3, method="nipals"))
    sum((mdComp[is.na(mD)] - imputedNipals[is.na(mD)])^2) / sum(mdComp[is.na(mD)]^2)
    # --- Data [] ---
    # Key functions: exprs, sample, na, pca, asExprSet
    library(Biobase)
    data(sample.ExpressionSet)
    exSet <- sample.ExpressionSet
    exSetNa <- exSet
    exprs(exSetNa)[sample(13000, 200)] <- NA

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pcamethods_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pcamethods_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pcamethods_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PCAMETHODS:", paste0("    pcamethods: ", packageVersion("pcaMethods"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pcamethods_results.csv
    touch ${prefix}_pcamethods_output.rds
    echo "BIOC_PCAMETHODS:" > versions.yml
    echo "    pcamethods: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PCAMETHODS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PCAMETHODS(ch_input)

    emit:
    results  = BIOC_PCAMETHODS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PCAMETHODS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PCAMETHODS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PCAMETHODS.out.versions  // channel: path(versions.yml)
}
