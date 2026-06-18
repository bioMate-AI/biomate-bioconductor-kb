#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bugsigdbr — bugsigdb_enrichment
// Perform differential abundance analysis on user metagenomic data and test for enrichment against ontology-filtered BugSigDB microbial signatures.
// Input: abundance.csv, coldata.csv
// Container: 1.16.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: bugsigdbr
// Visualizations: bar plot, enrichment plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUGSIGDBR_BUGSIGDB_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

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
    .bm_deps <- c("bugsigdbr")
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
    library(bugsigdbr)
    
    # ==========================================
    # --- Read and Align Input Datasets ---
    # ==========================================
    message("Reading input datasets...")
    abundance <- read.csv("abundance.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between abundance matrix and coldata
    common_samples <- intersect(colnames(abundance), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("Error: No common samples found between abundance.csv and coldata.csv")
    }
    abundance <- abundance[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # ==========================================
    # --- Identify User's Microbial Signature ---
    # ==========================================
    message("Performing differential abundance analysis...")
    groups <- as.factor(coldata\$group)
    group_levels <- levels(groups)
    if (length(group_levels) < 2) {
      stop("Error: 'group' column in coldata must contain at least 2 distinct groups.")
    }
    
    # Perform Wilcoxon rank-sum test for each taxon
    p_values <- apply(abundance, 1, function(x) {
      tryCatch({
        wilcox.test(x ~ groups)\$p.value
      }, error = function(e) NA)
    })
    
    # Calculate log2 fold change (Group 2 vs Group 1)
    mean_g1 <- rowMeans(abundance[, groups == group_levels[1], drop = FALSE])
    mean_g2 <- rowMeans(abundance[, groups == group_levels[2], drop = FALSE])
    log_fc <- log2((mean_g2 + 1) / (mean_g1 + 1))
    
    stats_df <- data.frame(
      taxon = rownames(abundance),
      p_value = p_values,
      log_fc = log_fc,
      stringsAsFactors = FALSE
    )
    stats_df <- stats_df[!is.na(stats_df\$p_value), ]
    
    # Define user signature (significant taxa)
    # Fallback to top 50 taxa by p-value if too few are strictly significant
    sig_taxa_df <- stats_df[stats_df\$p_value < 0.05, ]
    if (nrow(sig_taxa_df) < 5) {
      message("Fewer than 5 taxa met the p-value threshold. Selecting top 50 taxa instead.")
      sig_taxa_df <- stats_df[order(stats_df\$p_value), ][1:min(50, nrow(stats_df)), ]
    }
    user_sig <- sig_taxa_df\$taxon
    
    # ==========================================
    # --- Import and Filter BugSigDB ---
    # ==========================================
    message("Importing BugSigDB database...")
    bsdb <- importBugSigDB()
    
    message("Loading UBERON ontology...")
    uberon <- getOntology("uberon")
    
    message("Filtering BugSigDB signatures by UBERON body site ontology...")
    # Subset to signatures associated with the digestive system
    bsdb_filtered <- subsetByOntology(
      bsdb, 
      column = "Body site", 
      term = "digestive system", 
      ontology = uberon
    )
    
    # ==========================================
    # --- Extract Signatures ---
    # ==========================================
    # Determine if user taxa are NCBI IDs (numeric) or Taxon Names (character)
    is_numeric_id <- all(!is.na(suppressWarnings(as.numeric(user_sig))))
    
    if (is_numeric_id) {
      message("Detected NCBI Taxon IDs. Extracting NCBI signatures...")
      bsdb_sigs <- getSignatures(bsdb_filtered, tax.id.type = "ncbi")
    } else {
      message("Detected Taxon Names. Extracting Taxon Name signatures...")
      bsdb_sigs <- getSignatures(bsdb_filtered, tax.id.type = "taxname")
    }
    
    # ==========================================
    # --- Hypergeometric Enrichment Analysis ---
    # ==========================================
    message("Performing hypergeometric enrichment analysis...")
    background_taxa <- rownames(abundance)
    N <- length(background_taxa) # Background size
    
    enrichment_results <- lapply(names(bsdb_sigs), function(sig_name) {
      sig_taxa <- bsdb_sigs[[sig_name]]
      
      # Intersect signature with our background
      sig_in_bg <- intersect(sig_taxa, background_taxa)
      M <- length(sig_in_bg) # Number of signature taxa in background
      
      if (M == 0) return(NULL)
      
      # Intersect user signature with the signature in background
      overlap_taxa <- intersect(user_sig, sig_in_bg)
      k <- length(overlap_taxa) # Overlap size
      n <- length(intersect(user_sig, background_taxa)) # User signature size in background
      
      # Hypergeometric test (one-tailed over-representation)
      p_val <- phyper(k - 1, M, N - M, n, lower.tail = FALSE)
      
      data.frame(
        Signature = sig_name,
        Overlap_Size = k,
        Signature_Size_In_BG = M,
        User_Sig_Size_In_BG = n,
        P_Value = p_val,
        Overlapping_Taxa = paste(overlap_taxa, collapse = "; "),
        stringsAsFactors = FALSE
      )
    })
    
    enrichment_df <- do.call(rbind, enrichment_results)
    
    if (!is.null(enrichment_df) && nrow(enrichment_df) > 0) {
      enrichment_df\$Adjusted_P_Value <- p.adjust(enrichment_df\$P_Value, method = "BH")
      enrichment_df <- enrichment_df[order(enrichment_df\$P_Value), ]
    } else {
      # Fallback empty dataframe if no overlaps exist
      enrichment_df <- data.frame(
        Signature = character(),
        Overlap_Size = numeric(),
        Signature_Size_In_BG = numeric(),
        User_Sig_Size_In_BG = numeric(),
        P_Value = numeric(),
        Adjusted_P_Value = numeric(),
        Overlapping_Taxa = character(),
        stringsAsFactors = FALSE
      )
    }
    
    # Write enrichment results to CSV
    write.csv(enrichment_df, "enrichment_results.csv", row.names = FALSE)
    
    # ==========================================
    # --- Export Filtered Signatures to GMT ---
    # ==========================================
    message("Writing filtered BugSigDB signatures to GMT file...")
    writeGMT(bsdb_sigs, gmt.file = "bugsigdb_filtered.gmt")
    
    # ==========================================
    # --- Visualization ---
    # ==========================================
    message("Generating enrichment plot...")
    pdf("enrichment_plot.pdf", width = 10, height = 6)
    
    if (nrow(enrichment_df) > 0) {
      # Plot top 15 enriched signatures
      top_df <- head(enrichment_df, 15)
      top_df\$log10_p <- -log10(top_df\$P_Value)
      
      # Order by significance for horizontal barplot
      top_df <- top_df[order(top_df\$log10_p), ]
      
      # Truncate long signature names for plotting
      clean_names <- sapply(top_df\$Signature, function(x) {
        if (nchar(x) > 50) paste0(substr(x, 1, 47), "...") else x
      })
      
      par(mar = c(5, 22, 4, 2))
      barplot(
        top_df\$log10_p,
        names.arg = clean_names,
        las = 1,
        horiz = TRUE,
        col = "skyblue",
        xlab = "-log10(P-value)",
        main = "Top Enriched BugSigDB Signatures (Digestive System)"
      )
      abline(v = -log10(0.05), col = "red", lty = 2)
    } else {
      plot.new()
      text(0.5, 0.5, "No overlapping signatures found to plot.", cex = 1.2)
    }
    
    dev.off()
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_BUGSIGDBR_BUGSIGDB_ENRICHMENT":',
        paste0('    bugsigdbr: ', as.character(packageVersion('bugsigdbr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bugsigdb_enrichment.csv versions.yml
    """
}

workflow BIOC_BUGSIGDBR_BUGSIGDB_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BUGSIGDBR_BUGSIGDB_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_BUGSIGDBR_BUGSIGDB_ENRICHMENT.out.tables
    plots    = BIOC_BUGSIGDBR_BUGSIGDB_ENRICHMENT.out.plots
    objects  = BIOC_BUGSIGDBR_BUGSIGDB_ENRICHMENT.out.objects
    versions = BIOC_BUGSIGDBR_BUGSIGDB_ENRICHMENT.out.versions
}
