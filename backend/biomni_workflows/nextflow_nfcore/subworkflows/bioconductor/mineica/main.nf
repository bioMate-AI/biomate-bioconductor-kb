#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MineICA — mineica_transcriptome_analysis
// Perform Independent Component Analysis (ICA) on transcriptomic data, identify components associated with sample conditions, and extract key contributing genes.
// Input: counts.csv, coldata.csv
// Container: 1.49.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, MineICA, fastICA
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MINEICA_MINEICA_TRANSCRIPTOME_ANALYSIS {
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
    .bm_deps <- c("MineICA", "fastICA", "Biobase")
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
    library(MineICA)
    library(fastICA)
    library(Biobase)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    # Read expression/count matrix and sample metadata
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
        stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", check.names = FALSE)
    rownames(counts) <- counts\$gene_id
    counts\$gene_id <- NULL
    
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    rownames(coldata) <- coldata\$sample
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(counts), rownames(coldata))
    if (length(common_samples) == 0) {
        stop("No matching samples found between counts.csv and coldata.csv.")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, drop = FALSE]
    
    # Convert to matrix and apply log2 transformation if data is raw counts
    exprs_mat <- as.matrix(counts)
    if (max(exprs_mat, na.rm = TRUE) > 100) {
        message("High values detected. Applying log2(x + 1) transformation...")
        exprs_mat <- log2(exprs_mat + 1)
    }
    
    # Filter out genes with zero or extremely low variance
    gene_vars <- apply(exprs_mat, 1, var)
    exprs_mat <- exprs_mat[gene_vars > 0.01, , drop = FALSE]
    
    # Keep top 1000 most variable genes to ensure stable and fast ICA decomposition
    if (nrow(exprs_mat) > 1000) {
        top_genes <- names(sort(gene_vars, decreasing = TRUE))[1:1000]
        exprs_mat <- exprs_mat[top_genes, , drop = FALSE]
    }
    
    # ==========================================
    # --- Run Independent Component Analysis ---
    # ==========================================
    
    # Determine number of components
    nbComp <- min(3, ncol(exprs_mat) - 1)
    if (nbComp < 2) nbComp <- 2
    
    message(paste("Running fastICA to extract", nbComp, "components..."))
    # fastICA expects samples as rows and genes as columns
    ica_res <- fastICA::fastICA(t(exprs_mat), n.comp = nbComp)
    
    # Reconstruct S (genes x components) and A (components x samples) matrices
    # In fastICA: X = S %*% A where S is source signals (samples x components) and A is mixing matrix (components x genes)
    # For MineICA:
    # - S represents gene projections (genes x components) -> t(ica_res\$A)
    # - A represents sample contributions (components x samples) -> t(ica_res\$S)
    S <- t(ica_res\$A)
    A <- t(ica_res\$S)
    
    colnames(S) <- paste0("IC", 1:nbComp)
    rownames(S) <- rownames(exprs_mat)
    rownames(A) <- paste0("IC", 1:nbComp)
    colnames(A) <- colnames(exprs_mat)
    
    # ==========================================
    # --- Build IcaSet Object ---
    # ==========================================
    
    pData_obj <- new("AnnotatedDataFrame", data = coldata)
    
    icaSet <- buildIcaSet(
        S = S,
        A = A,
        dat = exprs_mat,
        pData = pData_obj,
        annotation = "",
        typeID = c(geneID_S = "SYMBOL", geneID_res = "SYMBOL", sampleID_A = "sampleID")
    )
    
    # ==========================================
    # --- Analyze and Mine Components ---
    # ==========================================
    
    # 1. Test association of components with the qualitative variable 'condition'
    message("Testing association of components with sample conditions...")
    tryCatch({
        qual_res <- qualVarAnalysis(icaSet = icaSet, sampleVar = "condition")
        if (!is.null(qual_res\$pval)) {
            pvals_df <- data.frame(
                Component = rownames(qual_res\$pval),
                P_Value = qual_res\$pval[, "condition"],
                FDR = if (!is.null(qual_res\$fdr)) qual_res\$fdr[, "condition"] else NA
            )
            write.csv(pvals_df, "component_association_pvalues.csv", row.names = FALSE)
        } else {
            write.csv(data.frame(Component = character(), P_Value = numeric(), FDR = numeric()), "component_association_pvalues.csv", row.names = FALSE)
        }
    }, error = function(e) {
        warning("Qualitative variable analysis failed: ", e\$message)
        write.csv(data.frame(Error = e\$message), "component_association_pvalues.csv", row.names = FALSE)
    })
    
    # 2. Select genes contributing significantly to each component (cutoff = 2 standard deviations)
    message("Extracting driver genes for each component...")
    tryCatch({
        sel_genes <- selectGenes(icaSet = icaSet, cutoff = 2)
        sel_list <- list()
        for (ic in names(sel_genes)) {
            df <- sel_genes[[ic]]
            if (!is.null(df) && nrow(df) > 0) {
                if (is.data.frame(df)) {
                    df\$Component <- ic
                    df\$Gene <- rownames(df)
                } else {
                    df <- data.frame(Component = ic, Gene = names(df), Projection = as.numeric(df))
                }
                sel_list[[ic]] <- df
            }
        }
        if (length(sel_list) > 0) {
            sel_genes_df <- do.call(rbind, sel_list)
            write.csv(sel_genes_df, "selected_genes_per_component.csv", row.names = FALSE)
        } else {
            write.csv(data.frame(Component = character(), Gene = character(), Projection = numeric()), "selected_genes_per_component.csv", row.names = FALSE)
        }
    }, error = function(e) {
        warning("Gene selection failed: ", e\$message)
        write.csv(data.frame(Error = e\$message), "selected_genes_per_component.csv", row.names = FALSE)
    })
    
    # ==========================================
    # --- Visualizations and Diagnostics ---
    # ==========================================
    
    message("Generating diagnostic and contribution plots...")
    pdf("ica_plots.pdf", width = 8, height = 6)
    
    # Plot distribution of gene projections (Sparsity)
    tryCatch({
        plotSparsity(icaSet)
    }, error = function(e) {
        message("plotSparsity failed: ", e\$message)
    })
    
    # Plot sample contributions and gene projections for each component
    for (i in 1:nbComp) {
        # Plot sample contributions colored by condition
        tryCatch({
            p1 <- plotPosSamples(icaSet, component = i, variable = "condition")
            if (!is.null(p1)) {
                if (inherits(p1, "ggplot") || inherits(p1, "gg")) {
                    print(p1)
                }
            }
        }, error = function(e) {
            message("plotPosSamples failed for component ", i, ": ", e\$message)
        })
        
        # Plot gene projections
        tryCatch({
            p2 <- plotSres(icaSet, component = i)
            if (!is.null(p2)) {
                if (inherits(p2, "ggplot") || inherits(p2, "gg")) {
                    print(p2)
                }
            }
        }, error = function(e) {
            message("plotSres failed for component ", i, ": ", e\$message)
        })
    }
    
    dev.off()
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MINEICA_MINEICA_TRANSCRIPTOME_ANALYSIS":',
        paste0('    MineICA: ', as.character(packageVersion('MineICA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mineica_transcriptome_analysis.csv versions.yml
    """
}

workflow BIOC_MINEICA_MINEICA_TRANSCRIPTOME_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MINEICA_MINEICA_TRANSCRIPTOME_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MINEICA_MINEICA_TRANSCRIPTOME_ANALYSIS.out.tables
    plots    = BIOC_MINEICA_MINEICA_TRANSCRIPTOME_ANALYSIS.out.plots
    objects  = BIOC_MINEICA_MINEICA_TRANSCRIPTOME_ANALYSIS.out.objects
    versions = BIOC_MINEICA_MINEICA_TRANSCRIPTOME_ANALYSIS.out.versions
}
