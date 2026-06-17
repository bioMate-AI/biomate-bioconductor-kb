#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ASSIGN — assign_pathway_profiling
// Evaluate pathway deregulation and activation status in patient samples using a signature-based Bayesian factor analysis approach without training data.
// Input: counts.csv, coldata.csv
// Container: 1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ASSIGN
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASSIGN_ASSIGN_PATHWAY_PROFILING {
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
    .bm_deps <- c("ASSIGN")
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
    library(ASSIGN)
    
    # Create output directory
    output_dir <- "assign_outputs"
    if (!dir.exists(output_dir)) {
      dir.create(output_dir)
    }
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    # Read expression matrix (probe/gene-by-sample)
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) == 0) {
      stop("No matching sample names found between counts.csv and coldata.csv.")
    }
    
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # Convert to matrix and ensure data is log-transformed/normalized
    testData <- as.matrix(counts)
    if (max(testData, na.rm = TRUE) > 100) {
      message("Data values exceed 100; performing log2 transformation...")
      testData <- log2(testData + 1)
    }
    
    # ==========================================
    # --- Construct Pathway Signatures ---
    # ==========================================
    
    # Identify highly variable genes to construct mock pathway signatures
    row_vars <- apply(testData, 1, var)
    row_vars <- row_vars[!is.is.na(row_vars) & !is.nan(row_vars)]
    top_genes <- names(sort(row_vars, decreasing = TRUE))
    
    if (length(top_genes) < 40) {
      stop("Too few genes in the input matrix to build pathway signatures.")
    }
    
    # Create two distinct pathway signatures from the top variable genes
    n_genes_per_pathway <- min(30, floor(length(top_genes) / 2))
    geneList <- list(
      Pathway_A = top_genes[1:n_genes_per_pathway],
      Pathway_B = top_genes[(n_genes_per_pathway + 1):(2 * n_genes_per_pathway)]
    )
    
    # Extract test labels (conditions)
    testLabel <- coldata\$condition
    
    # ==========================================
    # --- Run ASSIGN Step-by-Step Pipeline ---
    # ==========================================
    
    message("Step 1: Preprocessing data...")
    processed.data <- assign.preprocess(
      trainingData = NULL,
      testData = testData,
      trainingLabel = NULL,
      geneList = geneList
    )
    
    message("Step 2: Running MCMC chain...")
    mcmc.chain <- assign.mcmc(
      Y = processed.data\$testData_sub,
      Bg = processed.data\$B_vector,
      X = processed.data\$S_matrix,
      Delta_prior_p = processed.data\$Pi_matrix,
      iter = 1000,
      adaptive_B = TRUE,
      adaptive_S = TRUE,
      mixture_beta = TRUE
    )
    
    message("Step 3: Checking convergence...")
    pdf(file.path(output_dir, "convergence_trace_plot.pdf"))
    trace.plot <- assign.convergence(
      test = mcmc.chain,
      burn_in = 0,
      iter = 1000,
      parameter = "B",
      whichGene = 1,
      whichSample = NA,
      whichPath = NA
    )
    dev.off()
    
    message("Step 4: Computing posterior summary...")
    mcmc.pos.mean <- assign.summary(
      test = mcmc.chain,
      burn_in = 500,
      iter = 1000,
      adaptive_B = TRUE,
      adaptive_S = TRUE,
      mixture_beta = TRUE
    )
    
    message("Step 5: Generating prediction outputs...")
    assign.output(
      processed.data = processed.data,
      mcmc.pos.mean.testData = mcmc.pos.mean,
      trainingData = NULL,
      testData = testData,
      trainingLabel = NULL,
      testLabel = testLabel,
      geneList = geneList,
      adaptive_B = TRUE,
      adaptive_S = TRUE,
      mixture_beta = TRUE,
      outputDir = output_dir
    )
    
    message("ASSIGN pipeline completed successfully. Outputs saved in '", output_dir, "'.")

    writeLines(c(
        '"BIOC_ASSIGN_ASSIGN_PATHWAY_PROFILING":',
        paste0('    ASSIGN: ', as.character(packageVersion('ASSIGN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_assign_pathway_profiling.csv versions.yml
    """
}

workflow BIOC_ASSIGN_ASSIGN_PATHWAY_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_ASSIGN_ASSIGN_PATHWAY_PROFILING(ch_input)

    emit:
    tables   = BIOC_ASSIGN_ASSIGN_PATHWAY_PROFILING.out.tables
    plots    = BIOC_ASSIGN_ASSIGN_PATHWAY_PROFILING.out.plots
    objects  = BIOC_ASSIGN_ASSIGN_PATHWAY_PROFILING.out.objects
    versions = BIOC_ASSIGN_ASSIGN_PATHWAY_PROFILING.out.versions
}
