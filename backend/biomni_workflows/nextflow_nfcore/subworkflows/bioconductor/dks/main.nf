#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dks
// The dks package consists of a set of diagnostic functions for multiple testing methods. The function
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dks/inst/doc/dks.R
// Upstream  : cubature
// Downstream: none
//
// Install: BiocManager::install("dks")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DKS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dks"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dks:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dks:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dks_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dks_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dks_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(dks)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(dks)
    library(cubature)
    data(dksdata)
    dim(P)
    # --- Dks1 [] ---
    # Key functions: dks
    dks1 <- dks(P,plot=TRUE)
    # --- Pprob [] ---
    # Key functions: dist, image
    ## Calculate the posterior distribution
     delta <- 0.1
      dist1 <- pprob.dist(P[,1])
      ## Plot the posterior distribution
      alpha <- seq(0.1,10,by=delta)
    # --- Credset [] ---
    # Key functions: set, image
    ## Calculate a 80% credible set
      cred1 <- cred.set(dist1,delta=0.1, level=0.80)
      ## Plot the posterior and the credible set
      alpha <- seq(0.1,10,by=delta)
      beta <- seq(0.1,10,by=delta)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dks_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dks_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dks_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DKS:", paste0("    dks: ", packageVersion("dks"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dks_results.csv
    touch ${prefix}_dks_output.rds
    echo "BIOC_DKS:" > versions.yml
    echo "    dks: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DKS(ch_input)

    emit:
    results  = BIOC_DKS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DKS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DKS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DKS.out.versions  // channel: path(versions.yml)
}
