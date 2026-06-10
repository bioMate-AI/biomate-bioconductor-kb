#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: globaltest — graph_structured_multiple_testing
// Perform multiple testing correction on structured, nested subsets of covariates using Focus Level or Inheritance methods.
// Input: Y, X
// Container: quay.io/biocontainers/bioconductor-globaltest:5.64.0--r45hdfd78af_0
// R packages: globaltest
// Bioconductor: 3.20 | R: 4.4
// Requires: globaltest
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the DAG or tree structure of covariate subsets
//  * 2. [Core Analysis] Run focusLevel() or inheritance() to adjust p-values
//  * 3. [Core Analysis] Identify significant leaf nodes using leafNodes()
//  * 4. [Visualization & Output] Plot the significant subgraph using draw()

nextflow.enable.dsl = 2

process BIOC_GLOBALTEST_GRAPH_STRUCTURED_MULTIPLE_TESTING {
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
    .bm_deps <- c("globaltest")
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
    library(globaltest)
    
    # -------------------------------------------------------------------------
    # 1. Read User Input Files
    # -------------------------------------------------------------------------
    # Read Y (numeric vector of response values)
    if (file.exists("Y.rds")) {
      Y <- readRDS("Y.rds")
    } else if (file.exists("Y.csv")) {
      Y <- as.numeric(read.csv("Y.csv", header = FALSE)[, 1])
    } else if (file.exists("Y.txt")) {
      Y <- scan("Y.txt", quiet = TRUE)
    } else {
      stop("Error: Response file 'Y' (Y.rds, Y.csv, or Y.txt) not found in the working directory.")
    }
    
    # Read X (matrix of covariate measurements)
    if (file.exists("X.rds")) {
      X <- readRDS("X.rds")
    } else if (file.exists("X.csv")) {
      X <- as.matrix(read.csv("X.csv", header = FALSE))
    } else if (file.exists("X.txt")) {
      X <- as.matrix(read.table("X.txt", header = FALSE))
    } else {
      stop("Error: Covariate file 'X' (X.rds, X.csv, or X.txt) not found in the working directory.")
    }
    
    # Ensure X has column names for the clustering and testing methods
    if (is.null(colnames(X))) {
      colnames(X) <- paste0("V", seq_len(ncol(X)))
    }
    
    # -------------------------------------------------------------------------
    # 2. Execute Documented Workflow
    # -------------------------------------------------------------------------
    res <- gt(Y, X)
    hc <- hclust(dist(t(X)))
    res <- inheritance(res, hc)
    leaves <- leafNodes(res)
    
    # -------------------------------------------------------------------------
    # 3. Save Outputs
    # -------------------------------------------------------------------------
    # Save the result object
    saveRDS(res, "focus_level_result.rds")
    
    # Save the significant leaf nodes to CSV
    tryCatch({
      write.csv(result(leaves), "significant_leaf_nodes.csv", row.names = TRUE)
    }, error = function(e) {
      tryCatch({
        write.csv(as.data.frame(leaves), "significant_leaf_nodes.csv", row.names = TRUE)
      }, error = function(e2) {
        sink("significant_leaf_nodes.txt")
        print(leaves)
        sink()
      })
    })
    
    # Save the plot to PDF
    pdf("focus_level_plot.pdf", width = 10, height = 8)
    draw(res, names=TRUE)
    dev.off()

    writeLines(c(
        '"BIOC_GLOBALTEST_GRAPH_STRUCTURED_MULTIPLE_TESTING":',
        paste0('    globaltest: ', as.character(packageVersion('globaltest')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_graph_structured_multiple_testing.csv versions.yml
    """
}

workflow BIOC_GLOBALTEST_GRAPH_STRUCTURED_MULTIPLE_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y, X ] ]

    main:
    BIOC_GLOBALTEST_GRAPH_STRUCTURED_MULTIPLE_TESTING(ch_input)

    emit:
    tables   = BIOC_GLOBALTEST_GRAPH_STRUCTURED_MULTIPLE_TESTING.out.tables
    plots    = BIOC_GLOBALTEST_GRAPH_STRUCTURED_MULTIPLE_TESTING.out.plots
    objects  = BIOC_GLOBALTEST_GRAPH_STRUCTURED_MULTIPLE_TESTING.out.objects
    versions = BIOC_GLOBALTEST_GRAPH_STRUCTURED_MULTIPLE_TESTING.out.versions
}
