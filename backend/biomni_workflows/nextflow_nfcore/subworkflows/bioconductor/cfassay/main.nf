#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CFAssay
// The package provides functions for calculation of linear-quadratic cell survival curves and for ANOV
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CFAssay/inst/doc/cfassay.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CFAssay")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CFASSAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cfassay"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cfassay:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cfassay:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cfassay_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cfassay_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cfassay_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CFAssay)
    library(jsonlite)

    # --- Table [] ---
    # Key functions: file
    library(CFAssay)
    datatab <- read.table(system.file("doc", "expl1_cellsurvcurves.txt",
                                      package="CFAssay"), header=TRUE, sep="\t")
    # --- Subset [] ---
    # Key functions: cellsurvLQfit
    X <- subset(datatab, cline=="okf6TERT1")
      dim(X)
      fit <- cellsurvLQfit(X)
      print(fit)
    # --- Fig1 [] ---
    # Key functions: pes, sfpmean
    plot(fit)
      S0 <- pes(X)$S0
      names(S0) <- pes(X)$Exp
      sfpmean(X, S0)
    # --- Pdf [] ---
    # Key functions: plotExp, off
    ##   pdf("okf6TERT1_experimental_plots.pdf")
    ##   	plotExp(fit)
    ##   dev.off()
    # --- Subset [] ---
    # Key functions: cellsurvLQfit, plotExp
    ##   X <- subset(datatab, cline=="cal33")
    ##   dim(X)
    ##   fit <- cellsurvLQfit(X)
    ##   print(fit)
    ##   plot(fit)
    # --- Cellsurvlqdiff [] ---
    # Key functions: cellsurvLQdiff
    fitcomp <- cellsurvLQdiff(datatab, curvevar="cline")
      print(fitcomp)
    # --- Fig2 [] ---
    # Key functions: cellsurvLQfit
    plot(cellsurvLQfit(subset(datatab, cline=="okf6TERT1")), col=1)
      plot(cellsurvLQfit(subset(datatab, cline=="cal33")), col=2, add=TRUE)
      legend(0, 0.02, c("OKF6/TERT1", "CAL 33"), text.col=1:2)
    # --- Table [] ---
    # Key functions: file
    datatab <- read.table(system.file("doc", "exp2_2waycfa.txt", package="CFAssay"),
                          header=TRUE, sep="\t")
    # --- cfa2way [] ---
    # Key functions: cfa2way
    fitcomp <- cfa2way(datatab, A="siRNA", B="x5fuCis", param="A/B")
    # --- Pdf [] ---
    # Key functions: plotExp, off
    ##   pdf("TwoWay_experimental_plots.pdf")
    ##     plotExp(fitcomp, labels=c(A="siRNA", B="x5fuCis"))
    ##   dev.off()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cfassay_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cfassay_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cfassay_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CFASSAY:", paste0("    cfassay: ", packageVersion("CFAssay"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cfassay_results.csv
    touch ${prefix}_cfassay_output.rds
    echo "BIOC_CFASSAY:" > versions.yml
    echo "    cfassay: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CFASSAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CFASSAY(ch_input)

    emit:
    results  = BIOC_CFASSAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CFASSAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CFASSAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CFASSAY.out.versions  // channel: path(versions.yml)
}
