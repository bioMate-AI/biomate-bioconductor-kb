#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeoTcgaData — tcga_id_conversion_and_normalization
// Convert TCGA ENSEMBL gene IDs to gene symbols and normalize raw counts to FPKM or TPM.
// Input: profile, lung_squ_count2, gene_cov
// Container: quay.io/biocontainers/bioconductor-geotcgadata:2.10.0--r45hdfd78af_0
// R packages: GeoTcgaData
// Bioconductor: 3.20 | R: 4.4
// Requires: GeoTcgaData
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert ENSEMBL gene IDs to gene symbols using id_conversion_TCGA
//  * 2. [Core Analysis] Convert raw counts to FPKM using countToFpkm
//  * 3. [Core Analysis] Convert raw counts to TPM using countToTpm

nextflow.enable.dsl = 2

process BIOC_GEOTCGADATA_TCGA_ID_CONVERSION_AND_NORMALIZATION {
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
    .bm_deps <- c("GeoTcgaData")
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
    library(GeoTcgaData)
    
    # Helper function to read input files from the working directory
    # Supports RDS, CSV, and TSV formats
    read_input <- function(base_name) {
      extensions <- c(".rds", ".csv", ".tsv", "")
      for (ext in extensions) {
        file_path <- paste0(base_name, ext)
        if (file.exists(file_path)) {
          if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
            return(readRDS(file_path))
          } else if (grepl("\\\\.csv\$", file_path, ignore.case = TRUE)) {
            return(read.csv(file_path, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE))
          } else if (grepl("\\\\.tsv\$", file_path, ignore.case = TRUE)) {
            return(read.delim(file_path, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE))
          } else {
            # Default fallback to read.csv if no extension
            return(read.csv(file_path, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE))
          }
        }
      }
      stop(paste("Required input file not found in working directory:", base_name))
    }
    
    # 1. Read user inputs
    message("Reading input files...")
    profile <- read_input("profile")
    lung_squ_count2 <- read_input("lung_squ_count2")
    gene_cov <- read_input("gene_cov")
    
    # Ensure appropriate data types
    if (is.data.frame(lung_squ_count2)) {
      lung_squ_count2 <- as.matrix(lung_squ_count2)
    }
    if (is.data.frame(profile)) {
      profile <- as.matrix(profile)
    }
    
    # 2. Convert TCGA ENSEMBL gene IDs to gene symbols
    message("Converting TCGA ENSEMBL IDs to gene symbols...")
    converted_profile <- id_conversion_TCGA(profile)
    
    # Save ID conversion results
    write.csv(converted_profile, "id_conversion_results.csv", row.names = TRUE)
    message("Saved ID conversion results to 'id_conversion_results.csv'")
    
    # 3. Convert raw counts to FPKM
    message("Converting raw counts to FPKM...")
    fpkm_result <- countToFpkm(lung_squ_count2, keyType = "SYMBOL", 
                               gene_cov = gene_cov)
    
    # Save FPKM results
    write.csv(fpkm_result, "fpkm_results.csv", row.names = TRUE)
    message("Saved FPKM results to 'fpkm_results.csv'")
    
    # 4. Convert raw counts to TPM
    message("Converting raw counts to TPM...")
    tpm_result <- countToTpm(lung_squ_count2, keyType = "SYMBOL", 
                              gene_cov = gene_cov)
    
    # Save TPM results
    write.csv(tpm_result, "tpm_results.csv", row.names = TRUE)
    message("Saved TPM results to 'tpm_results.csv'")
    
    message("Workflow completed successfully.")

    writeLines(c(
        '"BIOC_GEOTCGADATA_TCGA_ID_CONVERSION_AND_NORMALIZATION":',
        paste0('    GeoTcgaData: ', as.character(packageVersion('GeoTcgaData')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tcga_id_conversion_and_normalization.csv versions.yml
    """
}

workflow BIOC_GEOTCGADATA_TCGA_ID_CONVERSION_AND_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ profile, lung_squ_count2, gene_cov ] ]

    main:
    BIOC_GEOTCGADATA_TCGA_ID_CONVERSION_AND_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_GEOTCGADATA_TCGA_ID_CONVERSION_AND_NORMALIZATION.out.tables
    plots    = BIOC_GEOTCGADATA_TCGA_ID_CONVERSION_AND_NORMALIZATION.out.plots
    objects  = BIOC_GEOTCGADATA_TCGA_ID_CONVERSION_AND_NORMALIZATION.out.objects
    versions = BIOC_GEOTCGADATA_TCGA_ID_CONVERSION_AND_NORMALIZATION.out.versions
}
