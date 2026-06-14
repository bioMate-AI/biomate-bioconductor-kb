#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AMOUNTAIN — single_layer_module_detection
// Identify active gene modules in a single-layer weighted gene co-expression network and tune the module size using binary search or grid search.
// Input: W, z
// Container: quay.io/biocontainers/bioconductor-amountain:1.36.0--r45h57f0213_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AMOUNTAIN
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize search parameters for module size control
//  * 2. [Core Analysis] Run the gradient projection algorithm using moduleIdentificationGPFixSS inside a search loop to find the optimal alpha parameter
//  * 3. [Core Analysis] Extract the predicted module member indices

nextflow.enable.dsl = 2

process BIOC_AMOUNTAIN_SINGLE_LAYER_MODULE_DETECTION {
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
    .bm_deps <- c("AMOUNTAIN")
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
    library(AMOUNTAIN)
    
    # Helper function to read the weighted gene co-expression matrix (W)
    read_input_matrix <- function(prefix) {
      files <- list.files(pattern = paste0("^", prefix, "\\\\.(csv|tsv|txt|rds)\$"), ignore.case = TRUE)
      if (length(files) == 0) {
        stop(paste("Error: Could not find file for", prefix))
      }
      file_path <- files[1]
      message("Reading matrix from: ", file_path)
      
      if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
        return(as.matrix(readRDS(file_path)))
      }
      
      # Detect delimiter
      first_line <- readLines(file_path, n = 1)
      sep <- ","
      if (grepl("\t", first_line)) {
        sep <- "\t"
      } else if (grepl(";", first_line)) {
        sep <- ";"
      }
      
      # Try reading with first column as row names
      df <- tryCatch({
        read.table(file_path, header = TRUE, sep = sep, row.names = 1, check.names = FALSE)
      }, error = function(e) {
        read.table(file_path, header = TRUE, sep = sep, check.names = FALSE)
      })
      return(as.matrix(df))
    }
    
    # Helper function to read the node score vector (z)
    read_input_vector <- function(prefix, expected_len) {
      files <- list.files(pattern = paste0("^", prefix, "\\\\.(csv|tsv|txt|rds)\$"), ignore.case = TRUE)
      if (length(files) == 0) {
        stop(paste("Error: Could not find file for", prefix))
      }
      file_path <- files[1]
      message("Reading vector from: ", file_path)
      
      if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
        val <- readRDS(file_path)
        return(as.numeric(unlist(val)))
      }
      
      # Try reading lines directly
      lines <- readLines(file_path)
      lines <- lines[lines != ""]
      nums <- as.numeric(lines)
      if (sum(!is.na(nums)) >= expected_len) {
        return(nums[!is.na(nums)][1:expected_len])
      }
      
      # Try reading as CSV/TSV
      df <- read.csv(file_path, header = TRUE, check.names = FALSE)
      num_col <- sapply(df, is.numeric)
      if (any(num_col)) {
        val <- df[[which(num_col)[1]]]
        if (length(val) >= expected_len) {
          return(val[1:expected_len])
        }
      }
      
      # Fallback
      df <- read.table(file_path, header = TRUE, check.names = FALSE)
      val <- as.numeric(unlist(df))
      val <- val[!is.na(val)]
      if (length(val) >= expected_len) {
        return(val[1:expected_len])
      }
      
      stop("Could not parse a numeric vector of the expected length from ", file_path)
    }
    
    # 1. Read user input files
    W <- read_input_matrix("W")
    n <- nrow(W)
    z <- read_input_vector("z", n)
    
    # Ensure W is a numeric matrix and z is a numeric vector
    W <- matrix(as.numeric(W), nrow = n, ncol = ncol(W), dimnames = dimnames(W))
    z <- as.numeric(z)
    
    # 2. Initialize search parameters for module size control
    abegin = 0.01
    aend = 0.9
    
    # Dynamically adjust minsize and maxsize based on network size to prevent out-of-bounds issues
    if (n > 200) {
      maxsize = 200
      minsize = 100
    } else {
      maxsize = max(5, round(n * 0.4))
      minsize = max(2, round(n * 0.1))
    }
    
    message(sprintf("Starting binary search for alpha. Target module size: %d to %d nodes (Total nodes n = %d)", minsize, maxsize, n))
    
    # 3. Run the gradient projection algorithm inside a search loop to find the optimal alpha parameter
    for (i in 1:100) {
      # EXACT documented function call and arguments
      x <- moduleIdentificationGPFixSS(W,z,rep(1/n,n),a=(abegin+aend)/2,lambda = 0.001,maxiter = 500)
      predictedid <- which(x[[2]]!=0)
      
      current_size <- length(predictedid)
      current_alpha <- (abegin+aend)/2
      message(sprintf("Iteration %d: alpha = %.4f, identified module size = %d", i, current_alpha, current_size))
      
      if(current_size > maxsize){
        abegin <- (abegin+aend)/2
      }else if (current_size < minsize){
        aend <- (abegin+aend)/2
      }else {
        break
      }
    }
    
    # 4. Extract the final predicted module member indices
    predictedid <- which(x[[2]]!=0)
    message(sprintf("Search complete. Final module size: %d nodes at alpha = %.4f", length(predictedid), (abegin+aend)/2))
    
    # 5. Write named output files for the meaningful results
    gene_names <- if (!is.null(rownames(W))) rownames(W)[predictedid] else paste0("Gene_", predictedid)
    
    # Output 1: CSV table of predicted module members
    output_df <- data.frame(
      NodeIndex = predictedid,
      GeneName = gene_names,
      MembershipScore = x[[2]][predictedid]
    )
    write.csv(output_df, "predicted_module_members.csv", row.names = FALSE)
    message("Saved module members to 'predicted_module_members.csv'")
    
    # Output 2: RDS object containing full results
    results_list <- list(
      x = x,
      predicted_indices = predictedid,
      gene_names = gene_names,
      optimal_alpha = (abegin+aend)/2,
      parameters = list(
        lambda = 0.001,
        maxiter = 500,
        minsize = minsize,
        maxsize = maxsize
      )
    )
    saveRDS(results_list, "module_detection_results.rds")
    message("Saved full results object to 'module_detection_results.rds'")
    
    # Output 3: PDF plot of membership scores
    pdf("module_membership_plot.pdf", width = 8, height = 6)
    plot(x[[2]], type = "h", col = "darkgray", lwd = 1.5,
         xlab = "Node Index", ylab = "Membership Score",
         main = paste("Module Membership Scores (alpha =", round((abegin+aend)/2, 4), ")"))
    abline(h = 0, col = "black", lty = 2)
    if (length(predictedid) > 0) {
      points(predictedid, x[[2]][predictedid], col = "red", pch = 19, cex = 0.8)
      legend("topright", legend = c("Background", "Module Member"), col = c("darkgray", "red"), pch = c(NA, 19), lty = c(1, NA))
    }
    dev.off()
    message("Saved membership plot to 'module_membership_plot.pdf'")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_AMOUNTAIN_SINGLE_LAYER_MODULE_DETECTION":',
        paste0('    AMOUNTAIN: ', as.character(packageVersion('AMOUNTAIN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_layer_module_detection.csv versions.yml
    """
}

workflow BIOC_AMOUNTAIN_SINGLE_LAYER_MODULE_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ W, z ] ]

    main:
    BIOC_AMOUNTAIN_SINGLE_LAYER_MODULE_DETECTION(ch_input)

    emit:
    tables   = BIOC_AMOUNTAIN_SINGLE_LAYER_MODULE_DETECTION.out.tables
    plots    = BIOC_AMOUNTAIN_SINGLE_LAYER_MODULE_DETECTION.out.plots
    objects  = BIOC_AMOUNTAIN_SINGLE_LAYER_MODULE_DETECTION.out.objects
    versions = BIOC_AMOUNTAIN_SINGLE_LAYER_MODULE_DETECTION.out.versions
}
