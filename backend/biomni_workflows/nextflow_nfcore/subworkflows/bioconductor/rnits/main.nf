#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rnits
// R/Bioconductor package for normalization, curve registration and inference in time course gene expre
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rnits/inst/doc/Rnits-vignette.R
// Upstream  : GEOquery, knitr, stringr
// Downstream: none
//
// Install: BiocManager::install("Rnits")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNITS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnits"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnits:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnits:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rnits_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnits_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnits_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Rnits)
    library(jsonlite)

    # --- Fetch GEO dataset [] ---
    # Key functions: getGEO, pData, fData
    library(knitr)
    rm(list = ls())
    library(GEOquery)
    # --- exprs [] ---
    # Key functions: exprs, pData, getLR
    Build rnits data object from formatted data (samples can be in any order)
    rnitsobj = build.Rnits(dat[, sample(ncol(dat))], logscale = TRUE, normmethod = "Between")
    datdf <-  exprs(dat)
    # --- fit [] ---
    # Key functions: fit
    rnitsobj <- fit(rnitsobj0, gene.level = TRUE, clusterallsamples = TRUE)
    # --- fit model noclustering [] ---
    # Key functions: fit, calculateGCV
    rnitsobj_nocl <- fit(rnitsobj0, gene.level = TRUE, clusterallsamples = FALSE)
    opt_model <- calculateGCV(rnitsobj0)
    rnitsobj_optmodel <- fit(rnitsobj0, gene.level = TRUE, model = opt_model)
    # --- get Pval [] ---
    # Key functions: getPval, getStat, getFitModel
    pval <- getPval(rnitsobj)
    head(pval)
    stat <- getStat(rnitsobj)
    # --- plot Results [] ---
    # Key functions: plotResults
    plotResults(rnitsobj, top = 16)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnits_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnits_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnits_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNITS:", paste0("    rnits: ", packageVersion("Rnits"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnits_results.csv
    touch ${prefix}_rnits_output.rds
    echo "BIOC_RNITS:" > versions.yml
    echo "    rnits: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNITS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RNITS(ch_input)

    emit:
    results  = BIOC_RNITS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNITS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNITS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNITS.out.versions  // channel: path(versions.yml)
}
