#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: microbiomeDASim
// A toolkit for simulating differential microbiome data designed for longitudinal analyses. Several fu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/microbiomeDASim/inst/doc/microbiomeDASim.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("microbiomeDASim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MICROBIOMEDASIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-microbiomedasim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-microbiomedasim:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-microbiomedasim:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_microbiomedasim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_microbiomedasim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_microbiomedasim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(microbiomeDASim)
    library(jsonlite)

    # --- mvrnorm_sim [] ---
    # Key functions: mvrnorm_sim
    require(microbiomeDASim)
    triv_ex <- mvrnorm_sim(n_control=10, n_treat=10, control_mean=2,
    sigma=1, num_timepoints=2, t_interval=c(1, 2), rho=0.8,
    # --- mean_trend [] ---
    # Key functions: mean_trend, mvrnorm_sim
    true_mean <- mean_trend(timepoints=1:10, form="L_up", beta=0.5, IP=5,
    hockey_sim <- mvrnorm_sim(n_control=10, n_treat=10, control_mean=2, sigma=1,
    num_timepoints=10, t_interval=c(0, 9), rho=0.8,
    # --- gen_norm_microbiome [] ---
    # Key functions: gen_norm_microbiome
    bug_gen <- gen_norm_microbiome(features=6, diff_abun_features=3, n_control=30,
    num_timepoints=4, t_interval=c(0, 3),
    func_form="M", beta=c(4, 3), IP=c(2, 3.3, 6),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_microbiomedasim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_microbiomedasim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_microbiomedasim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MICROBIOMEDASIM:", paste0("    microbiomedasim: ", packageVersion("microbiomeDASim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microbiomedasim_results.csv
    touch ${prefix}_microbiomedasim_output.rds
    echo "BIOC_MICROBIOMEDASIM:" > versions.yml
    echo "    microbiomedasim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MICROBIOMEDASIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MICROBIOMEDASIM(ch_input)

    emit:
    results  = BIOC_MICROBIOMEDASIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MICROBIOMEDASIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MICROBIOMEDASIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MICROBIOMEDASIM.out.versions  // channel: path(versions.yml)
}
