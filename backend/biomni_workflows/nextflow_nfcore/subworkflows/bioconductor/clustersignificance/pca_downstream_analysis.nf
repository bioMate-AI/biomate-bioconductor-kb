#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ClusterSignificance — pca_downstream_analysis
// Assess class cluster separation downstream of Principal Component Analysis (PCA).
// Input: expression, classes
// Container: quay.io/biocontainers/bioconductor-clustersignificance:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ClusterSignificance
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform PCA using prcomp
//  * 2. [Core Analysis] Project PCA matrix using pcp with normalization
//  * 3. [Core Analysis] Classify and score the separation using classify
//  * 4. [Core Analysis] Run permutation testing using permute
//  * 5. [Core Analysis] Extract p-values and confidence intervals using pvalue and conf.int

nextflow.enable.dsl = 2

process BIOC_CLUSTERSIGNIFICANCE_PCA_DOWNSTREAM_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("ClusterSignificance")
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
    library(ClusterSignificance)
    
    # Helper function to find and read the expression matrix
    find_and_read_expression <- function() {
      files <- list.files(pattern = "^expression\\\\.(csv|tsv|txt|rds)\$", ignore.case = TRUE)
      if (length(files) == 0) {
        if (file.exists("expression")) {
          files <- "expression"
        } else {
          stop("Expression file ('expression.csv', 'expression.tsv', 'expression.rds', etc.) not found in the working directory.")
        }
      }
      file <- files[1]
      message("Reading expression from: ", file)
      if (grepl("\\\\.rds\$", file, ignore.case = TRUE)) {
        return(readRDS(file))
      } else if (grepl("\\\\.csv\$", file, ignore.case = TRUE)) {
        return(as.matrix(read.csv(file, row.names = 1, check.names = FALSE)))
      } else {
        return(as.matrix(read.delim(file, row.names = 1, check.names = FALSE)))
      }
    }
    
    # Helper function to find and read the classes vector
    find_and_read_classes <- function(expected_length) {
      files <- list.files(pattern = "^classes\\\\.(csv|tsv|txt|rds)\$", ignore.case = TRUE)
      if (length(files) == 0) {
        if (file.exists("classes")) {
          files <- "classes"
        } else {
          stop("Classes file ('classes.csv', 'classes.tsv', 'classes.txt', 'classes.rds', etc.) not found in the working directory.")
        }
      }
      file <- files[1]
      message("Reading classes from: ", file)
      
      if (grepl("\\\\.rds\$", file, ignore.case = TRUE)) {
        classes <- as.character(readRDS(file))
      } else if (grepl("\\\\.txt\$", file, ignore.case = TRUE) || file == "classes") {
        classes <- readLines(file)
      } else {
        df <- read.csv(file, header = FALSE, stringsAsFactors = FALSE)
        classes <- as.character(df[[1]])
        # If the length is off by 1, it might have read a header. Try reading with header = TRUE.
        if (length(classes) != expected_length && nrow(df) > 1) {
          df_h <- read.csv(file, header = TRUE, stringsAsFactors = FALSE)
          classes <- as.character(df_h[[1]])
        }
      }
      return(classes)
    }
    
    # 1. Read User Input Files
    expression <- find_and_read_expression()
    classes <- find_and_read_classes(nrow(expression))
    
    # Validate inputs
    if (nrow(expression) != length(classes)) {
      stop(sprintf("Dimension mismatch: expression has %d rows (samples), but classes has %d elements.", 
                   nrow(expression), length(classes)))
    }
    
    # Set up PDF output for plots
    pdf("cluster_significance_plots.pdf", width = 10, height = 8)
    
    # 2. Perform PCA using prcomp
    pca <- prcomp(expression, scale = TRUE)
    mat <- pca\$x
    
    # 3. Project PCA matrix using pcp with normalization
    ob <- pcp(mat, classes, normalize = TRUE)
    plot(ob)
    
    # 4. Classify and score the separation using classify
    cl <- classify(ob)
    plot(cl)
    
    # 5. Run permutation testing using permute
    iterations <- 100
    pe <- permute(mat = mat, iter = iterations, classes = classes, projmethod = "pcp")
    
    # Try to plot permutation results if supported/applicable
    tryCatch({
      plot(pe)
    }, error = function(e) {
      warning("Could not plot permutation object: ", e\$message)
    })
    
    # Close PDF device
    dev.off()
    
    # 6. Extract p-values and confidence intervals
    p_vals <- pvalue(pe)
    conf_ints <- conf.int(pe)
    
    # Print results to console
    cat("\n--- P-values ---\n")
    print(p_vals)
    cat("\n--- Confidence Intervals ---\n")
    print(conf_ints)
    
    # 7. Write named output files for the meaningful results
    write.csv(as.data.frame(p_vals), "pvalues.csv", row.names = TRUE)
    write.csv(as.data.frame(conf_ints), "confidence_intervals.csv", row.names = TRUE)
    
    saveRDS(ob, "pcp_projection.rds")
    saveRDS(cl, "classification.rds")
    saveRDS(pe, "permutation_results.rds")
    
    message("\nPipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_CLUSTERSIGNIFICANCE_PCA_DOWNSTREAM_ANALYSIS":',
        paste0('    ClusterSignificance: ', as.character(packageVersion('ClusterSignificance')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pca_downstream_analysis.csv versions.yml
    """
}

workflow BIOC_CLUSTERSIGNIFICANCE_PCA_DOWNSTREAM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression, classes ] ]

    main:
    BIOC_CLUSTERSIGNIFICANCE_PCA_DOWNSTREAM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CLUSTERSIGNIFICANCE_PCA_DOWNSTREAM_ANALYSIS.out.tables
    plots    = BIOC_CLUSTERSIGNIFICANCE_PCA_DOWNSTREAM_ANALYSIS.out.plots
    objects  = BIOC_CLUSTERSIGNIFICANCE_PCA_DOWNSTREAM_ANALYSIS.out.objects
    versions = BIOC_CLUSTERSIGNIFICANCE_PCA_DOWNSTREAM_ANALYSIS.out.versions
}
