#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: goSTAG — gostag_analysis
// Perform GO enrichment on multiple gene lists, cluster and group the enriched GO terms, annotate the clusters using representative subtree terms, and visualize t
// Input: gene_lists.gmt, /gene/lists/directory
// Container: quay.io/biocontainers/bioconductor-gostag:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: goSTAG
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load gene lists using loadGeneLists
//  * 2. [Input & Preparation] Load GO terms and gene associations using loadGOTerms
//  * 3. [Core Analysis] Generate the enrichment matrix using performGOEnrichment
//  * 4. [Core Analysis] Perform hierarchical clustering on GO terms and samples using performHierarchicalClustering
//  * 5. [Core Analysis] Group the clustered GO terms into distinct clusters using groupClusters
//  * 6. [Core Analysis] Annotate the clusters with representative GO terms using annotateClusters
//  * 7. [Visualization & Output] Visualize the results as a heatmap using plotHeatmap

nextflow.enable.dsl = 2

process BIOC_GOSTAG_GOSTAG_ANALYSIS {
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
    .bm_deps <- c("goSTAG")
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
    
    # Load the required library
    library(goSTAG)
    
    # 1. Load gene lists from the user-specified inputs
    # The pipeline supports either a GMT file or a directory of gene lists.
    if (file.exists("gene_lists.gmt")) {
      message("Loading gene lists from GMT file: gene_lists.gmt")
      gene_lists <- loadGeneLists("gene_lists.gmt")
    } else if (dir.exists("/gene/lists/directory")) {
      message("Loading gene lists from directory: /gene/lists/directory")
      gene_lists <- loadGeneLists("/gene/lists/directory", type = "DIR")
    } else if (dir.exists("gene/lists/directory")) {
      message("Loading gene lists from local directory: gene/lists/directory")
      gene_lists <- loadGeneLists("gene/lists/directory", type = "DIR")
    } else {
      stop("Error: Neither 'gene_lists.gmt' nor '/gene/lists/directory' was found in the working directory.")
    }
    
    # 2. Load GO terms and gene associations
    message("Loading GO terms...")
    go_terms <- loadGOTerms()
    
    # 3. Generate the enrichment matrix
    message("Performing GO enrichment analysis...")
    enrichment_matrix <- performGOEnrichment(gene_lists, go_terms)
    
    # Save enrichment matrix to disk
    write.csv(enrichment_matrix, file = "enrichment_matrix.csv", row.names = TRUE)
    saveRDS(enrichment_matrix, file = "enrichment_matrix.rds")
    
    # 4. Perform hierarchical clustering on GO terms and samples
    message("Performing hierarchical clustering...")
    hclust_results <- performHierarchicalClustering(enrichment_matrix)
    hclust_results_euclidean <- performHierarchicalClustering(enrichment_matrix, distance_method = "euclidean", clustering_method = "complete")
    sample_hclust_results <- performHierarchicalClustering(enrichment_matrix, feature = "col")
    
    # Save clustering results
    saveRDS(hclust_results, file = "hclust_results.rds")
    saveRDS(hclust_results_euclidean, file = "hclust_results_euclidean.rds")
    saveRDS(sample_hclust_results, file = "sample_hclust_results.rds")
    
    # 5. Group the clustered GO terms into distinct clusters
    message("Grouping clusters...")
    clusters <- groupClusters(hclust_results_euclidean)
    saveRDS(clusters, file = "clusters.rds")
    
    # 6. Annotate the clusters with representative GO terms
    message("Annotating clusters...")
    cluster_labels <- annotateClusters(clusters)
    
    # Save cluster annotations
    cluster_labels_df <- data.frame(
      Cluster = names(cluster_labels),
      Representative_Term = cluster_labels,
      stringsAsFactors = FALSE
    )
    write.csv(cluster_labels_df, file = "cluster_annotations.csv", row.names = FALSE)
    saveRDS(cluster_labels, file = "cluster_labels.rds")
    
    # 7. Visualize the results as heatmaps
    message("Generating heatmap visualizations...")
    
    # Simple heatmap
    pdf("heatmap_simple.pdf", width = 12, height = 10)
    plotHeatmap(enrichment_matrix, hclust_results_euclidean, clusters, cluster_labels)
    dev.off()
    
    # Heatmap with sample clustering
    pdf("heatmap_with_samples.pdf", width = 12, height = 10)
    plotHeatmap(enrichment_matrix, hclust_results_euclidean, clusters, cluster_labels, sample_hclust_results = sample_hclust_results)
    dev.off()
    
    message("goSTAG analysis pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_GOSTAG_GOSTAG_ANALYSIS":',
        paste0('    goSTAG: ', as.character(packageVersion('goSTAG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gostag_analysis.csv versions.yml
    """
}

workflow BIOC_GOSTAG_GOSTAG_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_lists.gmt, /gene/lists/directory ] ]

    main:
    BIOC_GOSTAG_GOSTAG_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GOSTAG_GOSTAG_ANALYSIS.out.tables
    plots    = BIOC_GOSTAG_GOSTAG_ANALYSIS.out.plots
    objects  = BIOC_GOSTAG_GOSTAG_ANALYSIS.out.objects
    versions = BIOC_GOSTAG_GOSTAG_ANALYSIS.out.versions
}
