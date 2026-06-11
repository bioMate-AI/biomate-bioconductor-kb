#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EBcoexpress — ebcoexpress_differential_coexpression
// Perform differential co-expression analysis at the gene-pair level using an Empirical Bayesian approach to identify differentially co-expressed gene pairs and h
// Input: counts.csv, coldata.csv
// Container: 1.54.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EBcoexpress
// Visualizations: network plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EBCOEXPRESS_EBCOEXPRESS_DIFFERENTIAL_COEXPRESSION {
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
    
    # --- Load libraries and input data ---
    library(EBcoexpress)
    
    # Read expression matrix and sample metadata
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Set row names using the gene_id column
    if ("gene_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$gene_id
      counts_df\$gene_id <- NULL
    } else {
      rownames(counts_df) <- counts_df[, 1]
      counts_df <- counts_df[, -1]
    }
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(counts_df), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("Error: No matching samples found between counts.csv and coldata.csv")
    }
    counts_df <- counts_df[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # Convert conditions to a 1 and 2 numeric vector as required by EBcoexpress
    conditions <- as.numeric(as.factor(coldata\$condition))
    if (length(unique(conditions)) != 2) {
      # Force into two groups if there are not exactly 2 conditions
      conditions <- ifelse(conditions == unique(conditions)[1], 1, 2)
    }
    
    # --- Preprocessing and Filtering ---
    # Differential co-expression is highly sensitive to low-variance genes.
    # Since pairwise analysis scales quadratically, we filter to the top N most variable genes.
    gene_vars <- apply(counts_df, 1, var)
    counts_df <- counts_df[gene_vars > 0 & !is.na(gene_vars), ]
    
    max_genes <- 100
    num_genes_to_keep <- min(max_genes, nrow(counts_df))
    top_genes <- names(sort(apply(counts_df, 1, var), decreasing = TRUE))[1:num_genes_to_keep]
    expr_matrix <- as.matrix(counts_df[top_genes, ])
    
    message(paste("Running EBcoexpress on", num_genes_to_keep, "genes, yielding", 
                  (num_genes_to_keep * (num_genes_to_keep - 1)) / 2, "pairs."))
    
    # --- Co-expression Similarity Matrix Generation ---
    # Compute the correlation/similarity matrix D using Biweight Midcorrelation (BWMC)
    D <- makeMyD(expr_matrix, conditions, useBWMC = TRUE)
    
    # --- Hyperparameter Initialization and EM Run ---
    set.seed(42)
    initHP <- initializeHP(D, conditions)
    
    # Define patterns: "1,1" represents equal co-expression (EC), "1,2" represents differential co-expression (DC)
    tinyPat <- ebPatterns(c("1,1", "1,2"))
    
    # Run the recommended One-Step EM algorithm
    oout <- ebCoexpressOneStep(D, conditions, tinyPat, initHP)
    
    # --- Posterior Probabilities & FDR Control ---
    prob_EC <- oout\$POSTPROBS[, 1]
    prob_DC <- 1 - prob_EC
    
    # Determine critical threshold for the target FDR (0.05)
    fdr_threshold <- 0.05
    crit_val <- tryCatch({
      crit.fun(prob_EC, fdr_threshold)
    }, error = function(e) {
      message("FDR threshold estimation failed; falling back to hard threshold of 0.95")
      0.95
    })
    
    # Format and save the gene-pair results
    results_df <- data.frame(
      Gene_Pair = names(prob_DC),
      Prob_EC = prob_EC,
      Prob_DC = prob_DC,
      Significant_DC = prob_DC >= crit_val,
      stringsAsFactors = FALSE
    )
    results_df <- results_df[order(results_df\$Prob_DC, decreasing = TRUE), ]
    write.csv(results_df, "dc_pairs.csv", row.names = FALSE)
    
    # --- Gene Ranking (Hubness) ---
    # Rank genes by their overall differential co-expression hubness
    hubs <- rankMyGenes(oout)
    hubs_df <- data.frame(
      Gene = names(hubs),
      Hub_Score = as.numeric(hubs),
      stringsAsFactors = FALSE
    )
    hubs_df <- hubs_df[order(hubs_df\$Hub_Score, decreasing = TRUE), ]
    write.csv(hubs_df, "hub_genes.csv", row.names = FALSE)
    
    # --- Diagnostics and Visualizations ---
    # 1. Prior Diagnostics Plot
    pdf("ebcoexpress_diagnostics.pdf", width = 10, height = 10)
    par(mfrow = c(2, 2))
    tryCatch({
      priorDiagnostic(D, conditions, oout, 1)
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Diagnostic Condition 1 failed:\n", e\$message), cex = 0.8)
    })
    tryCatch({
      priorDiagnostic(D, conditions, oout, 2)
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Diagnostic Condition 2 failed:\n", e\$message), cex = 0.8)
    })
    dev.off()
    
    # 2. Network Visualizations for Top Hub Genes
    twentyGeneNames <- head(hubs_df\$Gene, 20)
    if (length(twentyGeneNames) < 2) {
      twentyGeneNames <- rownames(expr_matrix)[1:min(20, nrow(expr_matrix))]
    }
    
    pdf("ebcoexpress_networks.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    tryCatch({
      showNetwork(twentyGeneNames, D, condFocus = 1, gsep = "~",
                  layout = "kamada.kawai", seed = 5, vertex.shape = "circle",
                  vertex.label.cex = 0.8, vertex.color = "lightblue", edge.width = 2,
                  vertex.frame.color = "black", vertex.size = 20,
                  vertex.label.color = "black", vertex.label.family = "sans")
      title("Condition 1 Network")
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Network Plot Condition 1 failed:\n", e\$message), cex = 0.8)
    })
    
    tryCatch({
      showNetwork(twentyGeneNames, D, condFocus = 2, gsep = "~",
                  layout = "kamada.kawai", seed = 5, vertex.shape = "circle",
                  vertex.label.cex = 0.8, vertex.color = "lightpink", edge.width = 2,
                  vertex.frame.color = "black", vertex.size = 20,
                  vertex.label.color = "black", vertex.label.family = "sans")
      title("Condition 2 Network")
    }, error = function(e) {
      plot.new()
      text(0.5, 0.5, paste("Network Plot Condition 2 failed:\n", e\$message), cex = 0.8)
    })
    dev.off()
    
    # 3. Scatter Plot of the Top DC Pair
    pdf("ebcoexpress_top_pair.pdf", width = 6, height = 6)
    if (nrow(results_df) > 0) {
      top_pair <- results_df\$Gene_Pair[1]
      tryCatch({
        showPair(top_pair, expr_matrix, conditions, pch = 20, main = paste("Top DC Pair:", top_pair))
      }, error = function(e) {
        plot.new()
        text(0.5, 0.5, paste("ShowPair failed:\n", e\$message), cex = 0.8)
      })
    } else {
      plot.new()
      text(0.5, 0.5, "No pairs available to plot", cex = 0.8)
    }
    dev.off()
    
    message("EBcoexpress pipeline completed successfully.")

    writeLines(c(
        '"BIOC_EBCOEXPRESS_EBCOEXPRESS_DIFFERENTIAL_COEXPRESSION":',
        paste0('    EBcoexpress: ', as.character(packageVersion('EBcoexpress')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ebcoexpress_differential_coexpression.csv versions.yml
    """
}

workflow BIOC_EBCOEXPRESS_EBCOEXPRESS_DIFFERENTIAL_COEXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_EBCOEXPRESS_EBCOEXPRESS_DIFFERENTIAL_COEXPRESSION(ch_input)

    emit:
    tables   = BIOC_EBCOEXPRESS_EBCOEXPRESS_DIFFERENTIAL_COEXPRESSION.out.tables
    plots    = BIOC_EBCOEXPRESS_EBCOEXPRESS_DIFFERENTIAL_COEXPRESSION.out.plots
    objects  = BIOC_EBCOEXPRESS_EBCOEXPRESS_DIFFERENTIAL_COEXPRESSION.out.objects
    versions = BIOC_EBCOEXPRESS_EBCOEXPRESS_DIFFERENTIAL_COEXPRESSION.out.versions
}
