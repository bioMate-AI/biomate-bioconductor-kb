#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ANCOMBC — secom_correlation_analysis
// Estimate sparse linear and non-linear correlations among taxa within or across ecosystems.
// Input: microbiome_counts.tsv, sample_metadata.tsv
// Container: quay.io/biocontainers/bioconductor-ancombc:2.12.0--r45hdfd78af_0
// R packages: ANCOMBC, dplyr, phyloseq, readr
// Bioconductor: 3.20 | R: 4.4
// Requires: ANCOMBC, dplyr, phyloseq, readr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the microbiome data and metadata (or a phyloseq/TreeSummarizedExperiment object)
//  * 2. [Core Analysis] Run secom_linear to estimate linear relationships (Pearson or Spearman)
//  * 3. [Core Analysis] Run secom_dist to estimate non-linear relationships (Distance correlation)
//  * 4. [Core Analysis] Extract correlation matrices and co-occurrence tables

nextflow.enable.dsl = 2

process BIOC_ANCOMBC_SECOM_CORRELATION_ANALYSIS {
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
    .bm_deps <- c("ANCOMBC", "dplyr", "phyloseq", "readr")
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
    library(ANCOMBC)
    library(phyloseq)
    library(dplyr)
    library(readr)
    
    # 1. Load the microbiome data and metadata
    # Read the microbial abundance table
    counts <- read.delim("microbiome_counts.tsv", header = TRUE, row.names = 1, check.names = FALSE)
    
    # Read the sample metadata
    metadata <- read.delim("sample_metadata.tsv", header = TRUE, row.names = 1, check.names = FALSE)
    
    # Parse or construct a taxonomy table
    # SECOM requires a taxonomy table with the specified tax_level (e.g., "Phylum")
    tax_col <- grep("tax", colnames(counts), ignore.case = TRUE)
    if (length(tax_col) > 0) {
        tax_strings <- counts[, tax_col[1]]
        counts <- counts[, -tax_col[1], drop = FALSE]
        
        tax_matrix <- do.call(rbind, lapply(strsplit(as.character(tax_strings), ";|\\\\|"), function(x) {
            x <- gsub("^[kpcofgs]__", "", x)
            if (length(x) < 7) x <- c(x, rep(NA, 7 - length(x)))
            x[1:7]
        }))
        colnames(tax_matrix) <- c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
        rownames(tax_matrix) <- rownames(counts)
    } else {
        # Create a dummy taxonomy table with a "Phylum" column matching the row names
        tax_matrix <- matrix("Unassigned", nrow = nrow(counts), ncol = 7)
        colnames(tax_matrix) <- c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
        rownames(tax_matrix) <- rownames(counts)
        tax_matrix[, "Phylum"] <- rownames(counts)
        
        # Attempt to parse Phylum from semicolon-separated row names if present
        for (i in seq_len(nrow(counts))) {
            rname <- rownames(counts)[i]
            if (grepl(";", rname)) {
                parts <- strsplit(rname, ";")[[1]]
                phylum_part <- grep("p__", parts, value = TRUE)
                if (length(phylum_part) > 0) {
                    tax_matrix[i, "Phylum"] <- gsub("p__", "", phylum_part[1])
                } else if (length(parts) >= 2) {
                    tax_matrix[i, "Phylum"] <- parts[2]
                }
            }
        }
    }
    
    # Construct the phyloseq object
    OTU <- otu_table(as.matrix(counts), taxa_are_rows = TRUE)
    TAX <- tax_table(tax_matrix)
    META <- sample_data(metadata)
    pseq <- phyloseq(OTU, TAX, META)
    
    # 2. Run secom_linear to estimate linear relationships (Pearson or Spearman)
    res_linear = secom_linear(
        data = list(pseq), 
        tax_level = "Phylum", 
        pseudo = 0, 
        prv_cut = 0.5, 
        lib_cut = 1000, 
        corr_cut = 0.5, 
        wins_quant = c(0.05, 0.95), 
        method = "pearson", 
        soft = FALSE, 
        thresh_len = 20, 
        n_cv = 10, 
        thresh_hard = 0.3, 
        max_p = 0.005, 
        n_cl = 2
    )
    
    # 3. Run secom_dist to estimate non-linear relationships (Distance correlation)
    res_dist = secom_dist(
        data = list(pseq), 
        tax_level = "Phylum", 
        pseudo = 0, 
        prv_cut = 0.5, 
        lib_cut = 1000, 
        corr_cut = 0.5, 
        wins_quant = c(0.05, 0.95), 
        R = 1000, 
        thresh_hard = 0.3, 
        max_p = 0.005, 
        n_cl = 2
    )
    
    # 4. Extract correlation matrices and co-occurrence tables, and write outputs
    # Save full RDS objects
    saveRDS(res_linear, "secom_linear_results.rds")
    saveRDS(res_dist, "secom_dist_results.rds")
    
    # Helper to extract correlation matrix across different ANCOMBC versions
    get_corr_matrix <- function(res) {
        mat <- NULL
        if (!is.null(res\$s_diff_hat)) mat <- res\$s_diff_hat
        else if (!is.null(res\$corr_th)) mat <- res\$corr_th
        else if (!is.null(res\$corr_fl)) mat <- res\$corr_fl
        else if (!is.null(res\$dcorr_th)) mat <- res\$dcorr_th
        else if (!is.null(res\$dcorr_fl)) mat <- res\$dcorr_fl
        
        if (is.list(mat) && length(mat) > 0) {
            mat <- mat[[1]]
        }
        return(mat)
    }
    
    mat_linear <- get_corr_matrix(res_linear)
    mat_dist <- get_corr_matrix(res_dist)
    
    # Export Linear Correlation Results
    if (!is.null(mat_linear)) {
        write.csv(as.data.frame(mat_linear), "secom_linear_correlation.csv", row.names = TRUE)
    }
    if (!is.null(res_linear\$p_val) && length(res_linear\$p_val) > 0) {
        p_val_mat <- if (is.list(res_linear\$p_val)) res_linear\$p_val[[1]] else res_linear\$p_val
        write.csv(as.data.frame(p_val_mat), "secom_linear_p_val.csv", row.names = TRUE)
    }
    if (!is.null(res_linear\$q_val) && length(res_linear\$q_val) > 0) {
        q_val_mat <- if (is.list(res_linear\$q_val)) res_linear\$q_val[[1]] else res_linear\$q_val
        write.csv(as.data.frame(q_val_mat), "secom_linear_q_val.csv", row.names = TRUE)
    }
    
    # Export Distance Correlation Results
    if (!is.null(mat_dist)) {
        write.csv(as.data.frame(mat_dist), "secom_dist_correlation.csv", row.names = TRUE)
    }
    if (!is.null(res_dist\$p_val) && length(res_dist\$p_val) > 0) {
        p_val_mat_dist <- if (is.list(res_dist\$p_val)) res_dist\$p_val[[1]] else res_dist\$p_val
        write.csv(as.data.frame(p_val_mat_dist), "secom_dist_p_val.csv", row.names = TRUE)
    }
    
    # Generate Visualizations
    pdf("secom_correlation_plots.pdf", width = 10, height = 8)
    
    # Plot Linear Correlation Heatmap
    if (!is.null(mat_linear) && nrow(mat_linear) > 1) {
        tryCatch({
            heatmap(
                as.matrix(mat_linear), 
                symm = TRUE, 
                col = colorRampPalette(c("blue", "white", "red"))(100),
                main = "SECOM Linear Correlation (Pearson)"
            )
        }, error = function(e) {
            message("Could not plot linear correlation heatmap: ", e\$message)
        })
    }
    
    # Plot Distance Correlation Heatmap
    if (!is.null(mat_dist) && nrow(mat_dist) > 1) {
        tryCatch({
            heatmap(
                as.matrix(mat_dist), 
                symm = TRUE, 
                col = colorRampPalette(c("white", "red"))(100),
                main = "SECOM Distance Correlation"
            )
        }, error = function(e) {
            message("Could not plot distance correlation heatmap: ", e\$message)
        })
    }
    
    dev.off()

    writeLines(c(
        '"BIOC_ANCOMBC_SECOM_CORRELATION_ANALYSIS":',
        paste0('    ANCOMBC: ', as.character(packageVersion('ANCOMBC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_secom_correlation_analysis.csv versions.yml
    """
}

workflow BIOC_ANCOMBC_SECOM_CORRELATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ microbiome_counts.tsv, sample_metadata.tsv ] ]

    main:
    BIOC_ANCOMBC_SECOM_CORRELATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_ANCOMBC_SECOM_CORRELATION_ANALYSIS.out.tables
    plots    = BIOC_ANCOMBC_SECOM_CORRELATION_ANALYSIS.out.plots
    objects  = BIOC_ANCOMBC_SECOM_CORRELATION_ANALYSIS.out.objects
    versions = BIOC_ANCOMBC_SECOM_CORRELATION_ANALYSIS.out.versions
}
