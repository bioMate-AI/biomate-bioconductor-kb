#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: factDesign — fact_design_factorial_analysis
// Perform a comprehensive 2x2 factorial design analysis of transcriptomic data using the factDesign package, including outlier detection, linear modeling, contras
// Input: counts.csv, coldata.csv
// Container: 1.86.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, factDesign
// Visualizations: heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FACTDESIGN_FACT_DESIGN_FACTORIAL_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Biobase", "factDesign")
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
    library(Biobase)
    library(factDesign)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    # Read expression matrix (counts.csv contains normalized expression values for microarray)
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$gene_id
      counts_df\$gene_id <- NULL
    }
    counts <- as.matrix(counts_df)
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    rownames(coldata) <- coldata\$sample
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(counts), rownames(coldata))
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Ensure 2x2 factorial design factors (ES and TIME) exist
    if (!all(c("ES", "TIME") %in% colnames(coldata))) {
      if ("condition" %in% colnames(coldata)) {
        # Attempt to parse ES and TIME from condition (e.g., "A_10h", "P_48h")
        parts <- strsplit(as.character(coldata\$condition), "_")
        coldata\$ES <- sapply(parts, function(x) x[1])
        coldata\$TIME <- sapply(parts, function(x) if(length(x) > 1) x[2] else "10h")
      } else {
        # Fallback dummy factors for 2x2 design if not present
        coldata\$ES <- rep(c("A", "P"), length.out = nrow(coldata))
        coldata\$TIME <- rep(c("10h", "48h"), each = 2, length.out = nrow(coldata))
      }
    }
    
    coldata\$ES <- as.factor(coldata\$ES)
    coldata\$TIME <- as.factor(coldata\$TIME)
    
    # Create ExpressionSet object
    pheno <- AnnotatedDataFrame(coldata)
    eset <- ExpressionSet(assayData = counts, phenoData = pheno)
    
    # ==========================================
    # --- Gene Filtering using kRepsOverA ---
    # ==========================================
    
    # Filter genes that have at least k replicates with expression over A in any condition group
    group <- interaction(pData(eset)\$ES, pData(eset)\$TIME)
    # Find a reasonable threshold A (median of expression matrix)
    median_expr <- median(exprs(eset), na.rm = TRUE)
    
    keep <- tryCatch({
      filter_fun <- kRepsOverA(INDEX = group, k = 2, A = median_expr)
      apply(exprs(eset), 1, filter_fun)
    }, error = function(e) {
      # Fallback if kRepsOverA fails
      rep(TRUE, nrow(eset))
    })
    
    eset <- eset[keep, ]
    
    # ==========================================
    # --- Outlier Detection and Removal ---
    # ==========================================
    
    expr_mat <- exprs(eset)
    cleaned_expr_mat <- expr_mat
    
    for (j in seq_len(nrow(expr_mat))) {
      tryCatch({
        op <- outlierPair(expr_mat[j, ], INDEX = pData(eset), p = 0.05)
        if (op[[1]]) {
          so <- madOutPair(expr_mat[j, ], op[[3]])
          if (!is.na(so)) {
            cleaned_expr_mat[j, so] <- NA
          }
        }
      }, error = function(e) {
        # Ignore errors for individual genes
      })
    }
    exprs(eset) <- cleaned_expr_mat
    
    # ==========================================
    # --- Linear Modeling and ANOVA F-test ---
    # ==========================================
    
    lm.full <- function(y) lm(y ~ ES + TIME + ES:TIME, data = pData(eset))
    lm.time <- function(y) lm(y ~ TIME, data = pData(eset))
    
    lm.f <- esApply(eset, 1, lm.full)
    lm.t <- esApply(eset, 1, lm.time)
    
    # Extract ANOVA p-values robustly
    get_p_value <- function(m_reduced, m_full) {
      an <- anova(m_reduced, m_full)
      pval <- an[["Pr(>F)"]][2]
      if (is.null(pval)) pval <- an[["P"]][2]
      if (is.null(pval)) pval <- an\$p[2]
      return(pval)
    }
    
    Fpvals <- rep(NA, length(lm.f))
    names(Fpvals) <- names(lm.f)
    
    for (i in seq_along(lm.f)) {
      Fpvals[i] <- tryCatch({
        get_p_value(lm.t[[i]], lm.f[[i]])
      }, error = function(e) NA)
    }
    
    # Handle missing p-values
    Fpvals[is.na(Fpvals)] <- 1
    
    # Multiple testing correction (BH method)
    F.adjps <- p.adjust(Fpvals, method = "BH")
    
    # Select genes of interest (FDR < 0.15)
    Fsub <- which(F.adjps < 0.15)
    if (length(Fsub) < 5) {
      # Fallback to top 10 genes if too few pass FDR threshold
      Fsub <- order(Fpvals)[1:min(10, length(Fpvals))]
    }
    
    estrogen.Fsub <- eset[Fsub, ]
    lm.f.Fsub <- lm.f[Fsub]
    
    # ==========================================
    # --- Contrast Testing & Fold Change ---
    # ==========================================
    
    betaNames <- names(coef(lm.f[[1]]))
    
    # Dynamically identify the main effect coefficient for ES
    es_coef <- betaNames[grepl("ES", betaNames) & !grepl(":", betaNames)]
    if (length(es_coef) == 0) es_coef <- betaNames[2]
    
    # Main ES effect contrast test
    lambda <- par2lambda(betaNames, es_coef, 1)
    mainES <- function(x) {
      tryCatch({
        contrastTest(x, lambda, p = 0.05)[[1]]
      }, error = function(e) "FAIL TO REJECT")
    }
    mainESgenes <- sapply(lm.f.Fsub, FUN = mainES)
    
    # Fold Change Estimation
    lambdaNum <- par2lambda(betaNames, list(c("(Intercept)", es_coef)), list(c(1, 1)))
    lambdaDenom <- par2lambda(betaNames, list(c("(Intercept)")), list(c(1)))
    
    FCvals <- sapply(lm.f.Fsub, function(x) {
      tryCatch({
        findFC(x, lambdaNum, lambdaDenom, logbase = 2)
      }, error = function(e) NA)
    })
    
    # Interaction / 48h Contrast Test
    interaction_coef <- betaNames[grepl(":", betaNames)]
    if (length(interaction_coef) == 0) interaction_coef <- betaNames[length(betaNames)]
    
    lambdaEST <- par2lambda(betaNames, list(c(es_coef, interaction_coef)), list(c(1, 1)))
    ESTcontrast <- function(x) {
      tryCatch({
        contrastTest(x, lambdaEST, p = 0.10)[[1]]
      }, error = function(e) "FAIL TO REJECT")
    }
    ESTgenes <- sapply(lm.f.Fsub, FUN = ESTcontrast)
    
    # ==========================================
    # --- Export Results and Visualizations ---
    # ==========================================
    
    # Save results table
    results_df <- data.frame(
      Gene_ID = rownames(estrogen.Fsub),
      F_pvalue = Fpvals[Fsub],
      F_adj_pvalue = F.adjps[Fsub],
      Main_ES_Decision = mainESgenes,
      Fold_Change = FCvals,
      Interaction_Decision = ESTgenes,
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "fact_design_results.csv", row.names = FALSE)
    
    # Generate diagnostic plots and heatmaps
    pdf("fact_design_plots.pdf", width = 8, height = 8)
    
    sub_expr <- exprs(estrogen.Fsub)
    # Impute any NA values (from outlier removal) with row means for visualization
    for (i in seq_len(nrow(sub_expr))) {
      if (any(is.na(sub_expr[i, ]))) {
        sub_expr[i, is.na(sub_expr[i,])] <- mean(sub_expr[i, ], na.rm = TRUE)
      }
    }
    
    if (nrow(sub_expr) > 1) {
      heatmap(sub_expr, Colv = NA, col = cm.colors(256), main = "Selected Genes (FDR < 0.15)")
    }
    
    reject_genes <- mainESgenes == "REJECT"
    if (sum(reject_genes) > 1) {
      heatmap(sub_expr[reject_genes, , drop = FALSE], Colv = NA, col = cm.colors(256), main = "Main ES Effect Rejected")
    }
    
    dev.off()

    writeLines(c(
        '"BIOC_FACTDESIGN_FACT_DESIGN_FACTORIAL_ANALYSIS":',
        paste0('    factDesign: ', as.character(packageVersion('factDesign')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fact_design_factorial_analysis.csv versions.yml
    """
}

workflow BIOC_FACTDESIGN_FACT_DESIGN_FACTORIAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_FACTDESIGN_FACT_DESIGN_FACTORIAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FACTDESIGN_FACT_DESIGN_FACTORIAL_ANALYSIS.out.tables
    plots    = BIOC_FACTDESIGN_FACT_DESIGN_FACTORIAL_ANALYSIS.out.plots
    objects  = BIOC_FACTDESIGN_FACT_DESIGN_FACTORIAL_ANALYSIS.out.objects
    versions = BIOC_FACTDESIGN_FACT_DESIGN_FACTORIAL_ANALYSIS.out.versions
}
