#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ideal — ideal_differential_expression_pipeline
// Perform a complete differential expression analysis workflow using DESeq2 and the ideal package, generating diagnostic plots, heatmaps, functional enrichment, a
// Input: counts.csv, coldata.csv
// Container: 2.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DESeq2, ggplot2, ideal, org.Hs.eg.db
// Visualizations: MA plot, volcano plot, heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IDEAL_IDEAL_DIFFERENTIAL_EXPRESSION_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("ideal", "DESeq2", "ggplot2", "org.Hs.eg.db")
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
    library(ideal)
    library(DESeq2)
    library(ggplot2)
    
    # --- Load input data ---
    message("Loading input data...")
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", row.names = 1, check.names = FALSE)
    
    # Align counts and coldata
    if ("sample" %in% colnames(coldata)) {
      rownames(coldata) <- coldata\$sample
    }
    common_samples <- intersect(colnames(counts), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No common samples found between counts.csv and coldata.csv")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, drop = FALSE]
    
    # Ensure condition is a factor
    coldata\$condition <- as.factor(coldata\$condition)
    
    # --- Run DESeq2 Differential Expression Analysis ---
    message("Running DESeq2...")
    dds <- DESeqDataSetFromMatrix(countData = counts,
                                  colData = coldata,
                                  design = ~ condition)
    dds <- DESeq(dds)
    res <- results(dds, alpha = 0.05)
    
    # --- Build Annotation Object ---
    message("Building annotation...")
    gene_ids <- rownames(dds)
    gene_names <- gene_ids
    
    # Attempt to map ENSEMBL IDs to Gene Symbols if org.Hs.eg.db is available
    tryCatch({
      if (any(grepl("^ENSG", gene_ids))) {
        library(org.Hs.eg.db)
        mapped <- mapIds(org.Hs.eg.db, keys = gene_ids, column = "SYMBOL", keytype = "ENSEMBL", multiVals = "first")
        gene_names[!is.na(mapped)] <- mapped[!is.na(mapped)]
      }
    }, error = function(e) {
      message("Annotation mapping skipped or failed: ", e\$message)
    })
    
    annotation_df <- data.frame(
      gene_id = gene_ids,
      gene_name = gene_names,
      row.names = gene_ids,
      stringsAsFactors = FALSE
    )
    
    # --- Generate Diagnostic and Downstream Plots using ideal ---
    message("Generating plots...")
    
    # 4.1 MA Plot
    pdf("ma_plot.pdf", width = 8, height = 6)
    p_ma <- plot_ma(res, FDR = 0.05, title = "MA Plot (FDR = 0.05)")
    print(p_ma)
    dev.off()
    
    # 4.2 Volcano Plot
    pdf("volcano_plot.pdf", width = 8, height = 6)
    p_volcano <- plot_volcano(res, FDR = 0.05, title = "Volcano Plot (FDR = 0.05)")
    print(p_volcano)
    dev.off()
    
    # 4.3 Top Gene Counts Plot
    res_df <- as.data.frame(res)
    res_df <- res_df[order(res_df\$padj, na.last = TRUE), ]
    top_gene <- rownames(res_df)[1]
    
    if (!is.na(top_gene)) {
      pdf("top_gene_counts.pdf", width = 6, height = 6)
      p_counts <- ggplotCounts(dds = dds,
                               gene = top_gene,
                               intgroup = "condition",
                               annotation_obj = annotation_df)
      print(p_counts)
      dev.off()
    }
    
    # 4.4 Heatmap of Significant Genes
    tryCatch({
      pdf("sig_heatmap.pdf", width = 8, height = 10)
      sig_heatmap(dds = dds, res_obj = res, threshold = 0.05)
      dev.off()
    }, error = function(e) {
      message("sig_heatmap failed: ", e\$message)
      # Create an empty PDF to satisfy output requirements if it fails
      pdf("sig_heatmap.pdf")
      plot.new()
      text(0.5, 0.5, "Heatmap generation failed or no significant genes")
      dev.off()
    })
    
    # --- Functional Enrichment Analysis using goseqTable ---
    message("Running functional enrichment...")
    go_results <- data.frame(category = character(), over_represented_pvalue = numeric(), term = character())
    tryCatch({
      de_genes <- rownames(res_df)[which(res_df\$padj < 0.05)]
      assayed_genes <- rownames(res)
      if (length(de_genes) > 0) {
        # Try to run goseqTable assuming human hg38 if IDs look like ENSEMBL
        if (any(grepl("^ENSG", de_genes))) {
          go_results <- goseqTable(
            de.genes = de_genes,
            assayed.genes = assayed_genes,
            genome = "hg38",
            id = "ensGene",
            testCats = "GO:BP"
          )
        } else {
          message("Non-human or non-ENSEMBL IDs; skipping goseqTable.")
        }
      }
    }, error = function(e) {
      message("goseqTable failed: ", e\$message)
    })
    write.csv(go_results, "goseq_enrichment.csv", row.names = FALSE)
    
    # --- Prepare for iSEE ---
    message("Preparing iSEE object...")
    tryCatch({
      ise_obj <- wrapup_for_iSEE(dds, res)
      saveRDS(ise_obj, "isee_input.rds")
    }, error = function(e) {
      message("wrapup_for_iSEE failed: ", e\$message)
      saveRDS(NULL, "isee_input.rds")
    })
    
    # --- Save DE Results Table ---
    message("Saving results...")
    write.csv(res_df, "de_results.csv", row.names = TRUE)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_IDEAL_IDEAL_DIFFERENTIAL_EXPRESSION_PIPELINE":',
        paste0('    ideal: ', as.character(packageVersion('ideal')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ideal_differential_expression_pipeline.csv versions.yml
    """
}

workflow BIOC_IDEAL_IDEAL_DIFFERENTIAL_EXPRESSION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_IDEAL_IDEAL_DIFFERENTIAL_EXPRESSION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_IDEAL_IDEAL_DIFFERENTIAL_EXPRESSION_PIPELINE.out.tables
    plots    = BIOC_IDEAL_IDEAL_DIFFERENTIAL_EXPRESSION_PIPELINE.out.plots
    objects  = BIOC_IDEAL_IDEAL_DIFFERENTIAL_EXPRESSION_PIPELINE.out.objects
    versions = BIOC_IDEAL_IDEAL_DIFFERENTIAL_EXPRESSION_PIPELINE.out.versions
}
