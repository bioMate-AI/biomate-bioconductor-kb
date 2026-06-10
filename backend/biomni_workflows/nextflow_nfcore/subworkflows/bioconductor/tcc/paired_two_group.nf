#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TCC — paired_two_group
// Perform robust differential expression analysis on paired two-group RNA-seq count data without replicates.
// Input: hypoData, cl
// Container: quay.io/biocontainers/bioconductor-tcc:1.50.0--r45hdfd78af_0
// R packages: TCC
// Bioconductor: 3.20 | R: 4.4
// Requires: TCC
// Visualizations: plot (ggplot/base)
// QC: TMM normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Construct a TCC class object using the raw count matrix and the design data frame. 2. Calculate robust normalization factors using

nextflow.enable.dsl = 2

process BIOC_TCC_PAIRED_TWO_GROUP {
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
    .bm_deps <- c("TCC")
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
        library(TCC)
        
        # -----------------------------------------------------------------------------
        # Stage 1: Read User Input Files and Construct TCC Object
        # -----------------------------------------------------------------------------
        
        # Read hypoData (matrix of raw integer counts)
        if (file.exists("hypoData.rds")) {
          hypoData <- readRDS("hypoData.rds")
        } else if (file.exists("hypoData.csv")) {
          hypoData <- read.csv("hypoData.csv", row.names = 1, check.names = FALSE)
        } else if (file.exists("hypoData.tsv")) {
          hypoData <- read.delim("hypoData.tsv", row.names = 1, check.names = FALSE)
        } else {
          stop("Error: hypoData file (RDS, CSV, or TSV) not found in the working directory.")
        }
        
        # Ensure hypoData is a matrix of integers
        hypoData <- as.matrix(hypoData)
        storage.mode(hypoData) <- "integer"
        
        # Read cl (data frame containing group and pair/individual identifiers)
        if (file.exists("cl.rds")) {
          cl <- readRDS("cl.rds")
        } else if (file.exists("cl.csv")) {
          cl <- read.csv("cl.csv", header = TRUE, check.names = FALSE)
        } else if (file.exists("cl.tsv")) {
          cl <- read.delim("cl.tsv", header = TRUE, check.names = FALSE)
        } else {
          stop("Error: cl file (RDS, CSV, or TSV) not found in the working directory.")
        }
        
        # Ensure cl is a data frame
        cl <- as.data.frame(cl)
        
        # Construct the TCC class object
        tcc <- new("TCC", hypoData, cl)
        
        # -----------------------------------------------------------------------------
        # Stage 2: Calculate Robust Normalization Factors (Paired DEGES/edgeR)
        # -----------------------------------------------------------------------------
        tcc <- calcNormFactors(tcc, norm.method = "tmm", test.method = "edger",
                               iteration = 3, FDR = 0.1, floorPDEG = 0.05, paired = TRUE)
        
        # -----------------------------------------------------------------------------
        # Stage 3: Perform Paired Differential Expression Analysis
        # -----------------------------------------------------------------------------
        tcc <- estimateDE(tcc, test.method = "edger", FDR = 0.1, paired = TRUE)
        
        # -----------------------------------------------------------------------------
        # Stage 4: Retrieve Results and Generate Outputs
        # -----------------------------------------------------------------------------
        # Retrieve the sorted results table
        result <- getResult(tcc, sort = TRUE)
        
        # Print head of results and DEG summary table to console
        cat("First few rows of the DE analysis results:\n")
        print(head(result))
        
        cat("\nSummary of estimated DEGs (0 = non-DEG, 1 = DEG):\n")
        deg_table <- table(tcc\$estimatedDEG)
        print(deg_table)
        
        # Write results table to CSV
        write.csv(result, "tcc_paired_de_results.csv", row.names = FALSE)
        
        # Write DEG summary table to CSV
        write.csv(as.data.frame(deg_table), "tcc_deg_summary.csv", row.names = FALSE)
        
        # Save the final TCC object as an RDS file
        saveRDS(tcc, "tcc_completed_object.rds")
        
        # Generate and save the M-A plot to a PDF file
        pdf("tcc_ma_plot.pdf", width = 7, height = 7)
        plot(tcc)
        dev.off()
        
        cat("\nPipeline completed successfully. Outputs written to:\n")
        cat("- tcc_paired_de_results.csv\n")
        cat("- tcc_deg_summary.csv\n")
        cat("- tcc_completed_object.rds\n")
        cat("- tcc_ma_plot.pdf\n")

    writeLines(c(
        '"BIOC_TCC_PAIRED_TWO_GROUP":',
        paste0('    TCC: ', as.character(packageVersion('TCC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paired_two_group.csv versions.yml
    """
}

workflow BIOC_TCC_PAIRED_TWO_GROUP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hypoData, cl ] ]

    main:
    BIOC_TCC_PAIRED_TWO_GROUP(ch_input)

    emit:
    tables   = BIOC_TCC_PAIRED_TWO_GROUP.out.tables
    plots    = BIOC_TCC_PAIRED_TWO_GROUP.out.plots
    objects  = BIOC_TCC_PAIRED_TWO_GROUP.out.objects
    versions = BIOC_TCC_PAIRED_TWO_GROUP.out.versions
}
