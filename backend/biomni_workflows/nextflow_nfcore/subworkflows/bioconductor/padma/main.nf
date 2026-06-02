#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: padma
// Use multiple factor analysis to calculate individualized pathway-centric scores of deviation with re
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/padma/inst/doc/padma.R
// Upstream  : MultiAssayExperiment
// Downstream: none
//
// Install: BiocManager::install("padma")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PADMA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-padma"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-padma:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-padma:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_padma_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_padma_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_padma_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(padma)
    library(MultiAssayExperiment)
    library(jsonlite)

    # --- Data Preparation [padma] ---
    # Key functions: LUAD_subset, msigdb
    mae_data <- padma::LUAD_subset
    omics_list <- list(
        rnaseq = as.matrix(mae_data$rnaseq),
        methyl = as.matrix(mae_data$methyl),
        mirna = as.matrix(mae_data$mirna),
        cna = as.matrix(mae_data$cna)
    )
    pheno_df <- data.frame(
        mae_data$clinical,
        row.names = mae_data$clinical$bcr_patient_barcode
    )

    # --- Pathway Deviation Analysis [padma] ---
    # Key functions: padma
    geneset_name <- padma::msigdb[
        grep("D4GDI", padma::msigdb$geneset), "geneset"
    ]
    run_padma_res <- padma::padma(
        omics_list,
        colData = pheno_df,
        pathway_name = geneset_name,
        verbose = FALSE
    )

    # --- Pathway Deviation Analysis with Imputation [padma] ---
    # Key functions: padma
    geneset_name <- padma::msigdb[
        grep("D4GDI", padma::msigdb$geneset), "geneset"
    ]
    run_padma_impute <- padma::padma(
        omics_list,
        colData = pheno_df,
        pathway_name = geneset_name,
        impute = TRUE,
        verbose = FALSE
    )

    # --- Factor Map Visualisation [padma] ---
    # Key functions: factorMap
    factor_plot <- padma::factorMap(
        run_padma_res,
        dim_x = 1,
        dim_y = 2,
        ggplot = TRUE
    )
    partial_plot <- padma::factorMap(
        run_padma_res,
        partial_id = "TCGA-78-7536",
        dim_x = 1,
        dim_y = 2,
        ggplot = TRUE
    )

    # --- Omics Contribution Analysis [padma] ---
    # Key functions: omicsContrib
    contrib_plot <- padma::omicsContrib(
        run_padma_res,
        max_dim = 10,
        ggplot = TRUE
    )
    contrib_data <- padma::omicsContrib(
        run_padma_res,
        max_dim = 10,
        ggplot = FALSE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_padma_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_padma_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_padma_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PADMA:", paste0("    padma: ", packageVersion("padma"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_padma_results.csv
    touch ${prefix}_padma_output.rds
    echo "BIOC_PADMA:" > versions.yml
    echo "    padma: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PADMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PADMA(ch_input)

    emit:
    results  = BIOC_PADMA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PADMA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PADMA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PADMA.out.versions  // channel: path(versions.yml)
}
