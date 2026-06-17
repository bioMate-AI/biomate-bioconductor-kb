#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ReactomePA — reactome_pathway_enrichment
// Perform Reactome pathway over-representation analysis on a list of Entrez gene IDs and visualize the enriched pathways.
// Input: gene_list.txt
// Container: quay.io/biocontainers/bioconductor-reactomepa:1.54.0--r45hdfd78af_0
// R packages: DOSE, enrichplot, ReactomePA
// Bioconductor: 3.20 | R: 4.4
// Requires: ReactomePA, enrichplot
// Visualizations: dot plot, gene-concept network, enrichment map, enrichment plot, network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read gene IDs
//  * 2. [Core Analysis] Run enrichment analysis using enrichPathway
//  * 3. [Visualization & Output] Visualize results using dotplot, emapplot, or cnetplot

nextflow.enable.dsl = 2

process BIOC_REACTOMEPA_REACTOME_PATHWAY_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("DOSE", "enrichplot", "ReactomePA")
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
    suppressPackageStartupMessages({
      library(ReactomePA)
      library(enrichplot)
    })
    
    # Define input file path
    input_file <- "gene_list.txt"
    
    # Check if the input file exists
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # 1. Read gene IDs
    de_genes <- readLines(input_file)
    
    # Clean the gene list (remove empty lines, trim whitespace, keep unique IDs)
    de_genes <- trimws(de_genes)
    de_genes <- de_genes[de_genes != ""]
    de_genes <- unique(de_genes)
    
    if (length(de_genes) == 0) {
      stop("Error: The gene list is empty.")
    }
    
    # 2. Run enrichment analysis using enrichPathway
    message("Running Reactome pathway enrichment analysis...")
    res <- enrichPathway(gene = de_genes, organism = "human")
    
    # Save the raw enrichment result object
    saveRDS(res, "reactome_enrichment_results.rds")
    
    # Save the enrichment results as a CSV table
    if (!is.null(res)) {
      res_df <- as.data.frame(res)
      write.csv(res_df, "reactome_enrichment_results.csv", row.names = FALSE)
      message(paste("Enrichment analysis complete. Found", nrow(res_df), "enriched pathways."))
    } else {
      write.csv(data.frame(), "reactome_enrichment_results.csv", row.names = FALSE)
      message("Enrichment analysis returned NULL.")
    }
    
    # 3. Visualize results using dotplot, emapplot, and cnetplot
    if (!is.null(res) && nrow(as.data.frame(res)) > 0) {
      message("Generating visualization plots...")
    
      # Generate dotplot
      tryCatch({
        pdf("reactome_dotplot.pdf", width = 8, height = 6)
        print(dotplot(res))
        dev.off()
        message("Saved dotplot to 'reactome_dotplot.pdf'")
      }, error = function(e) {
        warning("Failed to generate dotplot: ", e\$message)
        if (dev.cur() > 1) dev.off()
      })
    
      # Generate emapplot
      # Note: Modern versions of enrichplot require running pairwise_termsim first.
      # We apply it to 'res' so that the exact call 'emapplot(res)' works seamlessly.
      res_sim <- tryCatch({
        enrichplot::pairwise_termsim(res)
      }, error = function(e) {
        res
      })
    
      tryCatch({
        pdf("reactome_emapplot.pdf", width = 8, height = 6)
        print(emapplot(res_sim))
        dev.off()
        message("Saved emapplot to 'reactome_emapplot.pdf'")
      }, error = function(e) {
        warning("Failed to generate emapplot: ", e\$message)
        if (dev.cur() > 1) dev.off()
      })
    
      # Generate cnetplot
      tryCatch({
        pdf("reactome_cnetplot.pdf", width = 10, height = 8)
        print(cnetplot(res))
        dev.off()
        message("Saved cnetplot to 'reactome_cnetplot.pdf'")
      }, error = function(e) {
        warning("Failed to generate cnetplot: ", e\$message)
        if (dev.cur() > 1) dev.off()
      })
    
    } else {
      message("No significant pathways found. Visualization plots were not generated.")
    }

    writeLines(c(
        '"BIOC_REACTOMEPA_REACTOME_PATHWAY_ENRICHMENT":',
        paste0('    ReactomePA: ', as.character(packageVersion('ReactomePA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reactome_pathway_enrichment.csv versions.yml
    """
}

workflow BIOC_REACTOMEPA_REACTOME_PATHWAY_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_list.txt ] ]

    main:
    BIOC_REACTOMEPA_REACTOME_PATHWAY_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_REACTOMEPA_REACTOME_PATHWAY_ENRICHMENT.out.tables
    plots    = BIOC_REACTOMEPA_REACTOME_PATHWAY_ENRICHMENT.out.plots
    objects  = BIOC_REACTOMEPA_REACTOME_PATHWAY_ENRICHMENT.out.objects
    versions = BIOC_REACTOMEPA_REACTOME_PATHWAY_ENRICHMENT.out.versions
}
