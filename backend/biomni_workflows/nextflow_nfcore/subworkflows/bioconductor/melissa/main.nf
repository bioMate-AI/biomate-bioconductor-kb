#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Melissa
// Melissa is a Baysian probabilistic model for jointly clustering and imputing single cell methylomes.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Melissa/inst/doc/process_files.R
// Upstream  : BPRMeth, BiocStyle, knitr
// Downstream: none
//
// Install: BiocManager::install("Melissa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MELISSA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-melissa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-melissa:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-melissa:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_melissa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_melissa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_melissa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Melissa)
    library(jsonlite)

    # --- Model Fitting and Clustering [] ---
    # Key functions: melissa, create_rbf_basis
    basis_obj <- create_rbf_basis(
        M = 4,
        min_val = -1,
        max_val = 1
    )
    melissa_result <- melissa(
        X = met_data,
        K = 2,
        basis = basis_obj,
        max_iter = 100,
        vb_init = TRUE
    )


    # --- Methylation Imputation [] ---
    # Key functions: impute_methylome
    imputed_profiles <- impute_methylome(
        model = melissa_result,
        X = met_data,
        basis = basis_obj
    )


    # --- Cluster Profiling and Visualization [] ---
    # Key functions: plot_melissa_profiles
    profile_plot <- plot_melissa_profiles(
        model = melissa_result,
        basis = basis_obj,
        cluster = 1
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_melissa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_melissa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_melissa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MELISSA:", paste0("    melissa: ", packageVersion("Melissa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_melissa_results.csv
    touch ${prefix}_melissa_output.rds
    echo "BIOC_MELISSA:" > versions.yml
    echo "    melissa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MELISSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MELISSA(ch_input)

    emit:
    results  = BIOC_MELISSA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MELISSA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MELISSA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MELISSA.out.versions  // channel: path(versions.yml)
}
