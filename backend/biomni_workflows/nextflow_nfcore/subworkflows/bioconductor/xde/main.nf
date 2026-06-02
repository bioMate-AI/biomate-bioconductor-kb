#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: XDE
// Multi-level model for cross-study detection of differential gene expression.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/XDE/inst/doc/XDE.R
// Upstream  : GeneMeta, siggenes
// Downstream: none
//
// Install: BiocManager::install("XDE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XDE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-xde"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-xde:2.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-xde:2.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_xde_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_xde_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_xde_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(XDE)
    library(jsonlite)

    # --- Parameter Configuration [] ---
    # Key functions: XdeParameter
    data(expressionSetList, package = "XDE")
    xlist <- expressionSetList
    params <- new("XdeParameter",
                  esetList = xlist,
                  phenotypeLabel = "adenoVsquamous")


    # --- MCMC Log Extraction [] ---
    # Key functions: output
    data(xmcmc, package = "XDE")
    pathToLogFiles <- system.file("logFiles", package = "XDE")
    xmcmc@directory <- pathToLogFiles
    c2 <- xmcmc$c2
    active_params <- output(xmcmc)[2:22]
    active_params <- active_params[active_params == 1]


    # --- Posterior Probability Analysis [] ---
    # Key functions: symbolsInteresting
    pathToLogFiles <- system.file("logFiles", package = "XDE")
    load(file.path(pathToLogFiles, "postAvg.rda"))
    op.conc <- symbolsInteresting(
        rankingStatistic = postAvg[, "concordant"]
    )
    op.disc <- symbolsInteresting(
        rankingStatistic = postAvg[, "discordant"]
    )


    # --- Visualisation of Concordant and Discordant Expression [] ---
    # Key functions: symbolsInteresting
    pathToLogFiles <- system.file("logFiles", package = "XDE")
    load(file.path(pathToLogFiles, "BES.rda"))
    load(file.path(pathToLogFiles, "postAvg.rda"))
    op.conc <- symbolsInteresting(rankingStatistic = postAvg[, "concordant"])
    graphics:::pairs(BES[op.conc$order, ],
                     pch = op.conc$pch,
                     col = op.conc$col,
                     bg = op.conc$bg,
                     upper.panel = NULL,
                     cex = op.conc$cex)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_xde_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_xde_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_xde_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_XDE:", paste0("    xde: ", packageVersion("XDE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xde_results.csv
    touch ${prefix}_xde_output.rds
    echo "BIOC_XDE:" > versions.yml
    echo "    xde: 0.0.0" >> versions.yml
    """
}


workflow BIOC_XDE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_XDE(ch_input)

    emit:
    results  = BIOC_XDE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_XDE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_XDE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_XDE.out.versions  // channel: path(versions.yml)
}
