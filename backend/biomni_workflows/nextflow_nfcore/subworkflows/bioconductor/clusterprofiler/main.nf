#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clusterProfiler — over_representation_analysis
// Identify over-represented biological terms and pathways in a list of genes of interest.
// Input: gene_list.txt
// Container: quay.io/biocontainers/bioconductor-clusterprofiler:4.18.4--r45hdfd78af_0
// R packages: clusterProfiler, enrichplot, org.Hs.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: clusterProfiler, enrichplot, org.Hs.eg.db
// Visualizations: dot plot, gene-concept network, enrichment map, GO DAG plot, bar plot, network plot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import the gene list
//  * 2. [Core Analysis] Perform enrichment analysis using functions like enrichGO, enrichKEGG, enricher, enrichMKEGG, enrichWP, or enrichDAVID
//  * 3. [Core Analysis] Map gene IDs to readable symbols using setReadable
//  * 4. [Core Analysis] Simplify GO terms to reduce redundancy using simplify
//  * 5. [Visualization & Output] Visualize results using barplot, dotplot, cnetplot, emapplot, or goplot

nextflow.enable.dsl = 2

process BIOC_CLUSTERPROFILER_OVER_REPRESENTATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    library(clusterProfiler)
    library(org.Hs.eg.db)
    library(enrichplot)
    
    # 1. Import the gene list
    if (!file.exists("gene_list.txt")) {
      stop("Error: 'gene_list.txt' not found in the working directory.")
    }
    
    gene_list <- readLines("gene_list.txt")
    gene_list <- trimws(gene_list)
    gene_list <- gene_list[gene_list != ""]
    
    if (length(gene_list) == 0) {
      stop("Error: 'gene_list.txt' is empty.")
    }
    
    # Determine keyType based on input format (Entrez ID vs Symbol)
    is_numeric <- all(grepl("^\\\\d+\$", gene_list))
    key_type <- if (is_numeric) "ENTREZID" else "SYMBOL"
    
    # 2. Perform enrichment analysis using enrichGO
    ego <- enrichGO(
      gene          = gene_list,
      OrgDb         = org.Hs.eg.db,
      keyType       = key_type,
      ont           = "BP",
      pAdjustMethod = "BH",
      pvalueCutoff  = 0.05,
      qvalueCutoff  = 0.2
    )
    
    # 3. Map gene IDs to readable symbols using setReadable
    ego_readable <- ego
    if (key_type != "SYMBOL") {
      ego_readable <- tryCatch({
        setReadable(ego, OrgDb = org.Hs.eg.db, keyType = key_type)
      }, error = function(e) {
        warning("setReadable failed: ", e\$message)
        ego
      })
    }
    
    # 4. Simplify GO terms to reduce redundancy using simplify
    ego_simplified <- tryCatch({
      simplify(ego_readable, cutoff = 0.7, by = "p.adjust", select_fun = min)
    }, error = function(e) {
      warning("simplify failed: ", e\$message)
      ego_readable
    })
    
    # Save tabular results
    write.csv(as.data.frame(ego), "enrichGO_results_full.csv", row.names = FALSE)
    write.csv(as.data.frame(ego_simplified), "enrichGO_results_simplified.csv", row.names = FALSE)
    
    # Save RDS objects
    saveRDS(ego, "ego_object.rds")
    saveRDS(ego_simplified, "ego_simplified_object.rds")
    
    # 5. Visualize results
    # Only attempt plotting if there are enriched terms
    if (!is.null(ego_simplified) && nrow(as.data.frame(ego_simplified)) > 0) {
      
      # Barplot
      tryCatch({
        pdf("barplot.pdf", width = 8, height = 6)
        print(barplot(ego_simplified, showCategory = 20))
        dev.off()
      }, error = function(e) {
        warning("Failed to generate barplot: ", e\$message)
      })
    
      # Dotplot
      tryCatch({
        pdf("dotplot.pdf", width = 8, height = 6)
        print(dotplot(ego_simplified, showCategory = 20))
        dev.off()
      }, error = function(e) {
        warning("Failed to generate dotplot: ", e\$message)
      })
    
      # Cnetplot
      tryCatch({
        pdf("cnetplot.pdf", width = 10, height = 8)
        print(cnetplot(ego_simplified, categorySize = "pvalue"))
        dev.off()
      }, error = function(e) {
        warning("Failed to generate cnetplot: ", e\$message)
      })
    
      # Emapplot
      tryCatch({
        # Modern enrichplot requires pairwise_termsim for emapplot
        ego_sim <- enrichplot::pairwise_termsim(ego_simplified)
        pdf("emapplot.pdf", width = 10, height = 8)
        print(emapplot(ego_sim))
        dev.off()
      }, error = function(e) {
        warning("Failed to generate emapplot: ", e\$message)
      })
    
      # Goplot
      tryCatch({
        pdf("goplot.pdf", width = 10, height = 10)
        print(goplot(ego_simplified))
        dev.off()
      }, error = function(e) {
        warning("Failed to generate goplot: ", e\$message)
      })
    
    } else {
      message("No significantly enriched terms found. Skipping visualization plots.")
    }

    writeLines(c(
        '"BIOC_CLUSTERPROFILER_OVER_REPRESENTATION_ANALYSIS":',
        paste0('    clusterProfiler: ', as.character(packageVersion('clusterProfiler')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_over_representation_analysis.csv versions.yml
    """
}

workflow BIOC_CLUSTERPROFILER_OVER_REPRESENTATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_list.txt ] ]

    main:
    BIOC_CLUSTERPROFILER_OVER_REPRESENTATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CLUSTERPROFILER_OVER_REPRESENTATION_ANALYSIS.out.tables
    plots    = BIOC_CLUSTERPROFILER_OVER_REPRESENTATION_ANALYSIS.out.plots
    objects  = BIOC_CLUSTERPROFILER_OVER_REPRESENTATION_ANALYSIS.out.objects
    versions = BIOC_CLUSTERPROFILER_OVER_REPRESENTATION_ANALYSIS.out.versions
}
