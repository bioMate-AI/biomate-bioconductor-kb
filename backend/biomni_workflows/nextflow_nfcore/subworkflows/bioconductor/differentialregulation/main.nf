#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DifferentialRegulation
// DifferentialRegulation is a method for detecting differentially regulated genes between two groups o
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DifferentialRegulation/inst/doc/DifferentialRegulation.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DifferentialRegulation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIFFERENTIALREGULATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-differentialregulation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-differentialregulation:2.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-differentialregulation:2.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_differentialregulation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_differentialregulation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_differentialregulation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DifferentialRegulation)
    library(jsonlite)

    # --- Pseudo-bulk Count Computation [] ---
    # Key functions: compute_PB_counts
    design = data.frame(sample = sample_ids,
                        group = c(rep("3 mon", 3), rep("6 mon", 3)))
    sce$cell_type = rep("neuron", ncol(sce))
    PB_counts = compute_PB_counts(sce = sce,
                                  EC_list = EC_list,
                                  design = design,
                                  sample_col_name = "sample",
                                  group_col_name = "group",
                                  sce_cluster_name = "cell_type")


    # --- Differential Regulation Analysis [] ---
    # Key functions: DifferentialRegulation
    results = DifferentialRegulation(PB_counts,
                                     n_cores = 2,
                                     traceplot = TRUE)


    # --- Visualisation [] ---
    # Key functions: plot_pi, plot_traceplot
    gene_id = results$Differential_results$Gene_id[1]
    cluster_id = results$Differential_results$Cluster_id[1]
    plot_pi(results, type = "US", gene_id = gene_id, cluster_id = cluster_id)
    plot_pi(results, type = "USA", gene_id = gene_id, cluster_id = cluster_id)
    plot_traceplot(results, gene_id = gene_id, cluster_id = cluster_id)


    # --- Bulk Data Analysis [] ---
    # Key functions: load_bulk_US, load_bulk_EC, DifferentialRegulation_bulk
    sample_ids_bulk = paste0("sample", seq_len(6))
    quant_files = file.path(data_dir, "salmon", sample_ids_bulk, "quant.sf")
    equiv_classes_files = file.path(data_dir, "salmon", sample_ids_bulk,
                                    "aux_info/eq_classes.txt.gz")
    SE = load_bulk_US(quant_files, sample_ids_bulk)
    EC_list_bulk = load_bulk_EC(path_to_eq_classes = equiv_classes_files,
                                 n_cores = 2)
    design_bulk = data.frame(sample = sample_ids_bulk,
                             group = rep(c("A", "B"), each = 3))
    results_bulk = DifferentialRegulation_bulk(SE = SE,
                                                EC_list = EC_list_bulk,
                                                design = design_bulk,
                                                n_cores = 2,
                                                traceplot = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_differentialregulation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_differentialregulation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_differentialregulation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIFFERENTIALREGULATION:", paste0("    differentialregulation: ", packageVersion("DifferentialRegulation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differentialregulation_results.csv
    touch ${prefix}_differentialregulation_output.rds
    echo "BIOC_DIFFERENTIALREGULATION:" > versions.yml
    echo "    differentialregulation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIFFERENTIALREGULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIFFERENTIALREGULATION(ch_input)

    emit:
    results  = BIOC_DIFFERENTIALREGULATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIFFERENTIALREGULATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIFFERENTIALREGULATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIFFERENTIALREGULATION.out.versions  // channel: path(versions.yml)
}
