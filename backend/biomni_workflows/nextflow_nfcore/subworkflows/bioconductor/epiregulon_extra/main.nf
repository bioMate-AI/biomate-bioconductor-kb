#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epiregulon.extra
// Gene regulatory networks model the underlying gene regulation hierarchies that drive gene expression
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epiregulon.extra/inst/doc/Data_visualization.R
// Upstream  : epiregulon, ggplot2, scMultiome
// Downstream: none
//
// Install: BiocManager::install("epiregulon.extra")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIREGULON_EXTRA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epiregulon_extra"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epiregulon.extra:1.2.4--r44_0' :
        'quay.io/biocontainers/bioconductor-epiregulon.extra:1.2.4--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epiregulon_extra_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epiregulon_extra_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epiregulon_extra_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(epiregulon.extra)
    library(jsonlite)

    # --- Differential Activity Analysis [] ---
    # Key functions: findDifferentialActivity, getSigGenes
    markers <- findDifferentialActivity(
        activity_matrix = score.combine,
        clusters = GeneExpressionMatrix$hash_assignment,
        pval.type = "some",
        direction = "up",
        test.type = "t",
        logvalue = FALSE
    )
    markers.sig <- getSigGenes(markers, topgenes = 5)


    # --- Activity Visualization [] ---
    # Key functions: plotBubble, plotActivityViolin, plotActivityDim
    plotBubble(
        activity_matrix = score.combine,
        tf = c("NKX2-1", "GATA6", "FOXA1", "FOXA2"),
        clusters = GeneExpressionMatrix$hash_assignment
    )
    plotActivityViolin(
        activity_matrix = score.combine,
        tf = c("NKX2-1", "GATA6", "FOXA1", "FOXA2", "AR"),
        clusters = GeneExpressionMatrix$hash_assignment
    )
    ActivityPlot <- plotActivityDim(
        sce = GeneExpressionMatrix,
        activity_matrix = score.combine,
        tf = c("NKX2-1", "GATA6", "FOXA1", "FOXA2", "AR"),
        dimtype = "UMAP_Combined",
        label = "Clusters",
        point_size = 0.3,
        ncol = 3,
        rasterise = TRUE
    )


    # --- Regulon Enrichment Analysis [] ---
    # Key functions: regulonEnrich, enrichPlot, plotGseaNetwork
    enrichresults <- regulonEnrich(
        TF = c("GATA6", "NKX2-1"),
        regulon = regulon,
        weight = "weight",
        weight_cutoff = 0.1,
        genesets = gs.list
    )
    enrichPlot(results = enrichresults)
    plotGseaNetwork(
        tf = names(enrichresults),
        enrichresults = enrichresults,
        p.adj_cutoff = 0.1,
        ntop_pathways = 10
    )


    # --- Network Construction and Centrality [] ---
    # Key functions: buildGraph, buildDiffGraph, addCentrality, normalizeCentrality, rankTfs
    C1_network <- buildGraph(regulon, weights = "weight", cluster = "C1")
    C5_network <- buildGraph(regulon, weights = "weight", cluster = "C5")
    diff_graph <- buildDiffGraph(C1_network, C5_network, abs_diff = FALSE)
    diff_graph <- addCentrality(diff_graph)
    diff_graph <- normalizeCentrality(diff_graph)
    rank_table <- rankTfs(diff_graph)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epiregulon_extra_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epiregulon_extra_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epiregulon_extra_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIREGULON_EXTRA:", paste0("    epiregulon_extra: ", packageVersion("epiregulon.extra"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epiregulon_extra_results.csv
    touch ${prefix}_epiregulon_extra_output.rds
    echo "BIOC_EPIREGULON_EXTRA:" > versions.yml
    echo "    epiregulon_extra: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIREGULON_EXTRA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPIREGULON_EXTRA(ch_input)

    emit:
    results  = BIOC_EPIREGULON_EXTRA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIREGULON_EXTRA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIREGULON_EXTRA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIREGULON_EXTRA.out.versions  // channel: path(versions.yml)
}
