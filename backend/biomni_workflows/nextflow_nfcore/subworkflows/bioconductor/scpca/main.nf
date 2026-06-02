#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scPCA
// A toolbox for sparse contrastive principal component analysis (scPCA) of high-dimensional biological
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scPCA/inst/doc/scpca_intro.R
// Upstream  : SingleCellExperiment, dplyr, elasticnet, ggplot2, ggpubr
// Downstream: OSCA.advanced, OSCA.workflows
//
// Install: BiocManager::install("scPCA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCPCA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scpca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scpca:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scpca:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scpca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scpca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scpca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scPCA)
    library(jsonlite)

    # --- Pca Sim [] ---
    # Key functions: prcomp, as_tibble, ggplot, aes
    # set seed for reproducibility
    set.seed(1742)
    # load data
    data(toy_df)
    # perform PCA
    # --- Spca Sim [] ---
    # Key functions: spca
    # perform sPCA on toy_df for a range of L1 penalty terms
    penalties <- exp(seq(log(10), log(1000), length.out = 6))
    # --- Cpca Sim [] ---
    # Key functions: scPCA, as_tibble, mutate, ggplot, aes, geom_point
    cpca_sim <- scPCA(target = toy_df[, 1:30],
                      background = background_df,
                      penalties = 0,
                      n_centers = 4)
    # create a dataframe to be plotted
    # --- Scpca Sim [] ---
    # Key functions: scPCA, as_tibble, mutate
    # run scPCA for using 40 logarithmically seperated contrastive parameter values
    # and possible 20 L1 penalty terms
    # --- Cpca Sim Cv [] ---
    # Key functions: scPCA, as_tibble, mutate, ggplot, aes, geom_point
    cpca_cv_sim <- scPCA(target = toy_df[, 1:30],
                         background = background_df,
                         penalties = 0,
                         n_centers = 4,
                         cv = 3)
    # --- Scpca Sim Cv [] ---
    # Key functions: scPCA, as_tibble, mutate

    # --- Plot Cv Cpca Scpca [] ---
    # Key functions: ggarrange

    # --- Microbenchmark Comparison [] ---
    # Key functions: microbenchmark, scPCA, autoplot, ggtitle, theme_minimal

    # --- Sce Setup [] ---
    # Key functions: newSplatParams, splatSimulate
    library(splatter)
    library(SingleCellExperiment)
    # Simulate the three groups of cells. Mask cell heterogeneity with batch effect
    # --- Make Sce Subs [] ---
    # Key functions: assay
    # rank genes by variance
    n_genes <- 250
    vars <- assay(sim_sce) %>%
      log1p %>%
      rowVars
    # --- Perform Dimred [] ---
    # Key functions: prcomp, log1p, counts, scPCA
    # for both cPCA and scPCA, we'll set the penalties and contrasts arguments
    contrasts <- exp(seq(log(0.1), log(100), length.out = 5))
    penalties <- exp(seq(log(0.001), log(0.1), length.out = 3))
    # first, PCA
    pca_out <- prcomp(t(log1p(counts(tg_sce))), center = TRUE, scale. = TRUE)
    # --- Plot Red Dims [] ---
    # Key functions: frame, ggplot, aes, geom_point, ggtitle, scale_colour_viridis_d, scale_shape_discrete
    # plot the 2D representations
    # prepare PCA

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scpca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scpca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scpca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCPCA:", paste0("    scpca: ", packageVersion("scPCA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scpca_results.csv
    touch ${prefix}_scpca_output.rds
    echo "BIOC_SCPCA:" > versions.yml
    echo "    scpca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCPCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCPCA(ch_input)

    emit:
    results  = BIOC_SCPCA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCPCA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCPCA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCPCA.out.versions  // channel: path(versions.yml)
}
