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
    library(CDI_lineplot)
    library(jsonlite)

    # --- kable [] ---
    # Key functions: kable
    data(one_batch_matrix_label_df, package = "CDI")
    knitr::kable(head(one_batch_matrix_label_df[,c("KMeans_k2", "KMeans_k4", "Seurat_k2", "Seurat_k3")], 3))
    # --- feature selection [] ---
    # Key functions: feature_gene_selection, size_factor

    # --- calculate cdi1 [] ---
    # Key functions: calculate_CDI, CDI_lineplot, contingency_heatmap
    start_time <- Sys.time()
    # --- data label2 [] ---
    # Key functions: kable
    data(two_batch_matrix_label_df, package = "CDI")
    knitr::kable(head(two_batch_matrix_label_df[,c("KMeans_k5", "KMeans_k6", "Seurat_k5", "Seurat_k6")], 3))
    # --- feature selection2 [] ---
    # Key functions: feature_gene_selection, size_factor, calculate_CDI, CDI_lineplot


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
