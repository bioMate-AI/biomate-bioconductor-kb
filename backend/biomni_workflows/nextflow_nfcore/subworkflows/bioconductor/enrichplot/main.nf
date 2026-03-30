#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: enrichplot
// The 'enrichplot' package implements several visualization methods for interpreting functional enrich
//
// Source : https://yulab-smu.top/biomedical-knowledge-mining-book/enrichplot.html
// Upstream  : none
// Downstream: maEndToEnd
//
// Install: BiocManager::install("enrichplot")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENRICHPLOT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-enrichplot"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-enrichplot:1.26.6--r44_0' :
        'quay.io/biocontainers/bioconductor-enrichplot:1.26.6--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_enrichplot_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_enrichplot_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_enrichplot_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(enrichplot)
    library(jsonlite)

    # --- Bar Plot [] ---
    # Key functions: data, enrichDGN, mutate
    library(DOSE)
    data(geneList)
    de <- names(geneList)[abs(geneList) > 2]
    
    edo <- enrichDGN(de)
    
    library(enrichplot)
    barplot(edo, showCategory=20)
    
    library(clusterProfiler)
    
    mutate(edo, qscore = -log(p.adjust, base=10)) |>
    # --- Split top categories by ontology [] ---
    # Key functions: aes, scale_fill_brewer, geom_text, scale_y_discrete, autofacet
    library(enrichplot)
    library(ggplot2)
    
    p_nofacet <- barplot(
      ego_all,
      x = "Count",
      showCategory = 15,
      split = "ONTOLOGY"
    ) +
      aes(fill = ONTOLOGY) +
      scale_fill_brewer(palette = "Set2")
    
    # --- Dot plot [] ---
    # Key functions: gseDO, dotplot, ggtitle
    library(ggplot2)
    edo2 <- gseDO(geneList)
    dotplot(edo, showCategory=30) + ggtitle("dotplot for ORA")
    dotplot(edo2, showCategory=30) + ggtitle("dotplot for GSEA")
    # --- Gene-Concept Network [] ---
    # Key functions: setReadable, cnetplot, plot_list
    ## convert gene ID to Symbol
    edox <- setReadable(edo, 'org.Hs.eg.db', 'ENTREZID')
    p1 <- cnetplot(edox, foldChange=geneList)
    p2 <- cnetplot(edox, categorySizeBy=~ -log10(pvalue), foldChange=geneList)
    ## only plot high fold-change genes
    p3 <- cnetplot(edox, foldChange=geneList, fc_threshold = 2)
    p4 <- cnetplot(edox, foldChange=geneList, node_label = "share")
    plot_list(p1, p2, p3, p4, ncol=2, tag_levels = 'A')
    
    p1 <- cnetplot(edox, node_label="category")
    p2 <- cnetplot(edox, node_label="gene")
    p3 <- cnetplot(edox, node_label="all")
    # --- Heatmap-like functional classification [] ---
    # Key functions: heatplot, plot_list
    p1 <- heatplot(edox, showCategory=5)
    p2 <- heatplot(edox, foldChange=geneList, showCategory=5)
    plot_list(p1, p2, ncol=1, tag_levels = 'A')
    # --- Tree plot [] ---
    # Key functions: pairwise_termsim, treeplot, hexpand, plot_list
    library(ggtree)
    
    edox2 <- pairwise_termsim(edox)
    p1 <- treeplot(edox2, cladelab_offset=8, tiplab_offset=.3, fontsize_cladelab =5) +
        hexpand(.2)
    p2 <- treeplot(edox2, cluster_method = "average",
                cladelab_offset=14, tiplab_offset=.3, fontsize_cladelab =5) +
        hexpand(.3)
    aplot::plot_list(p1, p2, tag_levels='A', ncol=2)
    # --- Enrichment Map [] ---
    # Key functions: pairwise_termsim, emapplot, plot_list
    edo <- pairwise_termsim(edo)
    p1 <- emapplot(edo) # node_label = "category" (default)
    p2 <- emapplot(edo, node_label = "none")
    p3 <- emapplot(edo, node_label = "none", size_category=1.5)
    p4 <- emapplot(edo, node_label = "none", layout="with_fr")
    
    plot_list(p1, p2, p3, p4,
            ncol=2, tag_levels = 'A',
            design="AAAAAA\nBBCCDD",
            heights = c(1, .3))
    
    p5 <- emapplot(edo, node_label = "group")
    # --- Biological theme comparison [] ---
    # Key functions: data, compareCluster, pairwise_termsim, emapplot, plot_list
    library(clusterProfiler)
    data(gcSample)
    xx <- compareCluster(gcSample, fun="enrichKEGG",
                         organism="hsa", pvalueCutoff=0.05)
    xx <- pairwise_termsim(xx)
    p1 <- emapplot(xx)
    p2 <- emapplot(xx)
    p3 <- emapplot(xx, pie="count")
    p4 <- emapplot(xx, pie="count", size_category=1.5, layout="kk")
    plot_list(p1, p2, p3, p4, ncol=2, tag_levels = 'A')
    # --- UpSet Plot [] ---
    # Key functions: upsetplot, gseKEGG
    upsetplot(edo)
    
    kk2 <- gseKEGG(geneList     = geneList,
                   organism     = 'hsa',
                   minGSSize    = 120,
                   pvalueCutoff = 0.05,
                   verbose      = FALSE)
    upsetplot(kk2)
    # --- ridgeline plot for expression distribution of GSEA result [] ---
    # Key functions: ridgeplot
    ridgeplot(edo2)
    # --- running score and preranked list of GSEA result [] ---
    # Key functions: gseaplot, plot_list, gseaplot2, gsearank
    p1 <- gseaplot(edo2, geneSetID = 1, by = "runningScore", title = edo2$Description[1])
    p2 <- gseaplot(edo2, geneSetID = 1, by = "preranked", title = edo2$Description[1])
    p3 <- gseaplot(edo2, geneSetID = 1, title = edo2$Description[1])
    plot_list(p1, p2, p3, ncol=1, tag_levels='A')
    
    gseaplot2(edo2, geneSetID = 1, title = edo2$Description[1])
    
    gseaplot2(edo2, geneSetID = 1:3)
    
    gseaplot2(edo2, geneSetID = 1:3, pvalue_table = TRUE,
              color = c("#E495A5", "#86B875", "#7DB0DD"), ES_geom = "dot")
    
    # --- pubmed trend of enriched terms [] ---
    # Key functions: pmcplot, plot_list
    terms <- edo$Description[1:5]
    p <- pmcplot(terms, 2010:2020)
    p2 <- pmcplot(terms, 2010:2020, proportion=FALSE)
    plot_list(p, p2, ncol=2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_enrichplot_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_enrichplot_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_enrichplot_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ENRICHPLOT:", paste0("    enrichplot: ", packageVersion("enrichplot"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enrichplot_results.csv
    touch ${prefix}_enrichplot_output.rds
    echo "BIOC_ENRICHPLOT:" > versions.yml
    echo "    enrichplot: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ENRICHPLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ENRICHPLOT(ch_input)

    emit:
    results  = BIOC_ENRICHPLOT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ENRICHPLOT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ENRICHPLOT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ENRICHPLOT.out.versions  // channel: path(versions.yml)
}
