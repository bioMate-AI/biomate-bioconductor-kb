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

    # --- Basis Function Definition [Basis Object Creation] ---
    # Key functions: create_rbf_object
    met_region <- encode_met
    met_data <- met_region$met
    anno_data <- met_region$anno
    basis_profile <- create_rbf_object(M = 5)
    basis_mean <- create_rbf_object(M = 0)
    basis_cluster <- create_rbf_object(M = 3)

    # --- Methylation Profile Inference [Profile Inference] ---
    # Key functions: infer_profiles_vb
    met_region <- encode_met
    fit_profiles <- infer_profiles_vb(
        X = met_region$met, model = "binomial",
        basis = basis_profile, is_parallel = FALSE
    )
    fit_mean <- infer_profiles_vb(
        X = met_region$met, model = "binomial",
        basis = basis_mean, is_parallel = FALSE
    )

    # --- Profile Visualisation [Visualisation] ---
    # Key functions: plot_infer_profiles
    met_region <- encode_met
    gene_id <- met_region$anno$id[21]
    p_profile <- plot_infer_profiles(
        region = 21, obj_prof = fit_profiles,
        obj_mean = fit_mean, obs = met_region$met,
        title = paste0("Gene ID ", gene_id)
    )

    # --- Gene Expression Prediction [Expression Prediction] ---
    # Key functions: predict_expr, plot_predicted_expr
    expr <- encode_expr
    met_region <- encode_met
    pred_profile <- predict_expr(
        prof_obj = fit_profiles, expr = expr,
        anno = met_region$anno, model_name = "svm",
        fit_feature = "RMSE", cov_feature = TRUE,
        is_summary = FALSE
    )
    g1 <- plot_predicted_expr(
        pred_obj = pred_profile,
        title = "Methylation profile"
    )

    # --- Methylation Profile Clustering [Clustering] ---
    # Key functions: cluster_profiles_vb, plot_cluster_profiles
    met_region <- encode_met
    basis_obj <- create_rbf_object(M = 3)
    cl_obj <- cluster_profiles_vb(
        X = met_region$met, K = 4, model = "binomial",
        alpha_0 = 0.5, beta_0 = 0.1,
        basis = basis_obj, vb_max_iter = 20
    )
    cluster_plot <- plot_cluster_profiles(cluster_obj = cl_obj)


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
