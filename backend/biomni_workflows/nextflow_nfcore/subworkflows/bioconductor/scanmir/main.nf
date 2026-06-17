#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scanMiR — scanmir_target_repression_prediction
// Scan custom transcript sequences (derived from gene expression data) for miRNA binding sites using a custom KdModel, aggregate the matches to predict target rep
// Input: counts.csv, coldata.csv
// Container: 1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, GenomicRanges, IRanges, S4Vectors, scanMiR
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCANMIR_SCANMIR_TARGET_REPRESSION_PREDICTION {
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
    .bm_deps <- c("scanMiR", "Biostrings", "S4Vectors", "GenomicRanges")
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
    library(scanMiR)
    library(Biostrings)
    library(S4Vectors)
    library(GenomicRanges)
    
    # ------------------------------------------------------------------------------
    # --- Load Input Data and Generate Mock Transcript Sequences ---
    # ------------------------------------------------------------------------------
    message("Stage 1: Loading expression data and generating transcript sequences...")
    
    # Read counts and coldata
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Ensure counts columns match coldata samples
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching samples found between counts.csv and coldata.csv")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[coldata\$sample %in% common_samples, , drop = FALSE]
    
    # Extract gene IDs
    gene_ids <- rownames(counts)
    n_genes <- length(gene_ids)
    
    # Generate mock transcript sequences for each gene using scanMiR's getRandomSeq
    set.seed(42)
    raw_seqs <- getRandomSeq(length = 1200, n = n_genes)
    seqs <- DNAStringSet(raw_seqs)
    names(seqs) <- gene_ids
    
    # Assign random ORF lengths to demonstrate ORF vs 3'UTR scanning
    mcols(seqs)\$ORF.length <- sample(500:800, n_genes, replace = TRUE)
    
    # ------------------------------------------------------------------------------
    # --- Construct a Custom KdModel ---
    # ------------------------------------------------------------------------------
    message("Stage 2: Constructing custom KdModel...")
    
    # Generate dummy 12-mer affinity data
    kd_data <- dummyKdData()
    
    # Define a mock miRNA sequence (e.g., miR-155-like sequence)
    mir_seq <- "UUAAUGCUAAUCGUGAUAGGGGUU"
    kd_model <- getKdModel(kd = kd_data, mirseq = mir_seq, name = "custom-mock-miR")
    
    # ------------------------------------------------------------------------------
    # --- Scan Transcripts for miRNA Binding Sites ---
    # ------------------------------------------------------------------------------
    message("Stage 3: Scanning transcripts for binding sites...")
    
    # Scan using findSeedMatches
    matches <- findSeedMatches(
      seqs, 
      kd_model, 
      verbose = FALSE, 
      minDist = 7, 
      onlyCanonical = FALSE
    )
    
    # ------------------------------------------------------------------------------
    # --- Aggregate Matches and Predict Repression ---
    # ------------------------------------------------------------------------------
    message("Stage 4: Aggregating matches to predict target repression...")
    
    # Aggregate matches to calculate predicted repression values
    if (length(matches) > 0) {
      agg_matches <- aggregateMatches(matches)
    } else {
      # Fallback empty data frame if no matches found
      agg_matches <- data.frame(
        transcript = gene_ids,
        repression = 0,
        `8mer` = 0,
        `7mer` = 0,
        `6mer` = 0,
        `non-canonical` = 0,
        check.names = FALSE
      )
    }
    
    # ------------------------------------------------------------------------------
    # --- Integrate with Expression Data and Save Results ---
    # ------------------------------------------------------------------------------
    message("Stage 5: Integrating repression predictions with expression data...")
    
    # Calculate average expression and log2 fold change if conditions exist
    avg_expr <- rowMeans(counts)
    expr_df <- data.frame(gene_id = names(avg_expr), avg_expression = avg_expr)
    
    conds <- unique(coldata\$condition)
    if (length(conds) >= 2) {
      s1 <- coldata\$sample[coldata\$condition == conds[1]]
      s2 <- coldata\$sample[coldata\$condition == conds[2]]
      expr1 <- rowMeans(counts[, s1, drop = FALSE])
      expr2 <- rowMeans(counts[, s2, drop = FALSE])
      log2FC <- log2((expr2 + 1) / (expr1 + 1))
      expr_df\$log2FC <- log2FC[expr_df\$gene_id]
    } else {
      expr_df\$log2FC <- 0
    }
    
    # Merge expression and repression data
    merged_data <- merge(expr_df, agg_matches, by.x = "gene_id", by.y = "transcript", all.x = TRUE)
    
    # Replace NA values with 0 for genes with no predicted binding sites
    numeric_cols <- sapply(merged_data, is.numeric)
    merged_data[numeric_cols] <- lapply(merged_data[numeric_cols], function(x) {
      x[is.na(x)] <- 0
      return(x)
    })
    
    # Write main output table
    write.csv(merged_data, "mirna_targets_repression.csv", row.names = FALSE)
    
    # ------------------------------------------------------------------------------
    # --- Visualizations and Diagnostics ---
    # ------------------------------------------------------------------------------
    message("Stage 6: Generating diagnostic plots and alignments...")
    
    # 1. Plot KdModel affinities
    pdf("kd_model_plot.pdf", width = 8, height = 6)
    tryCatch({
      plotKdModel(kd_model, what = "seeds")
    }, error = function(e) {
      plot(1, type = "n", axes = FALSE, xlab = "", ylab = "")
      text(1, 1, paste("Could not plot KdModel:", e\$message))
    })
    dev.off()
    
    # 2. Plot predicted repression vs average expression
    pdf("repression_vs_expression.pdf", width = 8, height = 6)
    plot(
      merged_data\$avg_expression, 
      merged_data\$repression,
      xlab = "Average Expression (Counts)", 
      ylab = "Predicted Repression (log FC)",
      main = "Predicted Repression vs Expression Level",
      pch = 19, 
      col = "darkblue"
    )
    grid()
    dev.off()
    
    # 3. Capture and save the top target alignment
    if (length(matches) > 0) {
      # Find the match with the highest affinity (lowest log_kd)
      best_match_idx <- which.min(matches\$log_kd)
      best_match <- matches[best_match_idx]
      tx_name <- as.character(seqnames(best_match))
      tx_seq <- seqs[tx_name] # Keep as DNAStringSet of length 1
      
      alignment_text <- capture.output(
        viewTargetAlignment(best_match, kd_model, tx_seq)
      )
      writeLines(alignment_text, "top_target_alignment.txt")
    } else {
      writeLines("No matches found to align.", "top_target_alignment.txt")
    }
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_SCANMIR_SCANMIR_TARGET_REPRESSION_PREDICTION":',
        paste0('    scanMiR: ', as.character(packageVersion('scanMiR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scanmir_target_repression_prediction.csv versions.yml
    """
}

workflow BIOC_SCANMIR_SCANMIR_TARGET_REPRESSION_PREDICTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_SCANMIR_SCANMIR_TARGET_REPRESSION_PREDICTION(ch_input)

    emit:
    tables   = BIOC_SCANMIR_SCANMIR_TARGET_REPRESSION_PREDICTION.out.tables
    plots    = BIOC_SCANMIR_SCANMIR_TARGET_REPRESSION_PREDICTION.out.plots
    objects  = BIOC_SCANMIR_SCANMIR_TARGET_REPRESSION_PREDICTION.out.objects
    versions = BIOC_SCANMIR_SCANMIR_TARGET_REPRESSION_PREDICTION.out.versions
}
