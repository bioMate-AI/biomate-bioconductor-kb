#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: selectKSigs
// A package to suggest the number of mutational signatures in a collection of somatic mutations using 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/selectKSigs/inst/doc/selectKSigs.R
// Upstream  : HiLDA, dplyr, ggplot2, tidyr
// Downstream: none
//
// Install: BiocManager::install("selectKSigs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SELECTKSIGS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-selectksigs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-selectksigs:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-selectksigs:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_selectksigs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_selectksigs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_selectksigs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(selectKSigs)
    library(jsonlite)

    # --- Cross Validation for Signature Number [] ---
    # Key functions: cv_PMSignature
    inputFile <- system.file("extdata/esophageal.mp.txt.gz", package="HiLDA")
    G <- HiLDA::hildaReadMPFile(inputFile, numBases=5, trDir=TRUE)
    results <- cv_PMSignature(G, Kfold = 3, nRep = 2, Klimit = 5)


    # --- Model Selection and Evaluation [] ---
    # Key functions: cv_PMSignature
    load(system.file("extdata/sample.rdata", package = "selectKSigs"))
    results$Kvalue <- seq_len(nrow(results)) + 1
    min_val <- min(results$cv, na.rm = TRUE)
    best_k <- results$Kvalue[which.min(results$cv)]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_selectksigs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_selectksigs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_selectksigs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SELECTKSIGS:", paste0("    selectksigs: ", packageVersion("selectKSigs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_selectksigs_results.csv
    touch ${prefix}_selectksigs_output.rds
    echo "BIOC_SELECTKSIGS:" > versions.yml
    echo "    selectksigs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SELECTKSIGS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SELECTKSIGS(ch_input)

    emit:
    results  = BIOC_SELECTKSIGS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SELECTKSIGS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SELECTKSIGS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SELECTKSIGS.out.versions  // channel: path(versions.yml)
}
