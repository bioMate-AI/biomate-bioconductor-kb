#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scMET
// High-throughput single-cell measurements of DNA methylomes can quantify methylation heterogeneity an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scMET/inst/doc/scMET_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("scMET")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCMET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scmet"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scmet:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scmet:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scmet_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scmet_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scmet_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scMET)
    library(jsonlite)

    # --- Maximum Likelihood Estimation [] ---
    # Key functions: bb_mle
    bbmle_fit <- scmet_dt$Y[, bb_mle(cbind(total_reads, met_reads)),
                            by = c("Feature")]
    bbmle_fit <- bbmle_fit[, c("Feature", "mu", "gamma")]


    # --- Highly Variable Features Analysis [] ---
    # Key functions: scmet_hvf
    fit_obj <- scmet_hvf(
        scmet_obj = fit_obj,
        delta_e = 0.75,
        evidence_thresh = 0.8,
        efdr = 0.1
    )
    hvf_summary <- fit_obj$hvf$summary


    # --- Differential Analysis [] ---
    # Key functions: scmet, scmet_differential
    fit_A <- scmet(
        Y = scmet_diff_dt$scmet_dt_A$Y,
        X = scmet_diff_dt$scmet_dt_A$X,
        L = 4,
        iter = 300,
        seed = 12
    )
    fit_B <- scmet(
        Y = scmet_diff_dt$scmet_dt_B$Y,
        X = scmet_diff_dt$scmet_dt_B$X,
        L = 4,
        iter = 300,
        seed = 12
    )
    diff_obj <- scmet_differential(
        obj_A = fit_A,
        obj_B = fit_B,
        evidence_thresh_m = 0.65,
        evidence_thresh_e = 0.65,
        group_label_A = "A",
        group_label_B = "B"
    )


    # --- Visualisation [] ---
    # Key functions: scmet_plot_mean_var, scmet_plot_estimated_vs_true, scmet_plot_efdr_efnr_grid, scmet_plot_vf_tail_prob
    gg_mean_var <- scmet_plot_mean_var(
        obj = fit_obj,
        y = "gamma",
        task = "hvf",
        show_fit = TRUE
    )
    gg_est_vs_true <- scmet_plot_estimated_vs_true(
        obj = fit_obj,
        sim_dt = scmet_dt,
        param = "gamma",
        mle_fit = bbmle_fit
    )
    gg_grid <- scmet_plot_efdr_efnr_grid(
        obj = fit_obj,
        task = "hvf"
    )
    gg_tail <- scmet_plot_vf_tail_prob(
        obj = fit_obj,
        x = "mu",
        task = "hvf"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scmet_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scmet_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scmet_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCMET:", paste0("    scmet: ", packageVersion("scMET"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmet_results.csv
    touch ${prefix}_scmet_output.rds
    echo "BIOC_SCMET:" > versions.yml
    echo "    scmet: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCMET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCMET(ch_input)

    emit:
    results  = BIOC_SCMET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCMET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCMET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCMET.out.versions  // channel: path(versions.yml)
}
