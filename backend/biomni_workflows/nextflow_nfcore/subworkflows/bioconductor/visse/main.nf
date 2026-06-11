#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vissE — summarize_gsea_results
// Summarize and interpret a list of significant gene sets from an enrichment analysis using network clustering, text-mining, and gene/PPI visualization.
// Input: geneset_gsc, geneset_stats, gene_stats, ppi
// Container: quay.io/biocontainers/bioconductor-visse:1.18.0--r45hdfd78af_0
// R packages: ggplot2, GSEABase, igraph, msigdb, patchwork, vissE
// Bioconductor: 3.20 | R: 4.4
// Requires: GSEABase, ggplot2, igraph, msigdb, patchwork, vissE
// Visualizations: network plot, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute gene-set overlap using computeMsigOverlap
//  * 2. [Input & Preparation] Build the overlap network using computeMsigNetwork
//  * 3. [Core Analysis] Identify clusters of gene-sets using findMsigClusters
//  * 4. [Visualization & Output] Characterize clusters using text-mining with plotMsigWordcloud
//  * 5. [Visualization & Output] Visualize gene-level statistics for clusters using plotGeneStats
//  * 6. [Visualization & Output] Visualize protein-protein interactions in clusters using plotMsigPPI
//  * 7. [Visualization & Output] Combine visualizations using patchwork

nextflow.enable.dsl = 2

process BIOC_VISSE_SUMMARIZE_GSEA_RESULTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("ggplot2", "GSEABase", "igraph", "msigdb", "patchwork", "vissE")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(msigdb)
    library(GSEABase)
    library(vissE)
    library(igraph)
    library(ggplot2)
    library(patchwork)
    
    # ==========================================
    # 1. READ USER INPUT FILES
    # ==========================================
    # The pipeline reads exactly these files from the working directory:
    # - geneset_gsc: A GeneSetCollection object containing the significant gene sets
    # - geneset_stats: A named numeric vector of gene-set level statistics
    # - gene_stats: A named numeric vector of gene-level statistics
    # - ppi: A protein-protein interaction database object
    geneset_gsc   <- readRDS("geneset_gsc.rds")
    geneset_stats <- readRDS("geneset_stats.rds")
    gene_stats    <- readRDS("gene_stats.rds")
    ppi           <- readRDS("ppi.rds")
    
    # Load and prepare the MSigDB database object required by vissE functions
    msigdb_hs <- getMsigdb()
    msigdb_hs <- subsetCollection(msigdb_hs, c('h', 'c2', 'c5'))
    
    # ==========================================
    # 2. COMPUTE GENE-SET OVERLAP & NETWORK
    # ==========================================
    # Compute gene-set overlap
    gs_ovlap = computeMsigOverlap(geneset_gsc, thresh = 0.25)
    
    # Create an overlap network
    gs_ovnet = computeMsigNetwork(gs_ovlap, msigdb_hs)
    
    # Save the network object
    saveRDS(gs_ovnet, "gs_ovnet.rds")
    
    # Plot the network
    pdf("plot_network.pdf", width = 8, height = 8)
    set.seed(36) # set seed for reproducible layout
    print(plotMsigNetwork(gs_ovnet))
    dev.off()
    
    # Plot the network and overlay gene-set statistics
    pdf("plot_network_stats.pdf", width = 8, height = 8)
    set.seed(36) # set seed for reproducible layout
    print(plotMsigNetwork(gs_ovnet, genesetStat = geneset_stats))
    dev.off()
    
    # ==========================================
    # 3. IDENTIFY CLUSTERS
    # ==========================================
    # Identify clusters - order based on cluster size and avg gene-set stats
    grps = findMsigClusters(gs_ovnet,
                            genesetStat = geneset_stats,
                            alg = cluster_walktrap,
                            minSize = 5)
    
    # Save the identified clusters
    saveRDS(grps, "grps.rds")
    
    # Export clusters to a CSV table for downstream analysis
    grps_df <- data.frame(
      Cluster = rep(names(grps), lengths(grps)),
      GeneSet = unlist(grps),
      stringsAsFactors = FALSE
    )
    write.csv(grps_df, "gene_set_clusters.csv", row.names = FALSE)
    
    # Subset up to the available length instead of repeating elements to prevent duplicate names
    grps_top <- head(grps, 6)
    
    # Plot the top clusters
    pdf("plot_network_clusters.pdf", width = 10, height = 8)
    set.seed(36) # set seed for reproducible layout
    print(plotMsigNetwork(gs_ovnet, markGroups = grps_top, genesetStat = geneset_stats))
    dev.off()
    
    # Plot focused network with unmarked groups removed
    pdf("plot_network_clusters_focused.pdf", width = 10, height = 8)
    set.seed(36) # set seed for reproducible layout
    print(plotMsigNetwork(
      gs_ovnet,
      markGroups = grps_top,
      genesetStat = geneset_stats,
      rmUnmarkedGroups = TRUE
    ))
    dev.off()
    
    # ==========================================
    # 4. CHARACTERIZE CLUSTERS (TEXT-MINING)
    # ==========================================
    # Compute and plot the results of text-mining using gene-set Names
    pdf("plot_wordcloud_name.pdf", width = 8, height = 8)
    print(plotMsigWordcloud(msigdb_hs, grps_top, type = 'Name'))
    dev.off()
    
    # Compute and plot the results of text-mining using gene-set Short descriptions
    pdf("plot_wordcloud_short.pdf", width = 8, height = 8)
    print(plotMsigWordcloud(msigdb_hs, grps_top, type = 'Short'))
    dev.off()
    
    # ==========================================
    # 5. VISUALIZE GENE-LEVEL STATISTICS
    # ==========================================
    # Plot the gene-level statistics
    pdf("plot_gene_stats.pdf", width = 10, height = 6)
    p_gene = plotGeneStats(gene_stats, msigdb_hs, grps_top) +
      geom_hline(yintercept = 0, colour = 2, lty = 2)
    print(p_gene)
    dev.off()
    
    # ==========================================
    # 6. VISUALIZE PROTEIN-PROTEIN INTERACTIONS
    # ==========================================
    # Create the PPI plot
    pdf("plot_ppi.pdf", width = 10, height = 8)
    set.seed(36)
    print(plotMsigPPI(
      ppi,
      msigdb_hs,
      grps_top,
      geneStat = gene_stats,
      threshStatistic = 0.2,
      threshConfidence = 0.2
    ))
    dev.off()
    
    # ==========================================
    # 7. COMBINE VISUALIZATIONS
    # ==========================================
    # Create independent plots and combine them using patchwork
    pdf("plot_combined.pdf", width = 14, height = 12)
    set.seed(36) # set seed for reproducible layout
    p1 = plotMsigWordcloud(msigdb_hs, grps_top, type = 'Name')
    p2 = plotMsigNetwork(gs_ovnet, markGroups = grps_top, genesetStat = geneset_stats)
    p3 = plotGeneStats(gene_stats, msigdb_hs, grps_top) +
      geom_hline(yintercept = 0, colour = 2, lty = 2)
    p4 = plotMsigPPI(
      ppi,
      msigdb_hs,
      grps_top,
      geneStat = gene_stats,
      threshStatistic = 0.2,
      threshConfidence = 0.2
    )
    
    # Combine using patchwork layout
    p_combined = p1 + p2 + p3 + p4 + plot_layout(2, 2)
    print(p_combined)
    dev.off()

    writeLines(c(
        '"BIOC_VISSE_SUMMARIZE_GSEA_RESULTS":',
        paste0('    vissE: ', as.character(packageVersion('vissE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_summarize_gsea_results.csv versions.yml
    """
}

workflow BIOC_VISSE_SUMMARIZE_GSEA_RESULTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneset_gsc, geneset_stats, gene_stats, ppi ] ]

    main:
    BIOC_VISSE_SUMMARIZE_GSEA_RESULTS(ch_input)

    emit:
    tables   = BIOC_VISSE_SUMMARIZE_GSEA_RESULTS.out.tables
    plots    = BIOC_VISSE_SUMMARIZE_GSEA_RESULTS.out.plots
    objects  = BIOC_VISSE_SUMMARIZE_GSEA_RESULTS.out.objects
    versions = BIOC_VISSE_SUMMARIZE_GSEA_RESULTS.out.versions
}
