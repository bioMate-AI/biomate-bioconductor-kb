#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: miaViz
// The miaViz package implements functions to visualize TreeSummarizedExperiment objects especially in 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/miaViz/inst/doc/miaViz.R
// Upstream  : dplyr, mia, miaTime, scater
// Downstream: none
//
// Install: BiocManager::install("miaViz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIAVIZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-miaviz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-miaviz:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-miaviz:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_miaviz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_miaviz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_miaviz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(miaViz)
    library(jsonlite)

    # --- Prevalence and Feature Analysis [] ---
    # Key functions: plotFeaturePrevalence, plotPrevalentAbundance, plotPrevalence
    p_feat <- plotFeaturePrevalence(GlobalPatterns, rank = "Phylum",
                                    detections = c(0, 0.001, 0.01, 0.1, 0.2))
    p_prev_abund <- plotPrevalentAbundance(GlobalPatterns, rank = "Family",
                                           colour_by = "Phylum")
    p_prev <- plotPrevalence(GlobalPatterns,
                             rank = "Phylum",
                             detections = c(0.01, 0.1, 1, 2, 5, 10, 20)/100,
                             prevalences = seq(0.1, 1, 0.1))


    # --- Phylogenetic Tree Visualization [] ---
    # Key functions: plotRowTree
    genus_se <- mia::agglomerateByRank(GlobalPatterns, "Genus")
    genus_se <- scater::addPerFeatureQC(genus_se)
    SummarizedExperiment::rowData(genus_se)$log_mean <- log(
        SummarizedExperiment::rowData(genus_se)$mean
    )
    SummarizedExperiment::rowData(genus_se)$detected <- (
        SummarizedExperiment::rowData(genus_se)$detected / 100
    )
    top_taxa <- mia::getTop(genus_se, method = "mean", top = 100L,
                            assay.type = "counts")
    p_tree <- plotRowTree(genus_se[top_taxa, ],
                          tip_colour_by = "log_mean",
                          tip_size_by = "detected",
                          show_label = TRUE)


    # --- Column Graph Visualization [] ---
    # Key functions: plotColGraph
    data(col_graph)
    genus_se <- mia::agglomerateByRank(GlobalPatterns, "Genus")
    p_graph <- plotColGraph(col_graph,
                            genus_se,
                            colour_by = "SampleType",
                            edge_colour_by = "weight",
                            edge_width_by = "weight",
                            show_label = TRUE)


    # --- Metadata and Model Fit Visualization [] ---
    # Key functions: plotColTile, plotDMNFit
    data(dmn_se, package = "mia")
    p_tile <- plotColTile(GlobalPatterns,
                          x = "SampleType",
                          y = "Primer")
    p_dmn <- plotDMNFit(dmn_se, type = "laplace")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_miaviz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_miaviz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_miaviz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIAVIZ:", paste0("    miaviz: ", packageVersion("miaViz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_miaviz_results.csv
    touch ${prefix}_miaviz_output.rds
    echo "BIOC_MIAVIZ:" > versions.yml
    echo "    miaviz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIAVIZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIAVIZ(ch_input)

    emit:
    results  = BIOC_MIAVIZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIAVIZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIAVIZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIAVIZ.out.versions  // channel: path(versions.yml)
}
