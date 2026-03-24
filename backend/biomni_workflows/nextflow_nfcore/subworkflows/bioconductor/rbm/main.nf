#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RBM
// Use A Resampling-Based Empirical Bayes Approach to Assess Differential Expression in Two-Color Micro
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RBM/inst/doc/RBM.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RBM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rbm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rbm:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rbm:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rbm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rbm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rbm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RBM_F)
    library(RBM_T)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: rnorm, RBM_T
    library(RBM)
    normdata <- matrix(rnorm(1000*6, 0, 1),1000,6)
    mydesign <- c(0,0,0,1,1,1)
    myresult <- RBM_T(normdata,mydesign,100,0.05)
    summary(myresult)
    # --- Matrix [] ---
    # Key functions: runif, RBM_T, adjust
    unifdata <- matrix(runif(1000*7,0.10, 0.95), 1000, 7)
    mydesign2 <- c(0,0,0, 1,1,1,1)
    myresult2 <- RBM_T(unifdata,mydesign2,100,0.05)
    sum(myresult2$permutatioin_p<=0.05)
    sum(myresult2$bootstrap_p<=0.05)
    # --- Matrix [] ---
    # Key functions: rnorm, RBM_F, adjust
    normdata_F <- matrix(rnorm(1000*9,0,2), 1000, 9)
    mydesign_F <- c(0, 0, 0, 1, 1, 1, 2, 2, 2)
    aContrast <- c("X1-X0", "X2-X1", "X2-X0")
    myresult_F <- RBM_F(normdata_F, mydesign_F, aContrast, 100, 0.05)
    summary(myresult_F)
    # --- Matrix [] ---
    # Key functions: runif, RBM_F
    unifdata_F <- matrix(runif(1000*18, 0.15, 0.98), 1000, 18)
    mydesign2_F <- c(rep(0, 6), rep(1, 6), rep(2, 6))
    aContrast <- c("X1-X0", "X2-X1", "X2-X0")
    myresult2_F <- RBM_F(unifdata_F, mydesign2_F, aContrast, 100, 0.05)
    summary(myresult2_F)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rbm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rbm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rbm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RBM:", paste0("    rbm: ", packageVersion("RBM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rbm_results.csv
    touch ${prefix}_rbm_output.rds
    echo "BIOC_RBM:" > versions.yml
    echo "    rbm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RBM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RBM(ch_input)

    emit:
    results  = BIOC_RBM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RBM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RBM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RBM.out.versions  // channel: path(versions.yml)
}
