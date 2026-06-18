#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kebabs — grid_search_and_model_selection
// Perform grid search and cross-validation to select the best sequence kernel and SVM hyperparameters.
// Input: sequences.fasta, labels.txt
// Container: quay.io/biocontainers/bioconductor-kebabs:1.44.0--r45ha27e39d_0
// R packages: Biostrings, kebabs
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, kebabs
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define candidate kernels
//  * 2. [Core Analysis] Run grid search with cross-validation using kbsvm
//  * 3. [Core Analysis] Extract model selection results
//  * 4. [Visualization & Output] Plot performance across the grid

nextflow.enable.dsl = 2

process BIOC_KEBABS_GRID_SEARCH_AND_MODEL_SELECTION {
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
    .bm_deps <- c("Biostrings", "kebabs")
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
    library(kebabs)
    library(Biostrings)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Read User Input and Prepare Data
    # -----------------------------------------------------------------------------
    
    if (!file.exists("sequences.fasta")) {
      stop("Error: 'sequences.fasta' not found in the working directory.")
    }
    
    if (!file.exists("labels.txt")) {
      stop("Error: 'labels.txt' not found in the working directory.")
    }
    
    # Read biological sequences (assumed to be amino acid sequences for coiled-coil/gappy kernels)
    ccseq <- readAAStringSet("sequences.fasta")
    
    # Read class labels
    yCC <- as.numeric(readLines("labels.txt"))
    
    if (length(ccseq) != length(yCC)) {
      stop("Error: The number of sequences does not match the number of labels.")
    }
    
    # To support the annotation-specific kernel (gappya), we assign a default
    # annotation of 'a's matching the length of each sequence.
    seq_lengths <- width(ccseq)
    ccannot <- sapply(seq_lengths, function(l) {
      paste(rep("a", l), collapse = "")
    })
    annotationMetadata(ccseq, annCharset = "abcdefg") <- ccannot
    
    # Define candidate kernels
    gappy <- gappyPairKernel(k = 1, m = 10)
    gappya <- gappyPairKernel(k = 1, m = 10, annSpec = TRUE)
    
    # Define training partition (e.g., 80% of the data)
    set.seed(123)
    n_samples <- length(ccseq)
    if (n_samples < 5) {
      stop("Error: At least 5 samples are required to perform 5-fold cross-validation.")
    }
    train <- sample(1:n_samples, max(5, floor(0.8 * n_samples)))
    
    # -----------------------------------------------------------------------------
    # Stage 2: Run Grid Search with Cross-Validation using kbsvm
    # -----------------------------------------------------------------------------
    
    model <- kbsvm(ccseq[train], y=yCC[train],
                   kernel=c(gappy, gappya), pkg="LiblineaR", svm="C-svc",
                   cost=c(1, 10, 50, 100, 200, 500), explicit="yes", cross=5,
                   perfParameters="ALL", perfObjective="BACC",
                   showProgress=TRUE)
    
    # -----------------------------------------------------------------------------
    # Stage 3: Extract Model Selection Results
    # -----------------------------------------------------------------------------
    
    result <- modelSelResult(model)
    perfData <- performance(result)
    
    # -----------------------------------------------------------------------------
    # Stage 4: Plot Performance Across the Grid and Save Outputs
    # -----------------------------------------------------------------------------
    
    # Save the plot to a PDF file
    pdf("model_selection_plot.pdf", width = 7, height = 5)
    plot(result, sel="BACC")
    dev.off()
    
    # Save meaningful results to files
    saveRDS(model, file = "kebabs_model.rds")
    saveRDS(result, file = "model_selection_result.rds")
    saveRDS(perfData, file = "performance_data.rds")
    
    # Export BACC performance grid to CSV if available
    if (!is.null(perfData\$BACC)) {
      write.csv(perfData\$BACC, file = "performance_bacc.csv", row.names = TRUE)
    }
    
    cat("Pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_KEBABS_GRID_SEARCH_AND_MODEL_SELECTION":',
        paste0('    kebabs: ', as.character(packageVersion('kebabs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_grid_search_and_model_selection.csv versions.yml
    """
}

workflow BIOC_KEBABS_GRID_SEARCH_AND_MODEL_SELECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sequences.fasta, labels.txt ] ]

    main:
    BIOC_KEBABS_GRID_SEARCH_AND_MODEL_SELECTION(ch_input)

    emit:
    tables   = BIOC_KEBABS_GRID_SEARCH_AND_MODEL_SELECTION.out.tables
    plots    = BIOC_KEBABS_GRID_SEARCH_AND_MODEL_SELECTION.out.plots
    objects  = BIOC_KEBABS_GRID_SEARCH_AND_MODEL_SELECTION.out.objects
    versions = BIOC_KEBABS_GRID_SEARCH_AND_MODEL_SELECTION.out.versions
}
