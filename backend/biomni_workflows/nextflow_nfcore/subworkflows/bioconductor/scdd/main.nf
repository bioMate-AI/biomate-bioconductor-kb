#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scDD — differential_distribution_analysis
// Identify and classify differentially distributed genes between two biological conditions in single-cell RNA-seq data.
// Input: expression_matrix.csv, metadata.csv
// Container: quay.io/biocontainers/bioconductor-scdd:1.34.0--r45hdfd78af_0
// R packages: gridExtra, scDD, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, gridExtra, scDD
// Visualizations: violin plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct a SingleCellExperiment object from the expression matrices and condition labels
//  * 2. [Core Analysis] Preprocess the data to filter out genes with high zero proportions and apply normalization
//  * 3. [Input & Preparation] Define the prior parameters for the mixture model
//  * 4. [Core Analysis] Run the scDD engine to test for differential distributions and classify genes
//  * 5. [Core Analysis] Extract the main results and partition estimates
//  * 6. [Visualization & Output] Visualize the expression distributions of significant genes using side-by-side violin plots

nextflow.enable.dsl = 2

process BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS {
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
    .bm_deps <- c("gridExtra", "scDD", "SingleCellExperiment")
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
    library(scDD)
    library(gridExtra)
    
    # ==========================================
    # 1. Load User Input and Construct SCE Object
    # ==========================================
    
    if (!file.exists("expression_matrix.csv") || !file.exists("metadata.csv")) {
      stop("Required input files 'expression_matrix.csv' and/or 'metadata.csv' are missing in the working directory.")
    }
    
    # Read expression matrix and metadata
    expr_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    meta_df <- read.csv("metadata.csv", row.names = 1, check.names = FALSE)
    
    # Align cells between expression matrix and metadata
    common_cells <- intersect(colnames(expr_df), rownames(meta_df))
    if (length(common_cells) == 0) {
      stop("No common cells found between expression matrix columns and metadata rows.")
    }
    
    expr_mat <- as.matrix(expr_df[, common_cells, drop = FALSE])
    meta_df <- meta_df[common_cells, , drop = FALSE]
    
    # Ensure condition column exists
    if (!"condition" %in% colnames(meta_df)) {
      colnames(meta_df)[1] <- "condition"
    }
    
    # Construct condition vector and ensure it is numeric 1 and 2
    condition <- as.numeric(as.factor(meta_df\$condition))
    names(condition) <- colnames(expr_mat)
    
    # Construct SingleCellExperiment object
    sce <- SingleCellExperiment(
      assays = list(counts = expr_mat, normcounts = expr_mat), 
      colData = data.frame(condition)
    )
    
    # ==========================================
    # 2. Preprocess the Data
    # ==========================================
    
    scDatEx <- sce
    scDatEx <- preprocess(scDatEx, zero.thresh = 0.9)
    
    # Apply scran normalization with fallback if it fails
    scDatEx.scran <- tryCatch({
      preprocess(scDatEx, zero.thresh = 0.5, scran_norm = TRUE)
    }, error = function(e) {
      warning("scran normalization failed, falling back to standard preprocessing: ", e\$message)
      preprocess(scDatEx, zero.thresh = 0.5, scran_norm = FALSE)
    })
    
    # Set up the object for the scDD engine
    scDatExSim <- scDatEx.scran
    
    # ==========================================
    # 3. Define Prior Parameters
    # ==========================================
    
    prior_param <- list(alpha = 0.01, mu0 = 0, s0 = 0.01, a0 = 0.01, b0 = 0.01)
    
    # ==========================================
    # 4. Run scDD Engine (Fast KS Test)
    # ==========================================
    
    scDatExSim <- scDD(scDatExSim, prior_param = prior_param, testZeroes = FALSE)
    
    # ==========================================
    # 5. Extract Results and Partition Estimates
    # ==========================================
    
    RES <- results(scDatExSim)
    PARTITION.C1 <- results(scDatExSim, type = "Zhat.c1")
    
    # Save intermediate results
    write.csv(RES, "scDD_results_fast.csv", row.names = FALSE)
    write.csv(as.data.frame(PARTITION.C1), "scDD_partition_c1.csv", row.names = TRUE)
    
    # ==========================================
    # 6. Save Final Object
    # ==========================================
    
    # Save final results
    saveRDS(scDatExSim, "scDD_final_object.rds")
    
    # ==========================================
    # 7. Visualize Expression Distributions
    # ==========================================
    
    # Identify top genes to plot
    if ("nonzero.pvalue.adj" %in% colnames(RES)) {
      top_genes <- as.character(RES\$gene[order(RES\$nonzero.pvalue.adj)])
    } else {
      top_genes <- as.character(RES\$gene)
    }
    
    # Generate the primary violin plot for the first gene
    de <- sideViolin(normcounts(scDatExSim)[top_genes[1],], scDatExSim\$condition, title.gene = top_genes[1])
    
    # Safely define remaining plots to prevent out-of-bounds errors if the dataset has few genes
    dp <- if (length(top_genes) >= 2) {
      sideViolin(normcounts(scDatExSim)[top_genes[2],], scDatExSim\$condition, title.gene = top_genes[2])
    } else { de }
    
    dm <- if (length(top_genes) >= 3) {
      sideViolin(normcounts(scDatExSim)[top_genes[3],], scDatExSim\$condition, title.gene = top_genes[3])
    } else { de }
    
    db <- if (length(top_genes) >= 4) {
      sideViolin(normcounts(scDatExSim)[top_genes[4],], scDatExSim\$condition, title.gene = top_genes[4])
    } else { de }
    
    ep <- if (length(top_genes) >= 5) {
      sideViolin(normcounts(scDatExSim)[top_genes[5],], scDatExSim\$condition, title.gene = top_genes[5])
    } else { de }
    
    ee <- if (length(top_genes) >= 6) {
      sideViolin(normcounts(scDatExSim)[top_genes[6],], scDatExSim\$condition, title.gene = top_genes[6])
    } else { de }
    
    # Arrange and save the plots to a PDF file
    pdf("scDD_violin_plots.pdf", width = 8.5, height = 11)
    grid.arrange(de, dp, dm, db, ep, ee, ncol = 2)
    dev.off()

    writeLines(c(
        '"BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS":',
        paste0('    scDD: ', as.character(packageVersion('scDD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_distribution_analysis.csv versions.yml
    """
}

workflow BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, metadata.csv ] ]

    main:
    BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.tables
    plots    = BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.plots
    objects  = BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.objects
    versions = BIOC_SCDD_DIFFERENTIAL_DISTRIBUTION_ANALYSIS.out.versions
}
