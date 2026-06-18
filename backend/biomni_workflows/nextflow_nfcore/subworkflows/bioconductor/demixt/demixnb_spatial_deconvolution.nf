#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DeMixT — demixnb_spatial_deconvolution
// Perform two-component deconvolution on sparse count data (such as spatially resolved transcriptomics) using the negative binomial model to estimate tumor propor
// Input: count_matrix, barcode_reference, barcode_mixed, top_genes
// Container: quay.io/biocontainers/bioconductor-demixt:1.26.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DeMixT, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Inputs
//  * 2. [Visualization & Output] Execute Documented Workflow
//  * 3. [Visualization & Output] Write Outputs

nextflow.enable.dsl = 2

process BIOC_DEMIXT_DEMIXNB_SPATIAL_DECONVOLUTION {
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
    .bm_deps <- c("DeMixT", "SummarizedExperiment")
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
     library(SummarizedExperiment)
   library(DeMixT)
    
    # Helper function to read vector inputs robustly
    read_vector <- function(base_name) {
      if (file.exists(paste0(base_name, ".rds"))) {
        return(as.character(readRDS(paste0(base_name, ".rds"))))
      } else if (file.exists(paste0(base_name, ".csv"))) {
        df <- read.csv(paste0(base_name, ".csv"), header = FALSE, stringsAsFactors = FALSE)
        return(as.character(df[[1]]))
      } else if (file.exists(paste0(base_name, ".txt"))) {
        return(readLines(paste0(base_name, ".txt")))
      } else {
        stop(paste("Required vector file not found for:", base_name))
      }
    }
    
    # Helper function to read matrix inputs robustly
    read_matrix <- function(base_name) {
      if (file.exists(paste0(base_name, ".rds"))) {
        return(as.matrix(readRDS(paste0(base_name, ".rds"))))
      } else if (file.exists(paste0(base_name, ".csv"))) {
        df <- tryCatch({
          read.csv(paste0(base_name, ".csv"), row.names = 1, check.names = FALSE)
        }, error = function(e) {
          read.csv(paste0(base_name, ".csv"), check.names = FALSE)
        })
        return(as.matrix(df))
      } else {
        stop(paste("Required matrix file not found for:", base_name))
      }
    }
    
    # --- Read User Inputs ---
    count_matrix <- read_matrix("count_matrix")
    barcode_reference <- read_vector("barcode_reference")
    barcode_mixed <- read_vector("barcode_mixed")
    top_genes <- read_vector("top_genes")
    
    # Align and clean inputs to prevent subscript out of bounds
    gl <- intersect(top_genes, rownames(count_matrix))
    barcode_reference <- intersect(barcode_reference, colnames(count_matrix))
    barcode_mixed <- intersect(barcode_mixed, colnames(count_matrix))
    
    if (length(gl) == 0) {
      stop("No overlap between top_genes and count_matrix row names.")
    }
    if (length(barcode_reference) == 0) {
      stop("No overlap between barcode_reference and count_matrix column names.")
    }
    if (length(barcode_mixed) == 0) {
      stop("No overlap between barcode_mixed and count_matrix column names.")
    }
    
    # --- Execute Documented Workflow ---
    filtered_mat <- count_matrix[gl, ]
    data.N1 <- as.matrix(filtered_mat[, barcode_reference])
    data.Y <- as.matrix(filtered_mat[, barcode_mixed])
    matrix_data <- as.matrix(filtered_mat[, barcode_mixed])
    data.Y <- SummarizedExperiment(assays = list(counts = matrix_data))
    matrix_data <- as.matrix(filtered_mat[, barcode_reference])
    data.N1 <- SummarizedExperiment(assays = list(counts = matrix_data))
    
    # Run DeMixNB deconvolution
    test_simulation <- DeMixNB(data.Y = data.Y, data.N1 = data.N1, niter = 30, tol = 1e-3)
    
    # --- Write Outputs ---
    saveRDS(test_simulation, file = "demixnb_results.rds")
    
    if (!is.null(test_simulation\$pi_t_summary)) {
      write.csv(test_simulation\$pi_t_summary, file = "estimated_proportions_summary.csv", row.names = TRUE)
    }
    if (!is.null(test_simulation\$pi)) {
      write.csv(test_simulation\$pi, file = "estimated_proportions_pi.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_DEMIXT_DEMIXNB_SPATIAL_DECONVOLUTION":',
        paste0('    DeMixT: ', as.character(packageVersion('DeMixT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_demixnb_spatial_deconvolution.csv versions.yml
    """
}

workflow BIOC_DEMIXT_DEMIXNB_SPATIAL_DECONVOLUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count_matrix, barcode_reference, barcode_mixed, top_genes ] ]

    main:
    BIOC_DEMIXT_DEMIXNB_SPATIAL_DECONVOLUTION(ch_input)

    emit:
    tables   = BIOC_DEMIXT_DEMIXNB_SPATIAL_DECONVOLUTION.out.tables
    plots    = BIOC_DEMIXT_DEMIXNB_SPATIAL_DECONVOLUTION.out.plots
    objects  = BIOC_DEMIXT_DEMIXNB_SPATIAL_DECONVOLUTION.out.objects
    versions = BIOC_DEMIXT_DEMIXNB_SPATIAL_DECONVOLUTION.out.versions
}
