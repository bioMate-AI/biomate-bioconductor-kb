#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MBttest — differential_expression_analysis
// Identify differentially expressed genes or isoforms between two conditions with small sample sizes using multiple beta t-tests.
// Input: count_matrix.csv
// Container: quay.io/biocontainers/bioconductor-mbttest:1.38.0--r45hdfd78af_0
// R packages: MBttest
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mbttest:1.38.0--r45hdfd78af_0"

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
    .bm_deps <- c("MBttest")
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
    
    # Load required library
    library(MBttest)
    
    # Check if input file exists
    input_file <- "count_matrix.csv"
    if (!file.exists(input_file)) {
      stop(paste("Error: Input file", input_file, "not found in the working directory."))
    }
    
    # Read the user input count matrix
    real_data <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE)
    
    # Dynamically determine the number of annotation columns (nci)
    # We assume annotation columns are on the left, and count columns are on the right.
    # Find the last column that is NOT numeric (character/factor) to set the boundary.
    non_num_cols <- which(!sapply(real_data, is.numeric))
    if (length(non_num_cols) > 0) {
      nci <- max(non_num_cols)
    } else {
      # Fallback if all columns are numeric
      nci <- ifelse(ncol(real_data) > 6, 2, 1)
    }
    
    # Determine the number of replicates for each condition (na and nb)
    # We assume the remaining columns are split equally between the two conditions.
    n_counts <- ncol(real_data) - nci
    na <- floor(n_counts / 2)
    nb <- n_counts - na
    
    message(paste("Detected parameters - Annotation columns (nci):", nci))
    message(paste("Detected parameters - Condition A replicates (na):", na))
    message(paste("Detected parameters - Condition B replicates (nb):", nb))
    
    # 1. Simulate null count data from real data using simulat
    # We use a subset of up to 500 rows to keep the simulation fast and faithful to the vignette
    sub_data_sim <- real_data[1:min(500, nrow(real_data)), ]
    sjknull1 <- simulat(yy = sub_data_sim, nci = nci, r1 = na, r2 = nb, p = 0, q = 0.2)
    
    # 2. Run multiple beta t-tests on the simulated null data using smbetattest to identify false positives
    mysim1 <- smbetattest(X = sjknull1, na = na, nb = nb, alpha = 0.05)
    
    # Save simulation results
    write.csv(mysim1, "simulated_null_results.csv", row.names = FALSE)
    
    # 3. Calculate the threshold parameter omega (W) by sorting and analyzing the rho values of false positives
    # False positives are identified by symb == "+"
    fps <- mysim1[trimws(as.character(mysim1\$symb)) == "+", ]
    if (nrow(fps) > 0) {
      rho_vals <- sort(fps\$rho)
      N <- length(rho_vals)
      q_vals <- (1:N) / N
      # Find the largest index i where q_vals[i] <= 0.85
      idx <- which(q_vals <= 0.85)
      if (length(idx) > 0) {
        W_val <- rho_vals[max(idx)]
      } else {
        W_val <- rho_vals[1]
      }
    } else {
      W_val <- 1.0 # Default fallback if no false positives are found
    }
    message(paste("Calculated omega (W) threshold parameter:", W_val))
    
    # 4. Normalize the real count data to ensure equal library sizes
    count_cols <- (nci + 1):(nci + na + nb)
    counts <- real_data[, count_cols]
    lib_sizes <- colSums(counts)
    mean_lib_size <- mean(lib_sizes)
    
    normalized_counts <- counts
    for (j in 1:ncol(counts)) {
      normalized_counts[, j] <- (counts[, j] * mean_lib_size) / lib_sizes[j]
    }
    
    normalized_data <- real_data
    normalized_data[, count_cols] <- normalized_counts
    
    # 5. Perform the multiple beta t-test on the normalized real data using mbetattest
    # We use the whole normalized dataset
    res <- mbetattest(X = normalized_data, na = na, nb = nb, W = W_val, alpha = 0.05, file = "jurkat_NS_48h_tag_mbetattest.csv")
    
    # Save the results object as RDS for downstream analysis
    saveRDS(res, "mbetattest_results.rds")
    
    # 6. Visualize the results using maplot and myheatmap
    dat <- res
    
    pdf("differential_expression_plots.pdf", width = 10, height = 8)
    
    tryCatch({
      maplot(dat = dat, r1 = na, r2 = nb, TT = 350, matitle = "MA plot")
    }, error = function(e) {
      warning("Failed to generate MA plot (TT=350): ", e\$message)
    })
    
    tryCatch({
      maplot(dat = dat, r1 = na, r2 = nb, TT = 50, matitle = "MA plot")
    }, error = function(e) {
      warning("Failed to generate MA plot (TT=50): ", e\$message)
    })
    
    tryCatch({
      myheatmap(dat = dat, r1 = na, r2 = nb, maptitle = "Jurkat T-cell heatmap2")
    }, error = function(e) {
      warning("Failed to generate heatmap2: ", e\$message)
    })
    
    tryCatch({
      myheatmap(dat = dat, r1 = na, r2 = nb, tree = "none", maptitle = "Jurkat T-cell heatmap3")
    }, error = function(e) {
      warning("Failed to generate heatmap3: ", e\$message)
    })
    
    tryCatch({
      myheatmap(dat = dat, r1 = na, r2 = nb, colrs = "redblue", tree = "column", method = "pearson", maptitle = "Jurkat T-cell heatmap")
    }, error = function(e) {
      warning("Failed to generate heatmap: ", e\$message)
    })
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'jurkat_NS_48h_tag_mbetattest.csv', 'mbetattest_results.rds', and 'differential_expression_plots.pdf'.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS":
        MBttest: \$(Rscript -e 'cat(as.character(packageVersion("MBttest")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_expression_analysis.csv versions.yml
    """
}

workflow BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_matrix.csv ] ]

    main:
    BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.objects
    versions = BIOC_MBTTEST_DIFFERENTIAL_EXPRESSION_ANALYSIS.out.versions
}
