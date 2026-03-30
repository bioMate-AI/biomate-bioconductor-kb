#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MEB
// This package provides a method to identify differential expression genes in the same or different sp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MEB/inst/doc/NIMEB.R
// Upstream  : SingleCellExperiment, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("MEB")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-meb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-meb:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-meb:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_meb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_meb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_meb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NIMEB)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(sim_data_sp)
    sim_data_sp
    # --- Data [] ---
    # Key functions: NIMEB, assay
    ---------------------------------------------------------------------
    data(sim_data_sp)
    gamma <- seq(1e-06,5e-05,1e-06)
    sim_model_sp <- NIMEB(countsTable=assay(sim_data_sp), train_id=1:1000, gamma,
    nu = 0.01, reject_rate = 0.05, ds = FALSE)
    # --- Predict [] ---
    # Key functions: predict, assay
    ---------------------------------------------------------------------
    sim_model_sp_pred <- predict(sim_model_sp$model, assay(sim_data_sp))
    summary(sim_model_sp_pred)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(sim_scRNA_data)
    sim_scRNA_data
    # --- Scmeb [] ---
    # Key functions: scMEB
    ---------------------------------------------------------------------
    sim_scRNA <- scMEB(sce=sim_scRNA_data, stable_idx=stable_gene,
    filtered = TRUE, gamma = seq(1e-04,0.001,1e-05), nu = 0.01,
    reject_rate = 0.1)
    # --- Predict [] ---
    # Key functions: predict
    ---------------------------------------------------------------------
    sim_scRNA_pred <- predict(sim_scRNA$model, sim_scRNA$dat_pca)
    summary(sim_scRNA_pred)
    # --- Frame [] ---
    # Key functions: frame
    ---------------------------------------------------------------------
    sim_scRNA_dist <- data.frame(Gene=rownames(sim_scRNA_data),
                                 Distance=sim_scRNA$dist)
    head(sim_scRNA_dist)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_meb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_meb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_meb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MEB:", paste0("    meb: ", packageVersion("MEB"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meb_results.csv
    touch ${prefix}_meb_output.rds
    echo "BIOC_MEB:" > versions.yml
    echo "    meb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MEB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MEB(ch_input)

    emit:
    results  = BIOC_MEB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MEB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MEB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MEB.out.versions  // channel: path(versions.yml)
}
