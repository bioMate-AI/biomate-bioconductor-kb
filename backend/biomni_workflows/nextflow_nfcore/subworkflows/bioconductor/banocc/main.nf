#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: banocc
// BAnOCC is a package designed for compositional data, where each sample sums to one. It infers the ap
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/banocc/inst/doc/banocc-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("banocc")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BANOCC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-banocc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-banocc:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-banocc:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_banocc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_banocc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_banocc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(banocc)
    library(jsonlite)

    # --- Fitting with Custom Hyperparameters [] ---
    # Key functions: run_banocc
    data(compositions_null)
    p <- ncol(compositions_null)
    compiled_banocc_model <- rstan::stan_model(
        model_code = banocc::banocc_model
    )
    b_fit_hp <- banocc::run_banocc(
        C = compositions_null,
        compiled_banocc_model = compiled_banocc_model,
        n = rep(0, p),
        L = 10 * diag(p),
        a = 0.5,
        b = 0.01
    )


    # --- Advanced MCMC Sampling Configuration [] ---
    # Key functions: run_banocc
    data(compositions_null)
    p <- ncol(compositions_null)
    compiled_banocc_model <- rstan::stan_model(
        model_code = banocc::banocc_model
    )
    init_list <- list(
        list(m = rep(0, p), O = diag(p), lambda = 0.02),
        list(m = rep(0.1, p), O = 10 * diag(p), lambda = 0.5)
    )
    b_fit_init <- banocc::run_banocc(
        C = compositions_null,
        compiled_banocc_model = compiled_banocc_model,
        chains = 2,
        init = init_list
    )


    # --- Posterior Inference and Credible Intervals [] ---
    # Key functions: get_banocc_output
    b_out_90 <- banocc::get_banocc_output(
        banoccfit = b_fit,
        conf_alpha = 0.1
    )
    b_out_99 <- banocc::get_banocc_output(
        banoccfit = b_fit,
        conf_alpha = 0.01
    )
    b_out_snc <- banocc::get_banocc_output(
        banoccfit = b_fit,
        calc_snc = TRUE,
        get_min_width = TRUE
    )


    # --- Convergence Evaluation [] ---
    # Key functions: get_banocc_output
    b_out_ec <- banocc::get_banocc_output(
        banoccfit = b_fit,
        eval_convergence = TRUE
    )
    b_out_nec <- banocc::get_banocc_output(
        banoccfit = b_fit,
        eval_convergence = FALSE
    )
    estimates_median <- b_out_nec$Estimates.median

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_banocc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_banocc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_banocc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BANOCC:", paste0("    banocc: ", packageVersion("banocc"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_banocc_results.csv
    touch ${prefix}_banocc_output.rds
    echo "BIOC_BANOCC:" > versions.yml
    echo "    banocc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BANOCC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BANOCC(ch_input)

    emit:
    results  = BIOC_BANOCC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BANOCC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BANOCC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BANOCC.out.versions  // channel: path(versions.yml)
}
