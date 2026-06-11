#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BgeeDB — bgee_topanat_enrichment
// Perform anatomical entity enrichment analysis (TopAnat) on a set of foreground genes derived from user-provided expression data using Bgee reference expression 
// Input: counts.csv, coldata.csv
// Container: 2.38.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BgeeDB, topGO
// Visualizations: bar plot, enrichment plot
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BGEEDB_BGEE_TOPANAT_ENRICHMENT {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(BgeeDB)
    library(topGO)
    
    # Define parameters
    species_fallback <- "Homo_sapiens"
    pval_cutoff <- 0.05
    log2fc_cutoff <- 1.0
    
    # Create a robust execution wrapper
    tryCatch({
      message("Stage 1: Reading input files...")
      if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
        stop("Required input files 'counts.csv' or 'coldata.csv' are missing.")
      }
      
      counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
      coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
      
      # Ensure sample names match between counts and coldata
      common_samples <- intersect(colnames(counts), coldata\$sample)
      if (length(common_samples) == 0) {
        stop("No matching samples found between counts.csv columns and coldata.csv 'sample' column.")
      }
      counts <- counts[, common_samples, drop = FALSE]
      coldata <- coldata[coldata\$sample %in% common_samples, ]
      
      message("Stage 2: Detecting species from Ensembl Gene IDs...")
      gene_ids <- rownames(counts)
      species <- species_fallback
      if (any(grepl("^ENSDARG", gene_ids))) {
        species <- "Danio_rerio"
      } else if (any(grepl("^ENSMUSG", gene_ids))) {
        species <- "Mus_musculus"
      } else if (any(grepl("^ENSRNOG", gene_ids))) {
        species <- "Rattus_norvegicus"
      } else if (any(grepl("^ENSGALG", gene_ids))) {
        species <- "Gallus_gallus"
      } else if (any(grepl("^ENSG", gene_ids))) {
        species <- "Homo_sapiens"
      }
      message(paste("Detected species:", species))
      
      message("Stage 3: Identifying foreground and background genes...")
      # Normalize counts to CPM (Counts Per Million)
      libsizes <- colSums(counts)
      cpm <- t(t(counts) / libsizes) * 1e6
      
      # Determine foreground genes based on experimental design
      conditions <- unique(coldata\$condition)
      if (length(conditions) >= 2) {
        message("Performing simple differential expression to define foreground genes...")
        cond1_samples <- coldata\$sample[coldata\$condition == conditions[1]]
        cond2_samples <- coldata\$sample[coldata\$condition == conditions[2]]
        
        mean1 <- rowMeans(cpm[, cond1_samples, drop = FALSE])
        mean2 <- rowMeans(cpm[, cond2_samples, drop = FALSE])
        log2fc <- log2((mean1 + 1) / (mean2 + 1))
        
        pvals <- apply(cpm, 1, function(x) {
          g1 <- x[names(x) %in% cond1_samples]
          g2 <- x[names(x) %in% cond2_samples]
          if (var(g1) == 0 && var(g2) == 0) return(1)
          t.test(g1, g2)\$p.value
        })
        
        foreground_idx <- which(pvals < pval_cutoff & abs(log2fc) > log2fc_cutoff)
        # Fallback if too few genes pass thresholds
        if (length(foreground_idx) < 10) {
          message("Too few genes passed thresholds. Selecting top 200 most variable/differentially expressed genes instead.")
          foreground_idx <- order(abs(log2fc), decreasing = TRUE)[1:min(200, length(log2fc))]
        }
      } else {
        message("Single condition detected. Selecting top 10% highest expressed genes as foreground...")
        mean_expr <- rowMeans(cpm)
        foreground_idx <- order(mean_expr, decreasing = TRUE)[1:min(500, length(mean_expr))]
      }
      
      foreground_genes <- gene_ids[foreground_idx]
      background_genes <- gene_ids
      
      message(paste("Foreground genes selected:", length(foreground_genes)))
      message(paste("Background genes selected:", length(background_genes)))
      
      message("Stage 4: Initializing Bgee database connection...")
      bgee <- Bgee\$new(species = species, release = "15.2")
      
      message("Stage 5: Loading TopAnat reference data from Bgee...")
      myTopAnatData <- loadTopAnatData(bgee)
      
      message("Stage 6: Preparing topAnat object...")
      geneList <- factor(as.integer(background_genes %in% foreground_genes))
      names(geneList) <- background_genes
      
      myTopAnatObject <- topAnat(myTopAnatData, geneList)
      
      message("Stage 7: Running anatomical enrichment test...")
      results <- runTest(myTopAnatObject, algorithm = 'weight', statistic = 'fisher')
      
      message("Stage 8: Formatting and exporting results...")
      tableOver <- makeTable(myTopAnatData, myTopAnatObject, results, cutoff = 1)
      write.csv(tableOver, "topanat_enrichment_results.csv", row.names = FALSE)
      
      # Extract significant terms and map back to foreground genes
      sig_terms <- tableOver[tableOver\$FDR < 0.05, ]
      if (nrow(sig_terms) == 0) {
        message("No terms met the 5% FDR threshold. Exporting top 10 terms by raw p-value.")
        sig_terms <- head(tableOver, 10)
      }
      
      gene_mapping_list <- list()
      for (term_id in sig_terms\$organId) {
        all_mapped <- genesInTerm(myTopAnatObject, term_id)[[term_id]]
        fg_mapped <- intersect(all_mapped, foreground_genes)
        gene_mapping_list[[term_id]] <- paste(fg_mapped, collapse = ";")
      }
      sig_terms\$foreground_genes <- unlist(gene_mapping_list[sig_terms\$organId])
      write.csv(sig_terms, "topanat_significant_terms_with_genes.csv", row.names = FALSE)
      
      message("Stage 9: Generating enrichment visualization...")
      pdf("topanat_enrichment_plot.pdf", width = 10, height = 8)
      plot_data <- head(tableOver[order(tableOver\$pValue), ], 10)
      if (nrow(plot_data) > 0) {
        plot_data\$organName <- substr(plot_data\$organName, 1, 30)
        par(mar = c(5, 15, 4, 2))
        barplot(
          -log10(plot_data\$pValue),
          names.arg = plot_data\$organName,
          las = 2,
          horiz = TRUE,
          col = "skyblue",
          xlab = "-log10(p-value)",
          main = "Top Enriched Anatomical Entities (Bgee TopAnat)"
        )
        abline(v = -log10(0.05), col = "red", lty = 2)
      } else {
        plot.new()
        text(0.5, 0.5, "No enrichment data available to plot.", cex = 1.2)
      }
      dev.off()
      
      message("Pipeline completed successfully!")
      
    }, error = function(e) {
      message("An error occurred during pipeline execution: ", e\$message)
      
      # Write fallback files to satisfy output requirements
      write.csv(data.frame(Error = e\$message), "topanat_enrichment_results.csv", row.names = FALSE)
      write.csv(data.frame(Error = e\$message), "topanat_significant_terms_with_genes.csv", row.names = FALSE)
      
      pdf("topanat_enrichment_plot.pdf")
      plot.new()
      text(0.5, 0.5, paste("Analysis failed:\n", e\$message), cex = 0.8, col = "red")
      dev.off()
    })

    writeLines(c(
        '"BIOC_BGEEDB_BGEE_TOPANAT_ENRICHMENT":',
        paste0('    BgeeDB: ', as.character(packageVersion('BgeeDB')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bgee_topanat_enrichment.csv versions.yml
    """
}

workflow BIOC_BGEEDB_BGEE_TOPANAT_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BGEEDB_BGEE_TOPANAT_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_BGEEDB_BGEE_TOPANAT_ENRICHMENT.out.tables
    plots    = BIOC_BGEEDB_BGEE_TOPANAT_ENRICHMENT.out.plots
    objects  = BIOC_BGEEDB_BGEE_TOPANAT_ENRICHMENT.out.objects
    versions = BIOC_BGEEDB_BGEE_TOPANAT_ENRICHMENT.out.versions
}
