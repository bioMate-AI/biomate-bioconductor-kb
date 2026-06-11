#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iBBiG — expression_data_preprocessing
// Prepare continuous gene expression data for iBBiG analysis by binarizing or discretizing it.
// Input: BicatYeast
// Container: quay.io/biocontainers/bioconductor-ibbig:1.54.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: biclust, iBBiG
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the continuous gene expression dataset
//  * 2. [Core Analysis] Binarize the dataset using a specified threshold or discretize it into binary format

nextflow.enable.dsl = 2

process BIOC_IBBIG_EXPRESSION_DATA_PREPROCESSING {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(iBBiG)
    library(biclust)
    
    # Define a robust function to load the user input file 'BicatYeast'
    load_input <- function(filename) {
      # Check for various possible extensions in the working directory
      possible_files <- c(
        filename,
        paste0(filename, ".rds"),
        paste0(filename, ".csv"),
        paste0(filename, ".tsv"),
        paste0(filename, ".txt")
      )
      
      selected_file <- NULL
      for (f in possible_files) {
        if (file.exists(f)) {
          selected_file <- f
          break
        }
      }
      
      if (is.null(selected_file)) {
        stop(paste("Error: Required input file 'BicatYeast' (as RDS, CSV, TSV, or TXT) not found in the working directory."))
      }
      
      message(paste("Loading input file:", selected_file))
      
      # Read based on file extension
      if (grepl("\\\\.rds\$", selected_file, ignore.case = TRUE)) {
        data_obj <- readRDS(selected_file)
      } else if (grepl("\\\\.tsv\$|\\\\.txt\$", selected_file, ignore.case = TRUE)) {
        data_obj <- as.matrix(read.delim(selected_file, row.names = 1, header = TRUE))
      } else {
        # Default to CSV
        data_obj <- as.matrix(read.csv(selected_file, row.names = 1, header = TRUE))
      }
      
      return(data_obj)
    }
    
    # 1. Load the continuous gene expression dataset
    BicatYeast <- load_input("BicatYeast")
    
    # --- BEGIN FAITHFUL REPRODUCTION OF DOCUMENTED CODE ---
    BicatYeast[1:5,1:5]
    binarize(BicatYeast[1:5,1:5], threshold=0.2)
    discretize(BicatYeast[1:5,1:5])
    # --- END FAITHFUL REPRODUCTION OF DOCUMENTED CODE ---
    
    # 2. Binarize and discretize the full dataset for downstream iBBiG analysis
    message("Binarizing the full dataset...")
    BicatYeast_binarized <- binarize(BicatYeast, threshold=0.2)
    
    message("Discretizing the full dataset...")
    BicatYeast_discretized <- discretize(BicatYeast)
    
    # 3. Write named output files for the meaningful results
    message("Saving preprocessed outputs...")
    write.csv(as.matrix(BicatYeast_binarized), "BicatYeast_binarized.csv", row.names = TRUE)
    write.csv(as.matrix(BicatYeast_discretized), "BicatYeast_discretized.csv", row.names = TRUE)
    
    saveRDS(BicatYeast_binarized, "BicatYeast_binarized.rds")
    saveRDS(BicatYeast_discretized, "BicatYeast_discretized.rds")
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_IBBIG_EXPRESSION_DATA_PREPROCESSING":',
        paste0('    iBBiG: ', as.character(packageVersion('iBBiG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expression_data_preprocessing.csv versions.yml
    """
}

workflow BIOC_IBBIG_EXPRESSION_DATA_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BicatYeast ] ]

    main:
    BIOC_IBBIG_EXPRESSION_DATA_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_IBBIG_EXPRESSION_DATA_PREPROCESSING.out.tables
    plots    = BIOC_IBBIG_EXPRESSION_DATA_PREPROCESSING.out.plots
    objects  = BIOC_IBBIG_EXPRESSION_DATA_PREPROCESSING.out.objects
    versions = BIOC_IBBIG_EXPRESSION_DATA_PREPROCESSING.out.versions
}
