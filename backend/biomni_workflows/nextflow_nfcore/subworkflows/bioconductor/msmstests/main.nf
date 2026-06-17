#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msmsTests — msms_tests_differential_expression
// Perform differential expression analysis on label-free LC-MS/MS spectral count data using Poisson, Quasi-likelihood, and Negative Binomial GLMs with post-test f
// Input: intensity.csv, coldata.csv
// Container: 1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MSnbase, msmsTests
// Visualizations: volcano plot
// QC: low-count filtering
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSMSTESTS_MSMS_TESTS_DIFFERENTIAL_EXPRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("msmsTests", "MSnbase")
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
    library(msmsTests)
    library(MSnbase)
    
    # ==========================================
    # --- Load and Pre-process Input Data ---
    # ==========================================
    
    # Read intensity/count matrix
    if (!file.exists("intensity.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'intensity.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts_df <- read.csv("intensity.csv", check.names = FALSE)
    if ("feature_id" %in% colnames(counts_df)) {
      rownames(counts_df) <- counts_df\$feature_id
      counts_df\$feature_id <- NULL
    } else {
      rownames(counts_df) <- counts_df[, 1]
      counts_df <- counts_df[, -1, drop = FALSE]
    }
    
    # Read column metadata
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    if (!all(c("sample", "condition") %in% colnames(coldata))) {
      stop("coldata.csv must contain 'sample' and 'condition' columns.")
    }
    
    # Align samples between counts and coldata
    rownames(coldata) <- coldata\$sample
    common_samples <- intersect(colnames(counts_df), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No matching samples found between intensity.csv and coldata.csv")
    }
    
    counts_df <- counts_df[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, , drop = FALSE]
    
    # Ensure counts are non-negative integers (required for spectral count GLMs)
    counts <- round(as.matrix(counts_df))
    counts[counts < 0] <- 0
    
    # Filter out features with all zero counts across all samples
    counts <- counts[rowSums(counts) > 0, , drop = FALSE]
    
    # Map 'condition' to 'treat' for consistency with vignette formulas
    colnames(coldata)[colnames(coldata) == "condition"] <- "treat"
    
    # ==========================================
    # --- Create MSnSet Object ---
    # ==========================================
    
    fd <- data.frame(row.names = rownames(counts))
    e <- new("MSnSet", 
             exprs = counts, 
             phenoData = new("AnnotatedDataFrame", data = coldata),
             featureData = new("AnnotatedDataFrame", data = fd))
    
    # Identify the two conditions to compare
    conditions <- unique(as.character(pData(e)\$treat))
    if (length(conditions) < 2) {
      stop("At least two distinct conditions are required in coldata.csv for differential testing.")
    }
    cond1 <- conditions[1]
    cond2 <- conditions[2]
    
    message(sprintf("Comparing condition '%s' vs '%s'", cond1, cond2))
    
    # ==========================================
    # --- Define Models and Normalization ---
    # ==========================================
    
    null.f <- "y~1"
    alt.f <- "y~treat"
    div <- apply(exprs(e), 2, sum)
    
    # ==========================================
    # --- Run Differential Expression Tests ---
    # ==========================================
    
    # 1. Poisson GLM (indicated for low number of replicates)
    message("Running Poisson GLM...")
    pois.res <- tryCatch({
      msms.glm.pois(e, alt.f, null.f, div = div)
    }, error = function(err) {
      warning("Poisson GLM failed: ", err\$message)
      NULL
    })
    
    # 2. Quasi-likelihood GLM (allows for overdispersion, requires >= 4 replicates)
    message("Running Quasi-likelihood GLM...")
    ql.res <- tryCatch({
      msms.glm.qlll(e, alt.f, null.f, div = div)
    }, error = function(err) {
      warning("Quasi-likelihood GLM failed: ", err\$message)
      NULL
    })
    
    # 3. Negative Binomial GLM (edgeR implementation)
    message("Running Negative Binomial GLM (edgeR)...")
    nb.res <- tryCatch({
      msms.edgeR(e, alt.f, null.f, div = div, fnm = "treat")
    }, error = function(err) {
      warning("Negative Binomial GLM failed: ", err\$message)
      NULL
    })
    
    # ==========================================
    # --- Post-test Filtering & Reproducibility ---
    # ==========================================
    
    alpha.cut <- 0.05
    SpC.cut <- 2
    lFC.cut <- 1
    
    # Helper function to apply post-test filters and format output
    process_results <- function(test.res, name) {
      if (is.null(test.res)) {
        # Return empty placeholder dataframe if test failed
        return(data.frame(LogFC=numeric(), p.value=numeric(), adjp=numeric(), DEP=logical()))
      }
      tbl <- test.results(test.res, e, pData(e)\$treat, cond1, cond2, div,
                          alpha = alpha.cut, minSpC = SpC.cut, minLFC = lFC.cut,
                          method = "BH")\$tres
      return(tbl)
    }
    
    pois.tbl <- process_results(pois.res, "Poisson")
    ql.tbl   <- process_results(ql.res, "Quasi-likelihood")
    nb.tbl   <- process_results(nb.res, "Negative-binomial")
    
    # Write results to CSV
    write.csv(pois.tbl, "pois_results.csv", row.names = TRUE)
    write.csv(ql.tbl, "ql_results.csv", row.names = TRUE)
    write.csv(nb.tbl, "nb_results.csv", row.names = TRUE)
    
    # ==========================================
    # --- Diagnostics and Visualization ---
    # ==========================================
    
    # Generate p-value by fold change frequency table for Quasi-likelihood
    if (!is.null(ql.res) && nrow(ql.tbl) > 0) {
      p_fc_table <- pval.by.fc(ql.tbl\$adjp, ql.tbl\$LogFC)
      write.csv(p_fc_table, "ql_pval_by_fc.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Message="Quasi-likelihood results unavailable"), "ql_pval_by_fc.csv")
    }
    
    # Generate Volcano Plots
    pdf("volcano_plots.pdf", width = 7, height = 7)
    par(mfrow = c(2, 2))
    
    if (nrow(pois.tbl) > 0) {
      tryCatch({
        res.volcanoplot(pois.tbl, max.pval = alpha.cut, min.LFC = lFC.cut)
        title("Poisson GLM")
      }, error = function(e) { plot.new(); text(0.5, 0.5, "Poisson Volcano Plot Failed") })
    }
    
    if (nrow(ql.tbl) > 0) {
      tryCatch({
        res.volcanoplot(ql.tbl, max.pval = alpha.cut, min.LFC = lFC.cut)
        title("Quasi-likelihood GLM")
      }, error = function(e) { plot.new(); text(0.5, 0.5, "QL Volcano Plot Failed") })
    }
    
    if (nrow(nb.tbl) > 0) {
      tryCatch({
        res.volcanoplot(nb.tbl, max.pval = alpha.cut, min.LFC = lFC.cut)
        title("Negative Binomial GLM")
      }, error = function(e) { plot.new(); text(0.5, 0.5, "NB Volcano Plot Failed") })
    }
    
    dev.off()
    
    message("Analysis complete. Outputs written successfully.")

    writeLines(c(
        '"BIOC_MSMSTESTS_MSMS_TESTS_DIFFERENTIAL_EXPRESSION":',
        paste0('    msmsTests: ', as.character(packageVersion('msmsTests')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msms_tests_differential_expression.csv versions.yml
    """
}

workflow BIOC_MSMSTESTS_MSMS_TESTS_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_MSMSTESTS_MSMS_TESTS_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_MSMSTESTS_MSMS_TESTS_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_MSMSTESTS_MSMS_TESTS_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_MSMSTESTS_MSMS_TESTS_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_MSMSTESTS_MSMS_TESTS_DIFFERENTIAL_EXPRESSION.out.versions
}
