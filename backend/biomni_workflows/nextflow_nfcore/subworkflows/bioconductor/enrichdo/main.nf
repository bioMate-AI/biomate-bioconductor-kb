#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EnrichDO — enrichdo_disease_ontology_analysis
// Perform Disease Ontology (DO) enrichment analysis on genomic regions by mapping them to Entrez IDs and applying the global double-weighted iterative model.
// Input: regions.bed, coldata.csv
// Container: 1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EnrichDO, GenomicRanges, rtracklayer
// Visualizations: enrichment plot, heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENRICHDO_ENRICHDO_DISEASE_ONTOLOGY_ANALYSIS {
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
    .bm_deps <- c("rtracklayer", "GenomicRanges", "EnrichDO")
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
    
    # --- Load required libraries ---
    library(rtracklayer)
    library(GenomicRanges)
    library(EnrichDO)
    
    # --- Import and preprocess genomic intervals ---
    message("Importing genomic regions from BED file...")
    gr <- rtracklayer::import("regions.bed")
    
    # Extract gene identifiers from the 'name' column of the BED file
    # EnrichDO requires NCBI Entrez IDs (integers)
    interest_genes <- as.character(mcols(gr)\$name)
    interest_genes <- as.integer(interest_genes)
    interest_genes <- unique(interest_genes[!is.na(interest_genes)])
    
    if (length(interest_genes) == 0) {
      stop("Error: No valid integer Entrez IDs found in the 'name' column of regions.bed.")
    }
    
    message(paste("Successfully loaded", length(interest_genes), "unique Entrez IDs for enrichment analysis."))
    
    # --- Disease Ontology Enrichment Analysis ---
    message("Running double-weighted Disease Ontology enrichment analysis...")
    weighted_res <- doEnrich(
      interestGenes = interest_genes,
      test = "fisherTest",
      method = "holm",
      m = 1,
      minGsize = 10,
      maxGsize = 2000,
      delta = 0.05,
      penalize = TRUE,
      traditional = FALSE
    )
    
    # --- Extract and Export Results ---
    message("Extracting and writing results...")
    # Extract detailed results
    detail_res <- viewDetailResult(weighted_res)
    write.csv(detail_res, "enrichdo_detail_results.csv", row.names = FALSE)
    
    # Extract summary results
    summary_res <- viewSummaryResult(weighted_res)
    write.csv(summary_res, "enrichdo_summary_results.csv", row.names = FALSE)
    
    # Write standard text output
    writeResult(
      EnrichResult = weighted_res,
      file = "enrichdo_results.txt",
      Q = 1,
      P = 1
    )
    
    # --- Visualization of Enrichment Results ---
    message("Generating diagnostic and enrichment plots...")
    
    # 1. Bar Graph
    pdf("enrichdo_bar_graph.pdf", width = 8, height = 6)
    tryCatch({
      drawBarGraph(EnrichResult = weighted_res, n = 10, delta = 0.05)
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Bar Graph failed:\n", e\$message), cex = 0.8)
    })
    dev.off()
    
    # 2. Point Graph (Bubble Plot)
    pdf("enrichdo_point_graph.pdf", width = 8, height = 6)
    tryCatch({
      drawPointGraph(EnrichResult = weighted_res, n = 10, delta = 0.05)
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Point Graph failed:\n", e\$message), cex = 0.8)
    })
    dev.off()
    
    # 3. GraphViz DAG Tree Plot
    pdf("enrichdo_dag_graph.pdf", width = 8, height = 6)
    tryCatch({
      drawGraphViz(
        EnrichResult = weighted_res,
        n = 5,
        numview = FALSE,
        pview = FALSE,
        labelfontsize = 12
      )
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("DAG Graph failed:\n", e\$message), cex = 0.8)
    })
    dev.off()
    
    # 4. Heatmap of top DO terms and genes
    pdf("enrichdo_heatmap.pdf", width = 8, height = 6)
    tryCatch({
      drawHeatmap(
        interestGenes = interest_genes,
        EnrichResult = weighted_res,
        gene_n = 10,
        fontsize_row = 8
      )
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Heatmap failed:\n", e\$message), cex = 0.8)
    })
    dev.off()
    
    # --- Convenient Drawing from Saved Text File (Demonstrating ---
    message("Demonstrating convDraw functionality from saved text results...")
    tryCatch({
      saved_data <- read.delim("enrichdo_results.txt")
      if (nrow(saved_data) > 0) {
        enrich_conv <- convDraw(resultDO = saved_data)
        
        pdf("enrichdo_conv_bar_graph.pdf", width = 8, height = 6)
        drawBarGraph(enrich = enrich_conv, delta = 0.05)
        dev.off()
      } else {
        # Create empty fallback PDF if no results were written
        pdf("enrichdo_conv_bar_graph.pdf", width = 8, height = 6)
        plot.new()
        text(0.5, 0.5, "No enrichment results available to draw.")
        dev.off()
      }
    }, error = function(e) {
      pdf("enrichdo_conv_bar_graph.pdf", width = 8, height = 6)
      plot.new()
      text(0.5, 0.5, paste("convDraw workflow failed:\n", e\$message), cex = 0.8)
      dev.off()
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_ENRICHDO_ENRICHDO_DISEASE_ONTOLOGY_ANALYSIS":',
        paste0('    EnrichDO: ', as.character(packageVersion('EnrichDO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enrichdo_disease_ontology_analysis.csv versions.yml
    """
}

workflow BIOC_ENRICHDO_ENRICHDO_DISEASE_ONTOLOGY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ENRICHDO_ENRICHDO_DISEASE_ONTOLOGY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ENRICHDO_ENRICHDO_DISEASE_ONTOLOGY_ANALYSIS.out.tables
    plots    = BIOC_ENRICHDO_ENRICHDO_DISEASE_ONTOLOGY_ANALYSIS.out.plots
    objects  = BIOC_ENRICHDO_ENRICHDO_DISEASE_ONTOLOGY_ANALYSIS.out.objects
    versions = BIOC_ENRICHDO_ENRICHDO_DISEASE_ONTOLOGY_ANALYSIS.out.versions
}
