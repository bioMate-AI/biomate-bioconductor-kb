#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BPRMeth
// The BPRMeth package is a probabilistic method to quantify explicit features of methylation profiles,
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BPRMeth/inst/doc/BPRMeth_vignette.R
// Upstream  : none
// Downstream: Melissa
//
// Install: BiocManager::install("BPRMeth")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BPRMETH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bprmeth"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bprmeth:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bprmeth:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_bprmeth_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bprmeth_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bprmeth_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BPRMeth)
    library(jsonlite)

    # --- read met dt pipeline [] ---
    # Key functions: read_met, read_anno, create_region_object
    met_dt <- read_met(file = "met_file", type = "bulk_seq")
    anno_dt <- read_anno(file = "anno_file")
    met_region <- create_region_object(met_dt = met_dt, anno_dt = anno_dt)
    # --- create_rbf_object [] ---
    # Key functions: create_rbf_object
    basis_profile <- create_rbf_object(M = 5)
    basis_mean <- create_rbf_object(M = 0)
    # --- infer_profiles_vb [] ---
    # Key functions: infer_profiles_vb
    fit_profiles <- infer_profiles_vb(X = met_region$met, model = "binomial",
    fit_mean <- infer_profiles_vb(X = met_region$met, model = "binomial",
    # --- plot_infer_profiles [] ---
    # Key functions: plot_infer_profiles
    p <- plot_infer_profiles(region = 21, obj_prof = fit_profiles,
    title = paste0("Gene ID ", gene_id))
    print(p)
    # --- predict_expr [] ---
    # Key functions: predict_expr
    set.seed(22)
    pred_profile <- predict_expr(prof_obj = fit_profiles, expr = expr,
    pred_mean <- predict_expr(prof_obj = fit_mean, expr = expr,
    # --- plot_predicted_expr [] ---
    # Key functions: plot_predicted_expr, plot_grid
    g1 <- plot_predicted_expr(pred_obj = pred_profile,
    g2 <- plot_predicted_expr(pred_obj = pred_mean,
    g <- cowplot::plot_grid(g1, g2, ncol = 2, nrow = 1)
    # --- create_rbf_object [] ---
    # Key functions: create_rbf_object, cluster_profiles_vb
    set.seed(12)
    basis_obj <- create_rbf_object(M = 3)
    cl_obj <- cluster_profiles_vb(X = met_region$met, K = K, model = "binomial",
    # --- plot_cluster_profiles [] ---
    # Key functions: plot_cluster_profiles
    cluster_plot <- plot_cluster_profiles(cluster_obj = cl_obj)
    print(cluster_plot)
    # --- infer profiles beta [] ---
    # Key functions: create_rbf_object, infer_profiles_mle, plot_infer_profiles
    basis_obj <- create_rbf_object(M = 5)
    beta_prof <- infer_profiles_mle(X = beta_data, model = "beta",
    p <- plot_infer_profiles(region = 15, obj_prof = beta_prof,
    # --- infer profiles bernoulli [] ---
    # Key functions: create_rbf_object, infer_profiles_vb, plot_infer_profiles
    basis_prof <- create_rbf_object(M = 5)
    basis_mean <- create_rbf_object(M = 0)
    bern_prof <- infer_profiles_vb(X = bernoulli_data, model = "bernoulli",
    # --- cluster bernoulli [] ---
    # Key functions: cluster_profiles_vb, plot_cluster_profiles
    cl_obj <- cluster_profiles_vb(X = bernoulli_data, K = 3, model = "bernoulli",
    cluster_plot <- plot_cluster_profiles(cluster_obj = cl_obj)
    print(cluster_plot)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bprmeth_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bprmeth_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bprmeth_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BPRMETH:", paste0("    bprmeth: ", packageVersion("BPRMeth"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bprmeth_results.csv
    touch ${prefix}_bprmeth_output.rds
    echo "BIOC_BPRMETH:" > versions.yml
    echo "    bprmeth: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BPRMETH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BPRMETH(ch_input)

    emit:
    results  = BIOC_BPRMETH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BPRMETH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BPRMETH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BPRMETH.out.versions  // channel: path(versions.yml)
}
