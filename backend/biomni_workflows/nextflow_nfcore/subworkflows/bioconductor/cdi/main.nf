#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CDI
// Single-cell RNA-sequencing (scRNA-seq) is widely used to explore cellular variation. The analysis of
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CDI/inst/doc/CDI.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CDI")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CDI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cdi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cdi:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cdi:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cdi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cdi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cdi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CDI)
    library(CDI_lineplot)
    library(jsonlite)

    # --- CDI Calculation [] ---
    # Key functions: calculate_CDI
    data(one_batch_matrix_label_df, package = "CDI")
    data(one_batch_matrix_celltype, package = "CDI")
    CDI_return1 <- calculate_CDI(
        X = sub_one_batch_matrix,
        cand_lab_df = one_batch_matrix_label_df,
        batch_label = NULL,
        cell_size_factor = one_batch_matrix_size_factor
    )
    benchmark_return1 <- calculate_CDI(
        X = sub_one_batch_matrix,
        cand_lab_df = one_batch_matrix_celltype,
        batch_label = NULL,
        cell_size_factor = one_batch_matrix_size_factor
    )


    # --- Visualisation of CDI Curves [] ---
    # Key functions: CDI_lineplot
    CDI_lineplot(
        cdi_dataframe = CDI_return1,
        cdi_type = "CDI_BIC",
        benchmark_celltype_cdi = benchmark_return1,
        benchmark_celltype_ncluster = length(
            unique(one_batch_matrix_celltype)
        )
    )


    # --- Contingency Heatmap Analysis [] ---
    # Key functions: contingency_heatmap
    cand_names <- paste0(
        "cluster",
        seq_len(length(unique(one_batch_matrix_label_df$KMeans_k5)))
    )
    contingency_heatmap(
        benchmark_label = one_batch_matrix_celltype,
        candidate_label = one_batch_matrix_label_df$KMeans_k5,
        rename_candidate_clusters = TRUE,
        candidate_cluster_names = cand_names
    )


    # --- Multi-Batch Analysis [] ---
    # Key functions: feature_gene_selection, size_factor, calculate_CDI
    data(two_batch_matrix, package = "CDI")
    data(two_batch_matrix_batch, package = "CDI")
    f_idx <- feature_gene_selection(
        X = two_batch_matrix,
        batch_label = two_batch_matrix_batch,
        method = "wds",
        nfeature = 500
    )
    sf <- size_factor(two_batch_matrix)
    CDI_return2 <- calculate_CDI(
        X = two_batch_matrix[f_idx, ],
        cand_lab_df = two_batch_matrix_label_df,
        batch_label = two_batch_matrix_batch,
        cell_size_factor = sf
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cdi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cdi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cdi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CDI:", paste0("    cdi: ", packageVersion("CDI"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cdi_results.csv
    touch ${prefix}_cdi_output.rds
    echo "BIOC_CDI:" > versions.yml
    echo "    cdi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CDI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CDI(ch_input)

    emit:
    results  = BIOC_CDI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CDI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CDI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CDI.out.versions  // channel: path(versions.yml)
}
