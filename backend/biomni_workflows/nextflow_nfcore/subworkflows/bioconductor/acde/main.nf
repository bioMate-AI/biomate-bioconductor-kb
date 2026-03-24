#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: acde
// This package provides a multivariate inferential analysis method for detecting differentially expres
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/acde/inst/doc/acde.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("acde")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ACDE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-acde"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-acde:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-acde:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_acde_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_acde_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_acde_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(acde)
    library(jsonlite)

    # --- Analysis [] ---
    # Key functions: analysis, stp
    ## ## Single time point analysis (36 hai)
    ## dat <- phytophthora[[3]]
    ## des <- c(rep(1,8), rep(2,8))
    ## ### For a quick run, set BCa=FALSE
    ## stpPI <- stp(dat, des, BCa=TRUE)
    # --- Vector [] ---
    # Key functions: tc
    ## ## Time course analysis
    ## desPI <- vector("list",4)
    ## for(tp in 1:4) desPI[[tp]] <- c(rep(1,8), rep(2,8))
    ## tcPI <- tc(phytophthora, desPI)
    # --- Stppi [] ---
    # Key functions: stp
    ## library(acde)
    ## dat <- phytophthora[[3]]
    ## des <- c(rep(1,8), rep(2,8))
    ## stpPI <- stp(dat, des, BCa=TRUE)
    # --- Plotstp [] ---
    # Key functions: off
    golden <- 1.1*(1+sqrt(5))/2
    hi <- 4
    pdf("acde-plotStpFDR.pdf", width=golden*hi, height=hi, fonts="Times")
    par(mfrow=c(1,1), mar=c(4, 4, 0.1, 1), las=1, family="Times")
    plot(stpPI, AC=FALSE)
    # --- Tcpi [] ---
    # Key functions: tc
    ## desPI <- vector("list",4)
    ## for(tp in 1:4) desPI[[tp]] <- c(rep(1,8), rep(2,8))
    ## tcPI <- tc(phytophthora, desPI)
    # --- Plottcpi1 [] ---
    # Key functions: off
    tcAux1 <- tcPI; tcAux1$gct <- "Not computed."
    hi <- 6
    pdf("acde-plotTcPI1.pdf", width=golden*hi, height=hi, fonts="Times")
    par(mfrow=c(1,1), mar=c(4, 4, 0.1, 1), las=1, family="Times")
    plot(tcAux1, iRatios=FALSE, FDR=FALSE)
    # --- Plottcpi2 [] ---
    # Key functions: off
    tcAux2 <- tcPI; tcAux2$act <- "Not computed."
    pdf("acde-plotTcPI2.pdf", width=golden*hi, height=hi, fonts="Times")
    par(mfrow=c(1,1), mar=c(4, 4, 0.1, 1), las=1, family="Times")
    plot(tcAux2, iRatios=FALSE, AC=FALSE)
    invisible(dev.off())
    # --- Plottcpi3 [] ---
    # Key functions: off
    pdf("acde-plotTcPI3.pdf", width=golden*hi, height=hi, fonts="Times")
    par(mfrow=c(1,1), mar=c(4, 4, 0.1, 1), las=1, family="Times")
    plot(tcAux2, iRatios=FALSE, FDR=FALSE)
    invisible(dev.off())

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_acde_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_acde_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_acde_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ACDE:", paste0("    acde: ", packageVersion("acde"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_acde_results.csv
    touch ${prefix}_acde_output.rds
    echo "BIOC_ACDE:" > versions.yml
    echo "    acde: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ACDE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ACDE(ch_input)

    emit:
    results  = BIOC_ACDE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ACDE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ACDE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ACDE.out.versions  // channel: path(versions.yml)
}
