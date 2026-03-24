#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneticsPed
// Classes and methods for handling pedigree data. It also includes functions to calculate genetic rela
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneticsPed/inst/doc/quanGenAnimalModel.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GeneticsPed")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENETICSPED {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geneticsped"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geneticsped:1.68.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geneticsped:1.68.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geneticsped_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geneticsped_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geneticsped_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Pedigree)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: Pedigree
    library(GeneticsPed)
    data(Mrode3.1)
    (x <- Pedigree(x=Mrode3.1, subject="calf", ascendant=c("sire", "dam"),
                   ascendantSex=c("Male", "Female"), sex="sex"))
    # --- Lhs [] ---
    # Key functions: efficiently, crossprod
    LHS <- rbind(cbind(t(X) %*% X, t(X) %*% Z),
                 cbind(t(Z) %*% X, t(Z) %*% Z))
    ## or more efficiently
    (LHS <- rbind(cbind(crossprod(X),    crossprod(X, Z)),
                  cbind(crossprod(Z, X), crossprod(Z))))
    # --- Lhs2 [] ---
    # Key functions: extend, inverseAdditive, nIndividual, q
    ## We want Ainv for all individuals in the pedigree not only individuals
    ##   with records
    x <- extend(x)
    Ainv <- inverseAdditive(x=x)
    sigma2a <- 20
    # --- Rhs [] ---
    # Key functions: crossprod
    RHS <- rbind(t(X) %*% y,
                 t(Z) %*% y)
    ## or more efficiently
    RHS <- rbind(crossprod(X, y),
                 crossprod(Z, y))
    # --- Solve [] ---
    # Key functions: solve
    sol <- solve(LHS) %*% RHS
    ## or more efficiently
    sol <- solve(LHS, RHS)
    t(sol)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geneticsped_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geneticsped_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geneticsped_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENETICSPED:", paste0("    geneticsped: ", packageVersion("GeneticsPed"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geneticsped_results.csv
    touch ${prefix}_geneticsped_output.rds
    echo "BIOC_GENETICSPED:" > versions.yml
    echo "    geneticsped: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENETICSPED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENETICSPED(ch_input)

    emit:
    results  = BIOC_GENETICSPED.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENETICSPED.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENETICSPED.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENETICSPED.out.versions  // channel: path(versions.yml)
}
