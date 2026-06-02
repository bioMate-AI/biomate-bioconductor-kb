#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BioNERO
// BioNERO aims to integrate all aspects of biological network inference in a single package, including
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BioNERO/inst/doc/vignette_01_GCN_inference.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BioNERO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIONERO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bionero"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bionero:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bionero:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_bionero_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bionero_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bionero_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BioNERO)
    library(jsonlite)


    # --- Data Loading Soybean [] ---
    # Key functions: colData, replace_na, remove_nonexp
    data(zma.se)

    # Take a quick look at the data
    zma.se
    SummarizedExperiment::colData(zma.se)
    exp_filt <- replace_na(zma.se)
    sum(is.na(zma.se))
    exp_filt <- remove_nonexp(exp_filt, method = "median", min_exp = 10)
    dim(exp_filt)

    # --- Filter By Variance [] ---
    # Key functions: filter_by_variance, ZKfiltering, pearson, PC_correction
    exp_filt <- filter_by_variance(exp_filt, n = 2000)
    dim(exp_filt)
    exp_filt <- ZKfiltering(exp_filt, cor_method = "pearson")
    dim(exp_filt)
    exp_filt <- PC_correction(exp_filt)

    # --- Exp Preprocess [] ---
    # Key functions: exp_preprocess, identical, plot_heatmap, expression, samplecor, expr
    final_exp <- exp_preprocess(
        zma.se, min_exp = 10, variance_filter = TRUE, n = 2000
    )
    identical(dim(exp_filt), dim(final_exp))

    # Take a look at the final data
    final_exp
    # This object is no longer necessary
    rm(exp_filt)
    # Heatmap of sample correlations
    p <- plot_heatmap(final_exp, type = "samplecor", show_rownames = FALSE)
    p

    # Heatmap of gene expression (here, only the first 50 genes)
    p <- plot_heatmap(
        final_exp[1:50, ], type = "expr", show_rownames = FALSE, show_colnames = FALSE
    )
    p

    # --- Pcaplot [] ---
    # Key functions: plot_PCA, SFT_fit, pearson
    plot_PCA(final_exp)
    sft <- SFT_fit(final_exp, net_type = "signed hybrid", cor_method = "pearson")
    sft$power
    power <- sft$power
    sft$plot

    # --- Exp2net [] ---
    # Key functions: exp2gcn, pearson, plot_dendro_and_colors, plot_eigengene_network
    net <- exp2gcn(
        final_exp, net_type = "signed hybrid", SFTpower = power, 
        cor_method = "pearson"
    )
    names(net)
    # Dendro and colors
    plot_dendro_and_colors(net)
    # Eigengene networks
    plot_eigengene_network(net)

    # --- Genes Per Module [] ---
    # Key functions: plot_ngenes_per_module, module_stability, module_trait_cor, plot_module_trait_cor
    plot_ngenes_per_module(net)
    module_stability(final_exp, net, nRuns = 5)
    MEtrait <- module_trait_cor(exp = final_exp, MEs = net$MEs)
    head(MEtrait)

    ## ----plot-module-trait-cor, fig.width = 5, fig.height = 5---------------------
    plot_module_trait_cor(MEtrait)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bionero_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bionero_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bionero_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIONERO:", paste0("    bionero: ", packageVersion("BioNERO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bionero_results.csv
    touch ${prefix}_bionero_output.rds
    echo "BIOC_BIONERO:" > versions.yml
    echo "    bionero: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIONERO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_BIONERO(ch_input)

    emit:
    results  = BIOC_BIONERO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIONERO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIONERO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIONERO.out.versions  // channel: path(versions.yml)
}
