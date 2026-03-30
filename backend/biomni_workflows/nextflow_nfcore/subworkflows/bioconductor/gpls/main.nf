#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gpls
// Classification using generalized partial least squares for two-group and multi-group (more than 2 gr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gpls/inst/doc/gpls.R
// Upstream  : MASS
// Downstream: none
//
// Install: BiocManager::install("gpls")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GPLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gpls"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gpls:1.78.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gpls:1.78.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gpls_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gpls_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gpls_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gpls)
    library(jsonlite)

    # --- Matrix [] ---
    # Key functions: rnorm, sample, error
    ## training set
    x <- matrix(rnorm(20),ncol=2)
    y <- sample(0:1,10,TRUE)
    ## test set
    x1 <- matrix(rnorm(10),ncol=2)
    # --- Matrix [] ---
    # Key functions: rnorm, sample, mlogit, all
    x <- matrix(rnorm(20),ncol=2)
    y <- sample(1:3,10,TRUE)
    ## no bias reduction and 1 PLS component
    glpls1a.mlogit(cbind(rep(1,10),x),y,K.prov=1,br=FALSE)
    glpls1a.logit.all(x,y,K.prov=1,br=FALSE)
    # --- Matrix [] ---
    # Key functions: rnorm, sample, error
    x <- matrix(rnorm(20),ncol=2)
    y <- sample(1:3,10,TRUE)
    ## no bias reduction
    glpls1a.mlogit.cv.error(x,y,br=FALSE)
    glpls1a.mlogit.cv.error(x,y,mlogit=FALSE,br=FALSE)
    # --- Pimaex [] ---
    # Key functions: gpls, predict, frame
    library(MASS)
     m1 = gpls(type~., Pima.tr)
     p1 = predict(m1, Pima.te[,-8])
    ##when we get to the multi-response problems
         data(iris3)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gpls_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gpls_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gpls_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GPLS:", paste0("    gpls: ", packageVersion("gpls"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gpls_results.csv
    touch ${prefix}_gpls_output.rds
    echo "BIOC_GPLS:" > versions.yml
    echo "    gpls: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GPLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GPLS(ch_input)

    emit:
    results  = BIOC_GPLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GPLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GPLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GPLS.out.versions  // channel: path(versions.yml)
}
