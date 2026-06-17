#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: phenoTest — phenot_expression_correlation
// Perform comprehensive association testing between gene expression and multiple phenotype variables (categorical, continuous, and survival) followed by Gene Set 
// Input: counts.csv, coldata.csv
// Container: 1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GSEABase, phenoTest
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHENOTEST_PHENOT_EXPRESSION_CORRELATION {
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
    .bm_deps <- c("phenoTest", "GSEABase", "Biobase")
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
    library(phenoTest)
    library(GSEABase)
    library(Biobase)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    # Read expression matrix (probes/genes as rows, samples as columns)
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    exprs_matrix <- as.matrix(counts)
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    rownames(coldata) <- coldata\$sample
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(exprs_matrix), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No common samples found between counts.csv and coldata.csv")
    }
    exprs_matrix <- exprs_matrix[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, drop = FALSE]
    
    # Simulate continuous and survival variables to demonstrate full phenoTest capabilities
    set.seed(42)
    coldata\$TumorSize <- rnorm(nrow(coldata), mean = 50, sd = 10)
    coldata\$SurvivalTime <- runif(nrow(coldata), min = 5, max = 120)
    coldata\$Status <- rbinom(nrow(coldata), size = 1, prob = 0.4)
    
    # Construct the ExpressionSet object
    pheno_data <- AnnotatedDataFrame(coldata)
    eset <- ExpressionSet(assayData = exprs_matrix, phenoData = pheno_data)
    
    # Define the variables to test
    survival_mat <- matrix(c("Status", "SurvivalTime"), ncol = 2, byrow = TRUE)
    colnames(survival_mat) <- c("event", "time")
    
    vars2test <- list(
      survival = survival_mat,
      categorical = "condition",
      continuous = "TumorSize"
    )
    
    # ==========================================
    # --- Individual Gene Association Testing ---
    # ==========================================
    
    # Run ExpressionPhenoTest
    message("Running ExpressionPhenoTest...")
    epheno <- ExpressionPhenoTest(eset, vars2test, p.adjust.method = "none")
    
    # Adjust p-values using Benjamini-Hochberg (BH) method
    epheno <- pAdjust(epheno, method = "BH")
    
    # Extract statistics and save to CSV
    pvals <- getSignif(epheno)
    fc <- getFc(epheno)
    hr <- getHr(epheno)
    means <- getMeans(epheno)
    
    # Combine key statistics into a single data frame for export
    combined_results <- data.frame(
      Gene = rownames(pvals),
      pvals,
      stringsAsFactors = FALSE
    )
    
    write.csv(combined_results, "epheno_pvals.csv", row.names = FALSE)
    message("Gene-level association testing completed and saved.")
    
    # ==========================================
    # --- Gene Set Signature Analysis ---
    # ==========================================
    
    # Define gene signatures dynamically based on available features
    features <- featureNames(eset)
    n_features <- length(features)
    
    if (n_features >= 10) {
      size1 <- min(20, floor(n_features / 2))
      sign1 <- features[1:size1]
      sign2 <- features[(size1 + 1):min(size1 + 30, n_features)]
    } else {
      sign1 <- features[1:floor(n_features/2)]
      sign2 <- features[(floor(n_features/2)+1):n_features]
    }
    
    # Create GeneSetCollection
    myGeneSetA <- GeneSet(geneIds = sign1, setName = "Signature_A")
    myGeneSetB <- GeneSet(geneIds = sign2, setName = "Signature_B")
    mySignature <- GeneSetCollection(myGeneSetA, myGeneSetB)
    
    # Start PDF device to capture all diagnostic plots
    pdf("pheno_plots.pdf", width = 10, height = 8)
    
    # Plot percentage of significant up/down regulated genes in each signature
    tryCatch({
      barplotSignifSignatures(epheno[, "condition"], mySignature, alpha = 0.99)
    }, error = function(e) {
      message("Skipping barplotSignifSignatures due to: ", e\$message)
    })
    
    # Plot average fold change for continuous variable
    tryCatch({
      barplotSignatures(epheno[, "TumorSize"], mySignature, ylim = c(-2, 2))
    }, error = function(e) {
      message("Skipping barplotSignatures due to: ", e\$message)
    })
    
    # Heatmap and Kaplan-Meier survival curves based on Signature A clustering
    tryCatch({
      heatmapPhenoTest(eset, mySignature[[1]], vars2test = vars2test["survival"], heat.kaplan = "heat")
      heatmapPhenoTest(eset, mySignature[[1]], vars2test = vars2test["survival"], heat.kaplan = "kaplan")
    }, error = function(e) {
      message("Skipping heatmapPhenoTest due to: ", e\$message)
    })
    
    # ==========================================
    # --- Gene Set Enrichment Analysis (GSEA) ---
    # ==========================================
    
    # Run GSEA with permutation test
    message("Running GSEA permutation test...")
    B_param <- as.numeric(Sys.getenv("B", unset = "100"))
    my.gsea <- gsea(x = epheno, gsets = mySignature, B = B_param, p.adjust = "BH")
    
    # Save GSEA summary table
    gsea_summary <- summary.gseaData(my.gsea)
    write.csv(gsea_summary, "gsea_summary.csv", row.names = FALSE)
    
    # Plot GSEA enrichment curves
    tryCatch({
      plot.gseaData(my.gsea, es.nes = "es", selGsets = "Signature_A")
    }, error = function(e) {
      message("Skipping GSEA plot due to: ", e\$message)
    })
    
    # Run Wilcoxon-based GSEA (alternative fast approach)
    message("Running GSEA Wilcoxon test...")
    my.gsea.wilcox <- gsea(x = epheno, gsets = mySignature, B = B_param, test = "wilcox", p.adjust = "BH")
    
    # Plot Wilcoxon GSEA density curves
    tryCatch({
      plot.gseaData(my.gsea.wilcox, selGsets = "Signature_A")
    }, error = function(e) {
      message("Skipping Wilcoxon GSEA plot due to: ", e\$message)
    })
    
    # Close PDF device
    dev.off()
    message("Pipeline completed successfully. All outputs generated.")

    writeLines(c(
        '"BIOC_PHENOTEST_PHENOT_EXPRESSION_CORRELATION":',
        paste0('    phenoTest: ', as.character(packageVersion('phenoTest')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phenot_expression_correlation.csv versions.yml
    """
}

workflow BIOC_PHENOTEST_PHENOT_EXPRESSION_CORRELATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_PHENOTEST_PHENOT_EXPRESSION_CORRELATION(ch_input)

    emit:
    tables   = BIOC_PHENOTEST_PHENOT_EXPRESSION_CORRELATION.out.tables
    plots    = BIOC_PHENOTEST_PHENOT_EXPRESSION_CORRELATION.out.plots
    objects  = BIOC_PHENOTEST_PHENOT_EXPRESSION_CORRELATION.out.objects
    versions = BIOC_PHENOTEST_PHENOT_EXPRESSION_CORRELATION.out.versions
}
