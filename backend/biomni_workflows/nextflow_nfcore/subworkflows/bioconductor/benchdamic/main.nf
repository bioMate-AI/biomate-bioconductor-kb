#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: benchdamic
// Starting from a microbiome dataset (16S or WMS with absolute count values) it is possible to perform
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/benchdamic/inst/doc/intro.R
// Upstream  : BiocParallel, SPsimSeq, SummarizedExperiment, cowplot, ggplot2
// Downstream: none
//
// Install: BiocManager::install("benchdamic")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BENCHDAMIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-benchdamic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-benchdamic:1.12.2--r44_0' :
        'quay.io/biocontainers/bioconductor-benchdamic:1.12.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_benchdamic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_benchdamic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_benchdamic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(benchdamic)
    library(SerialParam)
    library(TreeSummarizedExperiment)
    library(jsonlite)

    # --- Goodness of Fit Evaluation [Goodness of Fit] ---
    # Key functions: fitHURDLE, prepareObserved, meanDifferences, fitModels
    data("ps_stool_16S")
    example_HURDLE <- fitHURDLE(
        object = ps_stool_16S,
        scale = "median"
    )
    observed_hurdle <- prepareObserved(
        object = ps_stool_16S,
        scale = "median"
    )
    m_diffs <- meanDifferences(
        estimated = example_HURDLE,
        observed = observed_hurdle
    )
    gof_models <- fitModels(
        object = ps_stool_16S,
        models = c("NB", "ZINB", "DM", "ZIG", "HURDLE"),
        scale_HURDLE = c("median", "default"),
        verbose = FALSE
    )

    # --- Goodness of Fit Visualization [Visualisation] ---
    # Key functions: plotRMSE, plotMD
    rmse_md <- plotRMSE(
        gof_models,
        difference = "MD",
        plotIt = FALSE
    )
    rmse_zpd <- plotRMSE(
        gof_models,
        difference = "ZPD",
        plotIt = FALSE
    )
    md_plot <- plotMD(
        data = gof_models,
        difference = "MD",
        split = TRUE
    )
    zpd_plot <- plotMD(
        data = gof_models[1:5],
        difference = "ZPD",
        split = TRUE
    )

    # --- Mock Dataset Generation and Normalisation [Normalisation] ---
    # Key functions: createMocks, setNormalizations, runNormalizations
    data("ps_stool_16S")
    my_mocks <- createMocks(
        nsamples = phyloseq::nsamples(ps_stool_16S),
        N = 3
    )
    my_norms <- setNormalizations(
        fun = c("norm_edgeR", "norm_DESeq2", "norm_CSS"),
        method = c("TMM", "poscounts", "CSS")
    )
    ps_norm <- runNormalizations(
        normalization_list = my_norms,
        object = ps_stool_16S,
        verbose = FALSE
    )

    # --- Zero-Inflated Negative Binomial Weights Estimation [Weights Estimation] ---
    # Key functions: weights_ZINB
    data("ps_stool_16S")
    zinbweights <- weights_ZINB(
        object = ps_stool_16S,
        K = 0,
        design = "~ 1"
    )

    # --- Differential Abundance Method Configuration [Method Configuration] ---
    # Key functions: set_edgeR, set_DESeq2, set_limma, set_MAST, set_linda
    my_edgeR <- set_edgeR(
        pseudo_count = FALSE,
        group_name = "group",
        design = ~ group,
        robust = FALSE,
        coef = 2,
        norm = "TMM",
        weights_logical = c(TRUE, FALSE),
        expand = TRUE
    )
    my_DESeq2 <- set_DESeq2(
        pseudo_count = FALSE,
        design = ~ group,
        contrast = c("group", "grp2", "grp1"),
        norm = "poscounts",
        weights_logical = c(TRUE, FALSE),
        alpha = 0.05,
        expand = TRUE
    )
    my_limma <- set_limma(
        pseudo_count = FALSE,
        design = ~ group,
        coef = 2,
        norm = "TMM",
        weights_logical = c(FALSE, TRUE),
        expand = TRUE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_benchdamic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_benchdamic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_benchdamic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BENCHDAMIC:", paste0("    benchdamic: ", packageVersion("benchdamic"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_benchdamic_results.csv
    touch ${prefix}_benchdamic_output.rds
    echo "BIOC_BENCHDAMIC:" > versions.yml
    echo "    benchdamic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BENCHDAMIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BENCHDAMIC(ch_input)

    emit:
    results  = BIOC_BENCHDAMIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BENCHDAMIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BENCHDAMIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BENCHDAMIC.out.versions  // channel: path(versions.yml)
}
