#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clusterProfiler — biological_theme_comparison
// Compare functional profiles and enriched pathways across multiple gene clusters.
// Input: gene_clusters.csv
// Container: quay.io/biocontainers/bioconductor-clusterprofiler:4.18.4--r45hdfd78af_0
// R packages: clusterProfiler, enrichplot, org.Hs.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: clusterProfiler, enrichplot, org.Hs.eg.db
// Visualizations: dot plot, gene-concept network, enrichment map, enrichment plot, network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare multiple gene clusters
//  * 2. [Core Analysis] Compare clusters using the compareCluster function
//  * 3. [Visualization & Output] Visualize comparison results using dotplot, cnetplot, or emapplot

nextflow.enable.dsl = 2

process BIOC_CLUSTERPROFILER_BIOLOGICAL_THEME_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("clusterProfiler", "enrichplot", "org.Hs.eg.db")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    suppressPackageStartupMessages({
      library(clusterProfiler)
      library(org.Hs.eg.db)
      library(enrichplot)
    })
    
    # Step 1: Prepare multiple gene clusters from user input
    input_file <- "gene_clusters.csv"
    if (!file.exists(input_file)) {
      stop(paste("Input file", input_file, "not found in the working directory."))
    }
    
    df <- read.csv(input_file, stringsAsFactors = FALSE)
    
    # Identify gene and cluster columns dynamically
    gene_col <- grep("gene|entrez|id|symbol", colnames(df), ignore.case = TRUE, value = TRUE)[1]
    if (is.na(gene_col)) gene_col <- colnames(df)[1]
    
    cluster_col <- grep("cluster|group|condition", colnames(df), ignore.case = TRUE, value = TRUE)[1]
    if (is.na(cluster_col)) {
      if (ncol(df) >= 2) {
        cluster_col <- colnames(df)[2]
      } else {
        df\$cluster <- "Cluster1"
        cluster_col <- "cluster"
      }
    }
    
    # Determine keyType (ENTREZID or SYMBOL) based on the first gene ID
    first_gene <- as.character(df[[gene_col]][1])
    if (!is.na(suppressWarnings(as.numeric(first_gene)))) {
      keytype <- "ENTREZID"
    } else {
      keytype <- "SYMBOL"
    }
    
    # Split genes into a list of clusters
    gene_clusters <- split(as.character(df[[gene_col]]), df[[cluster_col]])
    
    # Step 2: Compare clusters using the compareCluster function
    message("Comparing clusters...")
    res <- compareCluster(
      geneCluster = gene_clusters,
      fun = "enrichGO",
      OrgDb = "org.Hs.eg.db",
      keyType = keytype,
      ont = "BP",
      pAdjustMethod = "BH",
      pvalueCutoff = 0.05,
      qvalueCutoff = 0.2
    )
    
    # Save tabular results
    res_df <- as.data.frame(res)
    write.csv(res_df, "comparison_results.csv", row.names = FALSE)
    saveRDS(res, "comparison_results.rds")
    message("Results saved to comparison_results.csv and comparison_results.rds")
    
    # Step 3: Visualize comparison results using dotplot, cnetplot, and emapplot
    if (nrow(res_df) > 0) {
      message("Generating plots...")
    
      # Dotplot
      tryCatch({
        pdf("dotplot_comparison.pdf", width = 10, height = 8)
        print(dotplot(res))
        dev.off()
        message("Saved dotplot_comparison.pdf")
      }, error = function(e) {
        message("Failed to generate dotplot: ", e\$message)
      })
    
      # Emapplot (requires pairwise similarity calculation first)
      tryCatch({
        res_sim <- pairwise_termsim(res)
        pdf("emapplot_comparison.pdf", width = 10, height = 8)
        print(emapplot(res_sim))
        dev.off()
        message("Saved emapplot_comparison.pdf")
      }, error = function(e) {
        message("Failed to generate emapplot: ", e\$message)
      })
    
      # Cnetplot
      tryCatch({
        pdf("cnetplot_comparison.pdf", width = 12, height = 10)
        print(cnetplot(res))
        dev.off()
        message("Saved cnetplot_comparison.pdf")
      }, error = function(e) {
        message("Failed to generate cnetplot: ", e\$message)
      })
    
    } else {
      message("No enriched terms found. Skipping visualization plots.")
    }

    writeLines(c(
        '"BIOC_CLUSTERPROFILER_BIOLOGICAL_THEME_COMPARISON":',
        paste0('    clusterProfiler: ', as.character(packageVersion('clusterProfiler')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biological_theme_comparison.csv versions.yml
    """
}

workflow BIOC_CLUSTERPROFILER_BIOLOGICAL_THEME_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_clusters.csv ] ]

    main:
    BIOC_CLUSTERPROFILER_BIOLOGICAL_THEME_COMPARISON(ch_input)

    emit:
    tables   = BIOC_CLUSTERPROFILER_BIOLOGICAL_THEME_COMPARISON.out.tables
    plots    = BIOC_CLUSTERPROFILER_BIOLOGICAL_THEME_COMPARISON.out.plots
    objects  = BIOC_CLUSTERPROFILER_BIOLOGICAL_THEME_COMPARISON.out.objects
    versions = BIOC_CLUSTERPROFILER_BIOLOGICAL_THEME_COMPARISON.out.versions
}
