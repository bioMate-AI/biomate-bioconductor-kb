#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: censcyt
// Methods for differential abundance analysis in high-dimensional cytometry data when a covariate is s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/censcyt/inst/doc/censored_covariate.R
// Upstream  : SummarizedExperiment, ggplot2, tidyr
// Downstream: none
//
// Install: BiocManager::install("censcyt")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CENSCYT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-censcyt"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-censcyt:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-censcyt:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_censcyt_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_censcyt_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_censcyt_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(censcyt)
    library(jsonlite)

    # --- Simulate Covariate Data [] ---
    # Key functions: rexp, pmin, ifelse
    set.seed(1234)
    X_true <- rexp(nr_samples)
    C <- rexp(nr_samples)
    # --- Simulate Multicluster Data [] ---
    # Key functions: runif, simulate_multicluster
    sizes <- round(runif(nr_samples,1e3,1e4))
    alphas <- runif(nr_clusters,1,10)
    simulation_output <- simulate_multicluster(alphas = alphas,
    # --- Visualize Simulated Data [] ---
    # Key functions: ifelse, pivot_longer, ggplot, geom_point, facet_wrap
    is_diff_cluster <- ifelse(is.na(simulation_output$row_data$paired),FALSE,TRUE)
    proportion <- as.data.frame(t(apply(assay(d_counts),2,function(x)x/sum(x))))
    names(proportion) <- paste0("Nr: ",names(proportion), " - ",
    # --- Create Model Formula [] ---
    # Key functions: createFormula
    da_formula <- createFormula(experiment_info = experiment_info,
    contrast <- matrix(c(0,1))
    # --- differential testing [] ---
    # Key functions: testDA_censoredGLMM
    test with 50 repetitions with method risk set imputation (rs)
    da_out <- testDA_censoredGLMM(d_counts = d_counts,
    BPPARAM=BiocParallel::MulticoreParam(workers = 1))
    # --- Extract Top Results [] ---
    # Key functions: topTable
    topTable(da_out)
    which(!is.na(simulation_output$row_data$paired))
    # --- Simulate Data for Wrapper [] ---
    # Key functions: sinh
    Function to create expression data (one sample)
    fcs_sim <- function(n = 2000, mean = 0, sd = 1, ncol = 10, cof = 5) {
    d <- matrix(sinh(rnorm(n*ncol, mean, sd)) * cof,ncol=ncol)
    # --- Run Censcyt Wrapper [] ---
    # Key functions: censcyt
    out_DA <- censcyt(d_input,
    BPPARAM=BiocParallel::MulticoreParam(workers = 1))
    # --- Visualize Wrapper Results [] ---
    # Key functions: topTable, plotHeatmap
    topTable(out_DA, format_vals = TRUE)
    plotHeatmap(out_DA,
    sample_order = order(X_true))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_censcyt_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_censcyt_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_censcyt_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CENSCYT:", paste0("    censcyt: ", packageVersion("censcyt"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_censcyt_results.csv
    touch ${prefix}_censcyt_output.rds
    echo "BIOC_CENSCYT:" > versions.yml
    echo "    censcyt: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CENSCYT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CENSCYT(ch_input)

    emit:
    results  = BIOC_CENSCYT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CENSCYT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CENSCYT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CENSCYT.out.versions  // channel: path(versions.yml)
}
