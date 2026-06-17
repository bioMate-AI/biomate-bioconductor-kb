#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dearseq — gene_set_analysis
// Perform gene-set analysis on RNA-seq data using the variance component score test.
// Input: expression_matrix.xlsx, metadata.csv, genesets.gmt
// Container: quay.io/biocontainers/bioconductor-dearseq:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocSet, SummarizedExperiment, dearseq, ggplot2, matrixStats, readxl
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Prepare expression data and metadata in a SummarizedExperiment object
//  * 2. [Core Analysis] Filter out genes with zero variance
//  * 3. [Core Analysis] Run gene-set analysis using dgsa_seq()
//  * 4. [Visualization & Output] Summarize results using summary()
//  * 5. [Visualization & Output] Visualize longitudinal expression within a gene set using spaghettiPlot1GS()

nextflow.enable.dsl = 2

process BIOC_DEARSEQ_GENE_SET_ANALYSIS {
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
    .bm_deps <- c("dearseq", "BiocSet", "readxl", "matrixStats", "ggplot2", "SummarizedExperiment")
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
        
         
        library(SummarizedExperiment)
       library(dearseq)
        library(BiocSet)
        library(readxl)
        library(matrixStats)
        library(ggplot2)
        
        # ==========================================
        # 1. Read User Input Files & Prepare Objects
        # ==========================================
        
        # Read normalized expression matrix
        expr_df <- readxl::read_excel("expression_matrix.xlsx")
        gene_names <- expr_df[[1]]
        expr_norm_corr <- as.matrix(expr_df[, -1])
        rownames(expr_norm_corr) <- gene_names
        
        # Read metadata
        design <- read.csv("metadata.csv", stringsAsFactors = TRUE)
        
        # Ensure metadata rownames match expression matrix colnames
        if ("sample" %in% colnames(design)) {
          rownames(design) <- design\$sample
        } else {
          rownames(design) <- colnames(expr_norm_corr)
          design\$sample <- colnames(expr_norm_corr)
        }
        design <- design[colnames(expr_norm_corr), , drop = FALSE]
        
        # Custom robust GMT reader to parse gene sets into a list structure
        read_gmt <- function(file) {
          lines <- readLines(file)
          gmt <- lapply(lines, function(line) {
            parts <- strsplit(line, "\t")[[1]]
            genes <- parts[3:length(parts)]
            genes <- genes[genes != ""]
            return(genes)
          })
          names(gmt) <- sapply(lines, function(line) strsplit(line, "\t")[[1]][1])
          return(gmt)
        }
        
        baduel_gmt <- list(genesets = read_gmt("genesets.gmt"))
        
        # Construct SummarizedExperiment object
        se2 <- SummarizedExperiment(assay = log2(expr_norm_corr + 1), 
                                    colData = design)
        
        # ==========================================
        # 2. Filter out genes with zero variance
        # ==========================================
        genes_non0var_ind <- which(matrixStats::rowVars(expr_norm_corr) != 0)
        
        # Determine gene sets to test (mimic vignette's subsetting dynamically)
        selected_indices <- if(length(baduel_gmt\$genesets) >= 5) c(3, 5) else 1:min(2, length(baduel_gmt\$genesets))
        genesets_to_test <- baduel_gmt\$genesets[selected_indices]
        
        # ==========================================
        # 3. Run gene-set analysis using dgsa_seq()
        # ==========================================
        
        valid_cols <- setdiff(colnames(design), "sample")
        if (length(valid_cols) == 0) valid_cols <- "sample"
        
        var1 <- valid_cols[1]
        cov1 <- setdiff(valid_cols, var1)
        if (length(cov1) == 0) cov1 <- NULL
        
        var2 <- if (length(valid_cols) > 1) valid_cols[2] else valid_cols[1]
        cov2 <- setdiff(valid_cols, var2)
        if (length(cov2) == 0) cov2 <- NULL
        
        # Test 1: KAvsTBG
        args1 <- list(object = se2[genes_non0var_ind, ],
                      variables2test = var1,
                      genesets = genesets_to_test,
                      which_test = 'permutation', which_weights = 'loclin',
                      n_perm = 2000, preprocessed = TRUE,
                      verbose = FALSE, 
                      parallel_comp = FALSE)
        if (!is.null(cov1)) args1\$covariates <- cov1
        KAvsTBG <- do.call(dearseq::dgsa_seq, args1)
        
        # Test 2: Cold
        args2 <- list(object = se2[genes_non0var_ind, ],
                      variables2test = var2,
                      genesets = genesets_to_test,
                      which_test = 'permutation', which_weights = 'loclin',
                      n_perm = 2000, preprocessed = TRUE, 
                      verbose = FALSE, 
                      parallel_comp = FALSE)
        if (!is.null(cov2)) args2\$covariates <- cov2
        Cold <- do.call(dearseq::dgsa_seq, args2)
        
        # ==========================================
        # 4. Summarize and Save Results
        # ==========================================
        
        # Save text summaries
        sink("KAvsTBG_summary.txt")
        summary(KAvsTBG)
        sink()
        
        sink("Cold_summary.txt")
        summary(Cold)
        sink()
        
        # Save p-values to CSV
        write.csv(as.data.frame(KAvsTBG\$pvals), "KAvsTBG_pvals.csv", row.names = TRUE)
        write.csv(as.data.frame(Cold\$pvals), "Cold_pvals.csv", row.names = TRUE)
        
        # Save RDS objects
        saveRDS(KAvsTBG, "KAvsTBG_results.rds")
        saveRDS(Cold, "Cold_results.rds")
        
        # ==========================================
        # 5. Visualize Longitudinal Expression
        # ==========================================
        
        if (!"sample" %in% colnames(colData(se2))) {
          colData(se2)[["sample"]] <- colnames(se2)
        }
        
        numeric_cols <- names(design)[sapply(design, is.numeric)]
        time_col <- if (length(numeric_cols) > 0) numeric_cols[1] else valid_cols[1]
        
        time_sym <- as.name(time_col)
        indiv_sym <- as.name("sample")
        group_sym <- as.name(valid_cols[1])
        subgroup_sym <- as.name(if (length(valid_cols) > 1) valid_cols[2] else valid_cols[1])
        
        # Plot the first selected gene set
        p <- eval(bquote(
          spaghettiPlot1GS(gs_index = selected_indices[1], gmt = baduel_gmt, expr_mat = assay(se2), 
                           design = colData(se2), var_time = .(time_sym), var_indiv = .(indiv_sym), 
                           sampleIdColname = "sample", var_group = .(group_sym), var_subgroup = .(subgroup_sym), 
                           loess_span = 1.5)
        )) + ggplot2::xlab(time_col)
        
        ggsave("spaghetti_plot.pdf", plot = p, width = 8, height = 6)

    writeLines(c(
        '"BIOC_DEARSEQ_GENE_SET_ANALYSIS":',
        paste0('    dearseq: ', as.character(packageVersion('dearseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_set_analysis.csv versions.yml
    """
}

workflow BIOC_DEARSEQ_GENE_SET_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.xlsx, metadata.csv, genesets.gmt ] ]

    main:
    BIOC_DEARSEQ_GENE_SET_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DEARSEQ_GENE_SET_ANALYSIS.out.tables
    plots    = BIOC_DEARSEQ_GENE_SET_ANALYSIS.out.plots
    objects  = BIOC_DEARSEQ_GENE_SET_ANALYSIS.out.objects
    versions = BIOC_DEARSEQ_GENE_SET_ANALYSIS.out.versions
}
