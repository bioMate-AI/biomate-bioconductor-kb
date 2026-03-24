#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: edge
// The edge package implements methods for carrying out differential expression analyses of genome-wide
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/edge/inst/doc/edge.R
// Upstream  : ggplot2, reshape2, splines
// Downstream: none
//
// Install: BiocManager::install("edge")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EDGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-edge"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-edge:2.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-edge:2.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_edge_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_edge_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_edge_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExpressionSet)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: ExpressionSet
    library(edge)
    anon_df <- as(data.frame(age=age, sex=sex), "AnnotatedDataFrame")
    exp_set <- ExpressionSet(assayData = kidexpr, phenoData = anon_df)
    # --- Quality control and filtering [] ---
    # Key functions: exprs, pData, build_models, slotNames
    library(splines)
    cov <- data.frame(sex = sex, age = age)
    null_model <- ~sex + ns(age, df=4)
    # --- PackageDescription analysis [] ---
    # Key functions: packageDescription, build_study, fullModel, nullModel, build_models, odp, lrt, qvalueObj
    cov <- data.frame(ind = ind, tme = time, grp = class)
    null_model <- ~grp + ns(tme, df = 2, intercept = FALSE)
    null_model <- ~grp + ns(tme, df = 2, intercept = FALSE) + (grp):ns(tme, df = 2, intercept = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_edge_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_edge_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_edge_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EDGE:", paste0("    edge: ", packageVersion("edge"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_edge_results.csv
    touch ${prefix}_edge_output.rds
    echo "BIOC_EDGE:" > versions.yml
    echo "    edge: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EDGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EDGE(ch_input)

    emit:
    results  = BIOC_EDGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EDGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EDGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EDGE.out.versions  // channel: path(versions.yml)
}
