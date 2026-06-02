#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: dce
// Compute differential causal effects (dce) on (biological) networks. Given observational samples from
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/dce/inst/doc/dce.R
// Upstream  : SummarizedExperiment, TCGAutils, cowplot, curatedTCGAData, ggplot2
// Downstream: none
//
// Install: BiocManager::install("dce")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DCE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dce"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dce:1.13.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dce:1.13.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dce_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dce_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dce_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TCGAsplitAssays)
    library(jsonlite)

    # --- Plot Grid [] ---
    # Key functions: plot_grid, plot_network
    ---------------------------------------------------------------------
    graph_mt <- graph_wt
    graph_mt["A", "B"] <- 2.5 # dysregulation happens here!
    graph_mt
    # --- Simulate Data [] ---
    # Key functions: simulate_data
    ---------------------------------------------------------------------
    X_wt <- simulate_data(graph_wt)
    X_mt <- simulate_data(graph_mt)
    X_wt %>%
      head
    # --- Dce [] ---
    # Key functions: dce
    ---------------------------------------------------------------------
    res <- dce(graph_wt, X_wt, X_mt)
    res %>%
      as.data.frame %>%
      drop_na
    # --- Plot [] ---
    # Key functions: ggtitle
    ---------------------------------------------------------------------
    plot(res) +
      ggtitle("Differential Causal Effects between WT and MT condition")
    # --- Simulate Data [] ---
    # Key functions: simulate_data, dce, arrange
    ---------------------------------------------------------------------
    # simulate gene expression data for both networks
    X_wt <- simulate_data(graph_wt)
    X_mt <- simulate_data(graph_mt)
    # compute DCEs
    # --- Trueeffects [] ---
    # Key functions: trueEffects, frame, inner_join, rename, ggplot
    ---------------------------------------------------------------------
    # compute ground truth DCEs
    dce_gt <- trueEffects(graph_mt) - trueEffects(graph_wt)
    dce_gt_ind <- which(dce_gt != 0, arr.ind = TRUE)
    # create plot
    # --- Curatedtcgadata [] ---
    # Key functions: curatedTCGAData
    ---------------------------------------------------------------------
    # --- Sampletables [] ---
    # Key functions: sampleTables, filter
    ---------------------------------------------------------------------
    sampleTables(brca)
    data(sampleTypes, package = "TCGAutils")
    sampleTypes %>%
      dplyr::filter(Code %in% c("01", "06", "11"))
    # --- Tcgasplitassays [] ---
    # Key functions: TCGAsplitAssays, assay
    ---------------------------------------------------------------------
    # split assays
    brca_split <- TCGAsplitAssays(brca, c("01", "11"))
    # only retain matching samples
    brca_matched <- as(brca_split, "MatchedAssayExperiment")
    # --- Get Pathways [] ---
    # Key functions: get_pathways
    ---------------------------------------------------------------------
    pathways <- get_pathways(pathway_list = list(kegg = c("Breast cancer")))
    brca_pathway <- pathways[[1]]$graph
    # --- Intersect [] ---
    # Key functions: intersect, nodes, glue
    ---------------------------------------------------------------------
    shared_genes <- intersect(nodes(brca_pathway), rownames(brca_wt))
    glue::glue(
      "Covered nodes: {length(shared_genes)}/{length(nodes(brca_pathway))}"
    )
    # --- Arrange [] ---
    # Key functions: arrange, desc
    ---------------------------------------------------------------------
    res %>%
      as.data.frame %>%
      drop_na %>%
      arrange(desc(abs(dce))) %>%
    # --- Dce [] ---
    # Key functions: dce, qplot, geom_abline, xlab, ylab, plot_network, ggtitle
    ---------------------------------------------------------------------
    res <- dce(graph_mt, X_wt, X_mt, deconfounding = FALSE)
    qplot(truth[truth != 0], res$dce[truth != 0]) +
      geom_abline(color = "red", linetype = "dashed") +
      xlab("true DCE") +
    # --- Sample [] ---
    # Key functions: sample, runif, dce
    ---------------------------------------------------------------------
    batch <- sample(c(0, 1), replace = TRUE, nrow(X_wt))
    bX_wt <- apply(X_wt, 2, function(x) x + max(x) * runif(1) * batch)
    bX_mt <- apply(X_mt, 2, function(x) x + max(x) * runif(1) * batch)
    res_without_deconf <- dce(graph_mt, bX_wt, bX_mt, deconfounding = FALSE)
    # --- Dce [] ---
    # Key functions: dce, plot_grid, plot_network, ggtitle, qplot, geom_abline, xlab
    ---------------------------------------------------------------------
    res_with_deconf <- dce(graph_mt, bX_wt, bX_mt, deconfounding = 1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dce_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dce_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dce_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DCE:", paste0("    dce: ", packageVersion("dce"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dce_results.csv
    touch ${prefix}_dce_output.rds
    echo "BIOC_DCE:" > versions.yml
    echo "    dce: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DCE(ch_input)

    emit:
    results  = BIOC_DCE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DCE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DCE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DCE.out.versions  // channel: path(versions.yml)
}
