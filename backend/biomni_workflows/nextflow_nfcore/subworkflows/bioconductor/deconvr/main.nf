#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: deconvR — wgbs_deconvolution
// Map WGBS methylation data to Illumina probe IDs and predict cell-type proportions using a reference atlas.
// Input: WGBS_GRanges.rda, IlluminaMethEpicB5ProbeIDs, HumanCellTypeMethAtlas
// Container: quay.io/biocontainers/bioconductor-deconvr:1.16.0--r45hdfd78af_0
// R packages: GenomicRanges, deconvR
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, deconvR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the WGBS data and probe ID locations
//  * 2. [Core Analysis] Map WGBS genomic coordinates to probe IDs using BSmeth2Probe
//  * 3. [Core Analysis] Perform deconvolution on the mapped bulk data using deconvolute

nextflow.enable.dsl = 2

process BIOC_DECONVR_WGBS_DECONVOLUTION {
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
    .bm_deps <- c("GenomicRanges", "deconvR")
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
    library(deconvR)
    library(GenomicRanges)
    
    # Helper function to robustly load user input files from the working directory
    # supporting various formats (.rda, .RData, .rds, or no extension)
    load_input <- function(filename, object_name) {
      possible_files <- c(
        filename,
        paste0(filename, ".rda"),
        paste0(filename, ".RData"),
        paste0(filename, ".rds")
      )
      
      loaded <- FALSE
      for (f in possible_files) {
        if (file.exists(f)) {
          if (grepl("\\\\.rds\$", f, ignore.case = TRUE)) {
            assign(object_name, readRDS(f), envir = .GlobalEnv)
            loaded <- TRUE
            message(paste("Successfully loaded", object_name, "from RDS file:", f))
            break
          } else {
            # load() loads into the global environment
            tmp_env <- new.env()
            load(f, envir = tmp_env)
            if (object_name %in% names(tmp_env)) {
              assign(object_name, tmp_env[[object_name]], envir = .GlobalEnv)
              loaded <- TRUE
              message(paste("Successfully loaded", object_name, "from RDA file:", f))
              break
            } else {
              # If the object name doesn't match but there is only one object in the RDA
              objs <- names(tmp_env)
              if (length(objs) == 1) {
                assign(object_name, tmp_env[[objs[1]]], envir = .GlobalEnv)
                loaded <- TRUE
                message(paste("Successfully loaded", object_name, "(originally named", objs[1], ") from RDA file:", f))
                break
              }
            }
          }
        }
      }
      
      if (!loaded) {
        stop(paste("Error: Could not find or load", filename, "as .rda, .RData, or .rds in the working directory."))
      }
    }
    
    # ==========================================
    # STAGE 1: Load WGBS data, probe ID locations, and reference atlas
    # ==========================================
    message("Stage 1: Loading input datasets...")
    
    # Load WGBS_GRanges
    load_input("WGBS_GRanges.rda", "WGBS_GRanges")
    
    # Load IlluminaMethEpicB5ProbeIDs
    load_input("IlluminaMethEpicB5ProbeIDs", "IlluminaMethEpicB5ProbeIDs")
    
    # Load HumanCellTypeMethAtlas
    load_input("HumanCellTypeMethAtlas", "HumanCellTypeMethAtlas")
    
    
    # ==========================================
    # STAGE 2: Map WGBS genomic coordinates to probe IDs using BSmeth2Probe
    # ==========================================
    message("Stage 2: Mapping WGBS genomic coordinates to probe IDs...")
    
    mapped_WGBS_data <- BSmeth2Probe(probe_id_locations = IlluminaMethEpicB5ProbeIDs, 
                                     WGBS_data = WGBS_GRanges,
                                     multipleMapping = TRUE,
                                     cutoff = 10)
    
    # Save mapped WGBS data
    write.csv(mapped_WGBS_data, file = "mapped_WGBS_data.csv", row.names = FALSE)
    saveRDS(mapped_WGBS_data, file = "mapped_WGBS_data.rds")
    message("Mapped WGBS data saved to 'mapped_WGBS_data.csv' and 'mapped_WGBS_data.rds'.")
    
    
    # ==========================================
    # STAGE 3: Perform deconvolution on the mapped bulk data using deconvolute
    # ==========================================
    message("Stage 3: Performing cell-type deconvolution...")
    
    deconvolution <- deconvolute(reference = HumanCellTypeMethAtlas, 
                                 bulk = mapped_WGBS_data)
    
    # Extract and save predicted proportions
    proportions <- deconvolution\$proportions
    write.csv(proportions, file = "predicted_proportions.csv", row.names = TRUE)
    message("Predicted cell-type proportions saved to 'predicted_proportions.csv'.")
    
    # Save full deconvolution results object (which includes partial R-squared values)
    saveRDS(deconvolution, file = "deconvolution_results.rds")
    message("Full deconvolution results object saved to 'deconvolution_results.rds'.")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_DECONVR_WGBS_DECONVOLUTION":',
        paste0('    deconvR: ', as.character(packageVersion('deconvR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wgbs_deconvolution.csv versions.yml
    """
}

workflow BIOC_DECONVR_WGBS_DECONVOLUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ WGBS_GRanges.rda, IlluminaMethEpicB5ProbeIDs, HumanCellTypeMethAtlas ] ]

    main:
    BIOC_DECONVR_WGBS_DECONVOLUTION(ch_input)

    emit:
    tables   = BIOC_DECONVR_WGBS_DECONVOLUTION.out.tables
    plots    = BIOC_DECONVR_WGBS_DECONVOLUTION.out.plots
    objects  = BIOC_DECONVR_WGBS_DECONVOLUTION.out.objects
    versions = BIOC_DECONVR_WGBS_DECONVOLUTION.out.versions
}
