#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rexposome
// Package that allows to explore the exposome and to perform association analyses between exposures an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rexposome/inst/doc/exposome_data_analysis.R
// Upstream  : ggplot2, mice
// Downstream: none
//
// Install: BiocManager::install("rexposome")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REXPOSOME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rexposome"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rexposome:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rexposome:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rexposome_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rexposome_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rexposome_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rexposome)
    library(jsonlite)

    # --- Quality control and filtering [] ---
    # Key functions: pData, levels, factor, exwas, formula
    strat_variable <- "sex"
    formula <- cbmi ~ 1
    family <- "gaussian"
    strat_ex <- lapply(levels(as.factor(pData(exp)[[strat_variable]])), function(i){
          mask <- pData(exp)[[strat_variable]]==i
    # --- Path analysis [] ---
    # Key functions: path, package, readExposome, csv, loadExposome, sampleNames, exposureNames, fData
    path <- file.path(path.package("rexposome"), "extdata")
    description <- file.path(path, "description.csv")
    phenotype <- file.path(path, "phenotypes.csv")
    exposures <- file.path(path, "exposures.csv")
    # --- Clustering and classification [] ---
    # Key functions: hclust, dist
    hclust_data <- function(data, ...) {
        hclust(d = dist(x = data), ...)
    }
    # --- Visualization and reporting [] ---
    # Key functions: plotPCA
    plotPCA(exp_pca, set = "samples", phenotype = "sex")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rexposome_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rexposome_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rexposome_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REXPOSOME:", paste0("    rexposome: ", packageVersion("rexposome"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rexposome_results.csv
    touch ${prefix}_rexposome_output.rds
    echo "BIOC_REXPOSOME:" > versions.yml
    echo "    rexposome: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REXPOSOME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REXPOSOME(ch_input)

    emit:
    results  = BIOC_REXPOSOME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REXPOSOME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REXPOSOME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REXPOSOME.out.versions  // channel: path(versions.yml)
}
