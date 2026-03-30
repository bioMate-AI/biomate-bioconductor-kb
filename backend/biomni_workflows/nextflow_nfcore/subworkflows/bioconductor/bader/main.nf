#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BADER
// For RNA sequencing count data, BADER fits a Bayesian hierarchical model. The algorithm returns the p
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BADER/inst/doc/BADER.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BADER")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BADER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bader"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bader:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bader:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bader_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bader_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bader_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BADER)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: file
    library(BADER)
    datafile <- system.file( "extdata/pasilla_gene_counts.tsv", package="pasilla" )
    pasillaCountTable <- read.table( datafile, header=TRUE, row.names=1 )
    head(pasillaCountTable)
    # --- Splitup [] ---
    # Key functions: rowSums, factor
    genetable <- pasillaCountTable[,c(3,4,6,7)]
    genetable <- genetable[rowSums(genetable) > 0,]
    genetable <- genetable[1:500,]
    design <- factor(c("A","A","B","B"))
    # --- Runmcmc [] ---
    # Key functions: BADER
    set.seed(21)
    results <- BADER(genetable,design,burn=1e3,reps=1e3,printEvery=1e3)
    # --- Toydataset [] ---
    # Key functions: rnorm, rnbinom
    set.seed(21)
    gam <- c(rnorm(50,0,2),rep(0,450))
    muA <- rnorm(500,3,1)
    muB <- muA + gam
    kA <- t(matrix(rnbinom(2*500,mu=exp(muA),size=exp(1)),nrow=2,byrow=TRUE))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bader_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bader_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bader_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BADER:", paste0("    bader: ", packageVersion("BADER"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bader_results.csv
    touch ${prefix}_bader_output.rds
    echo "BIOC_BADER:" > versions.yml
    echo "    bader: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BADER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BADER(ch_input)

    emit:
    results  = BIOC_BADER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BADER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BADER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BADER.out.versions  // channel: path(versions.yml)
}
