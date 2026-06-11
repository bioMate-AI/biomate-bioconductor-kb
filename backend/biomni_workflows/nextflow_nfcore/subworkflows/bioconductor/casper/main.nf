#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: casper — casper_equivalence_testing
// Perform alternative splicing/isoform expression equivalence testing and model diagnostics on expression data using casper's empirical Bayes and limma-treat wrap
// Input: counts.csv, coldata.csv
// Container: 2.44.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, casper
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CASPER_CASPER_EQUIVALENCE_TESTING {
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
    library(Biobase)
    library(casper)
    
    # Stage 1: Read and preprocess input data
    counts_file <- "counts.csv"
    coldata_file <- "coldata.csv"
    
    if (!file.exists(counts_file) || !file.exists(coldata_file)) {
        stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    # Read expression/count matrix
    counts_df <- read.csv(counts_file, check.names = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
        rownames(counts_df) <- counts_df\$gene_id
        counts_df\$gene_id <- NULL
    }
    counts_matrix <- as.matrix(counts_df)
    
    # Read sample metadata
    coldata <- read.csv(coldata_file, check.names = FALSE)
    if (!"sample" %in% colnames(coldata) || !"condition" %in% colnames(coldata)) {
        stop("coldata.csv must contain 'sample' and 'condition' columns.")
    }
    rownames(coldata) <- coldata\$sample
    
    # Align samples between counts and coldata
    common_samples <- intersect(colnames(counts_matrix), coldata\$sample)
    if (length(common_samples) == 0) {
        stop("No overlapping samples found between counts.csv and coldata.csv.")
    }
    counts_matrix <- counts_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # If values look like raw counts (integers and large), log2-transform them
    if (all(counts_matrix %% 1 == 0) && max(counts_matrix) > 50) {
        message("Raw counts detected. Applying log2(x + 1) transformation...")
        exprs_vals <- log2(counts_matrix + 1)
    } else {
        exprs_vals <- counts_matrix
    }
    
    # Stage 2: Construct ExpressionSet and Normalize
    pheno_data <- new("AnnotatedDataFrame", data = coldata)
    feature_data <- new("AnnotatedDataFrame", data = data.frame(
        readCount = rowSums(counts_matrix),
        row.names = rownames(counts_matrix)
    ))
    
    eset <- new("ExpressionSet",
                exprs = exprs_vals,
                phenoData = pheno_data,
                featureData = feature_data)
    
    # Apply quantile normalization
    message("Performing quantile normalization...")
    eset_norm <- quantileNorm(eset)
    
    # Ensure condition is a factor for group comparison
    pData(eset_norm)\$condition <- as.factor(pData(eset_norm)\$condition)
    
    # Stage 3: Equivalence Testing
    logfc_threshold <- log(1.5)
    
    # 3.1 Empirical Bayes Equivalence Testing (probNonEquiv)
    message("Running empirical Bayes equivalence testing (probNonEquiv)...")
    prob_ne_df <- data.frame(gene_id = rownames(eset_norm), prob_non_equiv = NA)
    tryCatch({
        prob_ne <- probNonEquiv(eset_norm, groups = "condition", logfc = logfc_threshold, minCount = 0)
        prob_ne_df <- data.frame(gene_id = names(prob_ne), prob_non_equiv = prob_ne)
    }, error = function(e) {
        warning("probNonEquiv failed: ", e\$message)
    })
    
    # 3.2 Limma-treat Equivalence Testing (pvalTreat)
    message("Running limma-treat equivalence testing (pvalTreat)...")
    treat_p_df <- data.frame(gene_id = rownames(eset_norm), adj_p_val = NA)
    tryCatch({
        pvals <- pvalTreat(eset_norm, groups = "condition", logfc = logfc_threshold, minCount = 0, p.adjust.method = "BH")
        treat_p_df <- data.frame(gene_id = names(pvals), adj_p_val = pvals)
    }, error = function(e) {
        warning("pvalTreat failed: ", e\$message)
    })
    
    # Write tabular outputs
    write.csv(prob_ne_df, "equivalence_probabilities.csv", row.names = FALSE)
    write.csv(treat_p_df, "treat_pvalues.csv", row.names = FALSE)
    
    # Stage 4: Model Diagnostics and Visualization
    message("Generating diagnostic plots...")
    pdf("diagnostics.pdf", width = 10, height = 8)
    par(mfrow = c(2, 2))
    
    # 4.1 Normal QQ Plot
    tryCatch({
        qqnormGenomeWide(eset_norm, ngenes = min(500, nrow(eset_norm)))
        title("Genome-wide Normal QQ Plot")
    }, error = function(e) {
        plot.new()
        text(0.5, 0.5, paste("Normal QQ Plot Failed:\n", e\$message), cex = 0.8)
    })
    
    # 4.2 Asymmetry Check
    tryCatch({
        asymmetryCheck(eset_norm)
        title("Asymmetry Check")
    }, error = function(e) {
        plot.new()
        text(0.5, 0.5, paste("Asymmetry Check Failed:\n", e\$message), cex = 0.8)
    })
    
    # 4.3 Gamma QQ Plot (requires positive values)
    tryCatch({
        eset_pos <- eset_norm
        offset <- min(exprs(eset_pos))
        exprs(eset_pos) <- exprs(eset_pos) - offset + 1
        qqgammaGenomeWide(eset_pos, ngenes = min(500, nrow(eset_pos)))
        title("Genome-wide Gamma QQ Plot")
    }, error = function(e) {
        plot.new()
        text(0.5, 0.5, paste("Gamma QQ Plot Failed:\n", e\$message), cex = 0.8)
    })
    
    dev.off()
    message("Analysis complete. Outputs written successfully.")

    writeLines(c(
        '"BIOC_CASPER_CASPER_EQUIVALENCE_TESTING":',
        paste0('    casper: ', as.character(packageVersion('casper')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_casper_equivalence_testing.csv versions.yml
    """
}

workflow BIOC_CASPER_CASPER_EQUIVALENCE_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_CASPER_CASPER_EQUIVALENCE_TESTING(ch_input)

    emit:
    tables   = BIOC_CASPER_CASPER_EQUIVALENCE_TESTING.out.tables
    plots    = BIOC_CASPER_CASPER_EQUIVALENCE_TESTING.out.plots
    objects  = BIOC_CASPER_CASPER_EQUIVALENCE_TESTING.out.objects
    versions = BIOC_CASPER_CASPER_EQUIVALENCE_TESTING.out.versions
}
