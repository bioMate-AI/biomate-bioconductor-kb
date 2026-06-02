#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: distinct
// distinct is a statistical method to perform differential testing between two or more groups of distr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/distinct/inst/doc/distinct.R
// Upstream  : SingleCellExperiment, UpSetR, scater
// Downstream: none
//
// Install: BiocManager::install("distinct")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DISTINCT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-distinct"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-distinct:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-distinct:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_distinct_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_distinct_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_distinct_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(distinct)
    library(jsonlite)

    # --- Differential Distribution Testing [Testing] ---
    # Key functions: distinct_test
    samples = Kang_subset@metadata$experiment_info$sample_id
    group = Kang_subset@metadata$experiment_info$stim
    design = model.matrix(~group)
    rownames(design) = samples
    res = distinct_test(
        x = Kang_subset, 
        name_assays_expression = "logcounts",
        name_cluster = "cell",
        name_sample = "sample_id",
        design = design,
        column_to_test = 2,
        min_non_zero_cells = 20,
        n_cores = 2
    )

    # --- Differential Testing with Batch Correction [Testing] ---
    # Key functions: distinct_test
    samples = Kang_subset@metadata$experiment_info$sample_id
    group = Kang_subset@metadata$experiment_info$stim
    batch = factor(c("A", "B", "C", "A", "B", "C"))
    design_batch = model.matrix(~group + batch)
    rownames(design_batch) = samples
    res_batches = distinct_test(
        x = Kang_subset, 
        name_assays_expression = "logcounts",
        name_cluster = "cell",
        name_sample = "sample_id",
        design = design_batch,
        column_to_test = 2,
        min_non_zero_cells = 20,
        n_cores = 2
    )

    # --- Fold Change Estimation [Analysis] ---
    # Key functions: log2_FC
    res_fc = log2_FC(
        res = res,
        x = Kang_subset, 
        name_assays_expression = "cpm",
        name_group = "stim",
        name_cluster = "cell"
    )

    # --- Results Filtering and Selection [Filtering] ---
    # Key functions: top_results
    top_all = top_results(res_fc)
    top_dendritic = top_results(
        res_fc, 
        cluster = "Dendritic cells", 
        sort_by = "log2FC"
    )
    top_down = top_results(
        res_fc, 
        up_down = "down",
        cluster = "Dendritic cells"
    )

    # --- Density and CDF Visualization [Visualisation] ---
    # Key functions: plot_densities, plot_cdfs
    dens_plot = plot_densities(
        x = Kang_subset,
        gene = "ISG15",
        cluster = "Dendritic cells",
        name_assays_expression = "logcounts",
        name_cluster = "cell",
        name_sample = "sample_id",
        name_group = "stim"
    )
    cdf_plot = plot_cdfs(
        x = Kang_subset,
        gene = "ISG15",
        cluster = "Dendritic cells",
        name_assays_expression = "logcounts",
        name_cluster = "cell",
        name_sample = "sample_id",
        name_group = "stim"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_distinct_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_distinct_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_distinct_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DISTINCT:", paste0("    distinct: ", packageVersion("distinct"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_distinct_results.csv
    touch ${prefix}_distinct_output.rds
    echo "BIOC_DISTINCT:" > versions.yml
    echo "    distinct: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DISTINCT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DISTINCT(ch_input)

    emit:
    results  = BIOC_DISTINCT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DISTINCT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DISTINCT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DISTINCT.out.versions  // channel: path(versions.yml)
}
