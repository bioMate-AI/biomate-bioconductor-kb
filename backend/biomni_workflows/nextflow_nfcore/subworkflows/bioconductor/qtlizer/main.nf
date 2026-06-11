#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Qtlizer — qtl_annotation_pipeline
// Identify differentially expressed or highly variable genes from expression data and annotate them with quantitative trait loci (QTLs) using Qtlizer.
// Input: counts.csv, coldata.csv
// Container: 1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, Qtlizer
// Visualizations: bar plot
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE {
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
    library(Qtlizer)
    library(GenomicRanges)
    
    # ==========================================
    # Stage 1: Load and Preprocess Input Data
    # ==========================================
    
    message("Loading input datasets...")
    # Read counts matrix
    counts_raw <- read.csv("counts.csv", check.names = FALSE, stringsAsFactors = FALSE)
    
    # Handle gene_id column or row names
    if ("gene_id" %in% colnames(counts_raw)) {
      rownames(counts_raw) <- counts_raw\$gene_id
      counts_raw\$gene_id <- NULL
    } else if (is.character(counts_raw[, 1])) {
      rownames(counts_raw) <- counts_raw[, 1]
      counts_raw <- counts_raw[, -1, drop = FALSE]
    }
    
    # Clean gene identifiers (e.g., strip Ensembl version suffixes like .13)
    clean_genes <- sub("\\\\..*\$", "", rownames(counts_raw))
    rownames(counts_raw) <- clean_genes
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between counts and metadata
    common_samples <- intersect(colnames(counts_raw), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("Error: No matching samples found between counts.csv and coldata.csv")
    }
    
    counts <- counts_raw[, common_samples, drop = FALSE]
    coldata <- coldata[coldata\$sample %in% common_samples, ]
    
    # ==========================================
    # Stage 2: Identify Key Genes for QTL Query
    # ==========================================
    
    message("Normalizing expression data...")
    # Simple CPM normalization
    libsizes <- colSums(counts)
    libsizes[libsizes == 0] <- 1 # Avoid division by zero
    cpm <- t(t(counts) / libsizes) * 1e6
    log2_cpm <- log2(cpm + 1)
    
    # Find differentially expressed or highly variable genes
    conditions <- unique(coldata\$condition)
    if (length(conditions) >= 2) {
      message("Performing two-group comparison to identify candidate genes...")
      group1 <- coldata\$sample[coldata\$condition == conditions[1]]
      group2 <- coldata\$sample[coldata\$condition == conditions[2]]
      
      p_values <- apply(log2_cpm, 1, function(x) {
        tryCatch({
          t.test(x[group1], x[group2])\$p.value
        }, error = function(e) NA)
      })
      
      mean_g1 <- rowMeans(log2_cpm[, group1, drop = FALSE])
      mean_g2 <- rowMeans(log2_cpm[, group2, drop = FALSE])
      log2_fc <- mean_g2 - mean_g1
      
      stats_df <- data.frame(
        gene = rownames(log2_cpm),
        log2FC = log2_fc,
        pvalue = p_values,
        stringsAsFactors = FALSE
      )
      stats_df <- stats_df[!is.na(stats_df\$pvalue), ]
      stats_df <- stats_df[order(stats_df\$pvalue), ]
    } else {
      message("Single condition detected. Selecting highly variable genes...")
      vars <- apply(log2_cpm, 1, var)
      stats_df <- data.frame(
        gene = rownames(log2_cpm),
        variance = vars,
        stringsAsFactors = FALSE
      )
      stats_df <- stats_df[order(stats_df\$variance, decreasing = TRUE), ]
    }
    
    # Select top 15 genes to query to avoid API rate limits/timeouts
    top_genes <- head(stats_df\$gene, 15)
    
    # ==========================================
    # Stage 3: Query Qtlizer Database
    # ==========================================
    
    qtl_df <- data.frame()
    qtl_gr <- GRanges()
    
    if (length(top_genes) > 0) {
      message("Querying Qtlizer for top candidate genes: ", paste(top_genes, collapse = ", "))
      
      # Query as DataFrame
      qtl_df <- tryCatch({
        get_qtls(top_genes, return_obj = "dataframe")
      }, error = function(e) {
        warning("Qtlizer DataFrame query failed: ", e\$message)
        NULL
      })
      
      # Query as GRanges
      qtl_gr <- tryCatch({
        get_qtls(top_genes, return_obj = "granges", ref_version = "hg38")
      }, error = function(e) {
        warning("Qtlizer GRanges query failed: ", e\$message)
        NULL
      })
    } else {
      warning("No candidate genes found to query.")
    }
    
    # ==========================================
    # Stage 4: Post-processing and Export
    # ==========================================
    
    # Ensure output data frame is valid and write to CSV
    if (is.null(qtl_df) || nrow(qtl_df) == 0) {
      message("No QTL annotations returned. Creating empty placeholder output.")
      qtl_df <- data.frame(
        query_type = character(), query_term = character(), sentinel = character(),
        chr = character(), var_pos_hg19 = integer(), var_pos_hg38 = integer(),
        type = character(), gene = character(), ensgid = character(),
        colocalization = character(), distance = numeric(), tissue = character(),
        p = numeric(), sign_info = character(), beta = numeric(),
        source = character(), pmid = character(), is_sign = logical()
      )
    } else {
      # Print metadata comments from the query
      meta_info <- comment(qtl_df)
      if (!is.null(meta_info)) {
        message("Qtlizer Metadata:")
        cat(meta_info, sep = "\n")
      }
    }
    write.csv(qtl_df, "qtl_annotations.csv", row.names = FALSE)
    
    # Process and write GRanges output
    if (!is.null(qtl_gr) && length(qtl_gr) > 0) {
      gr_df <- as.data.frame(qtl_gr)
      write.csv(gr_df, "qtl_ranges.csv", row.names = FALSE)
    } else {
      write.csv(data.frame(message = "No genomic ranges returned or query failed"), 
                "qtl_ranges.csv", row.names = FALSE)
    }
    
    # ==========================================
    # Stage 5: Diagnostic Visualizations
    # ==========================================
    
    pdf("qtl_summary_plots.pdf", width = 8, height = 6)
    
    if (nrow(qtl_df) > 0 && "tissue" %in% colnames(qtl_df)) {
      # Plot 1: Distribution of QTLs across tissues
      tissue_counts <- table(qtl_df\$tissue)
      tissue_counts <- sort(tissue_counts, decreasing = TRUE)
      top_tissues <- head(tissue_counts, 10)
      
      if (length(top_tissues) > 0) {
        op <- par(mar = c(5, 15, 4, 2))
        barplot(top_tissues, las = 2, horiz = TRUE, col = "skyblue",
                main = "Top 10 Tissues with Associated QTLs",
                xlab = "Number of QTLs")
        par(op)
      }
      
      # Plot 2: P-value distribution of retrieved QTLs
      if ("p" %in% colnames(qtl_df)) {
        p_vals <- as.numeric(qtl_df\$p)
        p_vals <- p_vals[!is.na(p_vals)]
        if (length(p_vals) > 0) {
          hist(-log10(p_vals), col = "coral", border = "white",
               main = "Significance Distribution of Associated QTLs",
               xlab = "-log10(P-value)", ylab = "Frequency")
        }
      }
    } else {
      # Fallback empty plot if no data
      plot.new()
      text(0.5, 0.5, "No QTL data available to plot", cex = 1.2)
    }
    
    dev.off()
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE":',
        paste0('    Qtlizer: ', as.character(packageVersion('Qtlizer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qtl_annotation_pipeline.csv versions.yml
    """
}

workflow BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE.out.tables
    plots    = BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE.out.plots
    objects  = BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE.out.objects
    versions = BIOC_QTLIZER_QTL_ANNOTATION_PIPELINE.out.versions
}
