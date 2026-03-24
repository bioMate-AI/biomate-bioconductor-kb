#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DirichletMultinomial
// Dirichlet-multinomial mixture models can be used to describe variability in microbial metagenomic da
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DirichletMultinomial/inst/doc/DirichletMultinomial.R
// Upstream  : lattice, parallel
// Downstream: none
//
// Install: BiocManager::install("DirichletMultinomial")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIRICHLETMULTINOMIAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dirichletmultinomial"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dirichletmultinomial:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dirichletmultinomial:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dirichletmultinomial_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dirichletmultinomial_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dirichletmultinomial_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DirichletMultinomial)
    library(jsonlite)

    # --- Filter by row sum threshold [] ---
    # Key functions: rowSums, datatable
    diff <- rowSums(abs(p4 - as.vector(p0)))
    o <- order(diff, decreasing=TRUE)
    cdiff <- cumsum(diff[o]) / sum(diff)
    # --- Densityplot analysis [] ---
    # Key functions: densityplot, mclapply, mixturewt, splom, fitted, heatmapdmn, dmngroup, xtabs
    bst <- roc(pheno[rownames(count)] == "Obese",
    predict(bestgrp, count)[,"Obese"])
    two <- roc(pheno[rownames(xval)] == "Obese", xval[,"Obese"])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dirichletmultinomial_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dirichletmultinomial_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dirichletmultinomial_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIRICHLETMULTINOMIAL:", paste0("    dirichletmultinomial: ", packageVersion("DirichletMultinomial"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dirichletmultinomial_results.csv
    touch ${prefix}_dirichletmultinomial_output.rds
    echo "BIOC_DIRICHLETMULTINOMIAL:" > versions.yml
    echo "    dirichletmultinomial: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIRICHLETMULTINOMIAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIRICHLETMULTINOMIAL(ch_input)

    emit:
    results  = BIOC_DIRICHLETMULTINOMIAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIRICHLETMULTINOMIAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIRICHLETMULTINOMIAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIRICHLETMULTINOMIAL.out.versions  // channel: path(versions.yml)
}
