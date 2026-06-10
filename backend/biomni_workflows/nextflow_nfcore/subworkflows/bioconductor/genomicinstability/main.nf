#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomicInstability — unsupervised_gia
// Estimate genomic instability scores and neoplastic likelihood for single cells without a prior normal reference.
// Input: tpm_matrix
// Container: quay.io/biocontainers/bioconductor-genomicinstability:1.16.0--r45hdfd78af_0
// R packages: ExperimentHub, genomicInstability, pROC, SingleCellExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: genomicInstability
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Estimate association between gene expression and loci-blocks using inferCNV()
//  * 2. [Core Analysis] Calculate the Genomic Instability Score (GIS) using genomicInstabilityScore()
//  * 3. [Core Analysis] Estimate the relative likelihood of cells being neoplastic using giLikelihood()
//  * 4. [Visualization & Output] Plot the GIS density and fitted Gaussian models using giDensityPlot()
//  * 5. [Core Analysis] Refine likelihood estimation by manually specifying normal and tumor components in giLikelihood()

nextflow.enable.dsl = 2

process BIOC_GENOMICINSTABILITY_UNSUPERVISED_GIA {
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
    .bm_deps <- c("ExperimentHub", "genomicInstability", "pROC", "SingleCellExperiment")
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
    library(genomicInstability)
    
    # Helper function to read the input tpm_matrix from the working directory
    read_tpm_matrix <- function() {
      possible_files <- c("tpm_matrix", "tpm_matrix.rds", "tpm_matrix.csv", "tpm_matrix.tsv", "tpm_matrix.txt")
      found_file <- NULL
      for (f in possible_files) {
        if (file.exists(f)) {
          found_file <- f
          break
        }
      }
      
      if (is.null(found_file)) {
        stop("Error: Required input file 'tpm_matrix' (or with .rds, .csv, .tsv, .txt extension) not found in the working directory.")
      }
      
      message("Reading input file: ", found_file)
      
      # Determine file type and read
      if (grepl("\\\\.rds\$", found_file, ignore.case = TRUE)) {
        mat <- readRDS(found_file)
      } else {
        # Try reading as RDS first in case 'tpm_matrix' has no extension but is RDS
        mat <- tryCatch({
          readRDS(found_file)
        }, error = function(e) {
          # If not RDS, try reading as text/csv
          first_line <- readLines(found_file, n = 1)
          sep <- if (grepl("\t", first_line)) "\t" else ","
          as.matrix(read.table(found_file, header = TRUE, row.names = 1, sep = sep, check.names = FALSE))
        })
      }
      
      if (!is.matrix(mat)) {
        mat <- as.matrix(mat)
      }
      return(mat)
    }
    
    # Read the user input
    tpm_matrix <- read_tpm_matrix()
    
    # 1. Estimate association between gene expression and loci-blocks
    message("Running inferCNV...")
    cnv <- inferCNV(tpm_matrix)
    
    # 2. Calculate the Genomic Instability Score (GIS)
    message("Running genomicInstabilityScore...")
    cnv <- genomicInstabilityScore(cnv)
    
    # 3. Estimate the relative likelihood of cells being neoplastic
    message("Running giLikelihood (unsupervised)...")
    cnv <- giLikelihood(cnv)
    
    # 4. Plot the GIS density and fitted Gaussian models
    message("Generating density plots...")
    pdf("gi_density_plots.pdf", width = 8, height = 6)
    
    tryCatch({
      giDensityPlot(cnv)
    }, error = function(e) {
      message("Warning: giDensityPlot failed: ", e\$message)
    })
    
    # 5. Refine likelihood estimation by manually specifying normal and tumor components
    message("Refining likelihood estimation...")
    tryCatch({
      cnv <- giLikelihood(cnv, recompute=FALSE, normal=1, tumor=2:3)
      
      # Plot the refined density plot
      giDensityPlot(cnv)
    }, error = function(e) {
      message("Warning: Refined giLikelihood with normal=1, tumor=2:3 failed (possibly due to number of components). Keeping default likelihood. Error: ", e\$message)
    })
    
    dev.off()
    
    # Save outputs
    message("Saving outputs...")
    
    # Save the final cnv object
    saveRDS(cnv, "cnv_results.rds")
    
    # Create a summary data frame of the results
    results_df <- data.frame(
      Cell_ID = colnames(tpm_matrix),
      GIS = cnv\$gis,
      GI_Likelihood = cnv\$gi_likelihood,
      stringsAsFactors = FALSE
    )
    
    write.csv(results_df, "genomic_instability_scores.csv", row.names = FALSE)
    message("Pipeline completed successfully. Outputs saved to 'gi_density_plots.pdf', 'cnv_results.rds', and 'genomic_instability_scores.csv'.")

    writeLines(c(
        '"BIOC_GENOMICINSTABILITY_UNSUPERVISED_GIA":',
        paste0('    genomicInstability: ', as.character(packageVersion('genomicInstability')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unsupervised_gia.csv versions.yml
    """
}

workflow BIOC_GENOMICINSTABILITY_UNSUPERVISED_GIA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tpm_matrix ] ]

    main:
    BIOC_GENOMICINSTABILITY_UNSUPERVISED_GIA(ch_input)

    emit:
    tables   = BIOC_GENOMICINSTABILITY_UNSUPERVISED_GIA.out.tables
    plots    = BIOC_GENOMICINSTABILITY_UNSUPERVISED_GIA.out.plots
    objects  = BIOC_GENOMICINSTABILITY_UNSUPERVISED_GIA.out.objects
    versions = BIOC_GENOMICINSTABILITY_UNSUPERVISED_GIA.out.versions
}
