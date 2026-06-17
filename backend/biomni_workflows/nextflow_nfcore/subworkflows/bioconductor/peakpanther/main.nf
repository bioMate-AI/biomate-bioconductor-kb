#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: peakPantheR — parallel_annotation
// Detect and integrate multiple targeted features across multiple MS files in parallel, optimize parameters using diagnostic plots, and export final results.
// Input: input_spectraPaths, input_targetFeatTable
// Container: quay.io/biocontainers/bioconductor-peakpanther:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: peakPantheR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize annotation object with peakPantheRAnnotation
//  * 2. [Core Analysis] Run initial parallel annotation with peakPantheR_parallelAnnotation
//  * 3. [Core Analysis] Establish updated ROI (uROI) and fallback integration regions (FIR) using annotationParamsDiagnostic
//  * 4. [Visualization & Output] Save diagnostic parameters and plots to disk using outputAnnotationDiagnostic
//  * 5. [Input & Preparation] Load updated parameters from CSV using peakPantheR_loadAnnotationParamsCSV
//  * 6. [Core Analysis] Reset annotation with new samples and enable uROI/FIR using resetAnnotation
//  * 7. [Core Analysis] Run final parallel annotation with peakPantheR_parallelAnnotation
//  * 8. [Visualization & Output] Extract results using peakTables or annotationTable and export to disk using outputAnnotationResult

nextflow.enable.dsl = 2

process BIOC_PEAKPANTHER_PARALLEL_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("peakPantheR")
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
        
        # peakPantheR Parallel Annotation Pipeline
        # This script runs the parallel annotation workflow of peakPantheR to detect,
        # integrate, and report targeted features across multiple MS files.
        
        library(peakPantheR)
        
        # ==========================================
        # 1. READ USER INPUT FILES
        # ==========================================
        
        # Read targeted features table (CSV format)
        if (file.exists("input_targetFeatTable.csv")) {
          input_targetFeatTable <- read.csv("input_targetFeatTable.csv", stringsAsFactors = FALSE)
        } else {
          stop("Error: Required input file 'input_targetFeatTable.csv' not found in the working directory.")
        }
        
        # Ensure expected numeric columns are correctly typed
        numeric_cols <- c("rtMin", "rt", "rtMax", "mzMin", "mz", "mzMax")
        for (col in numeric_cols) {
          if (col %in% colnames(input_targetFeatTable)) {
            input_targetFeatTable[[col]] <- as.numeric(input_targetFeatTable[[col]])
          }
        }
        
        # Read representative spectra paths for the first pass (QC/representative samples)
        if (file.exists("input_spectraPaths.txt")) {
          input_spectraPaths <- readLines("input_spectraPaths.txt")
        } else {
          # Fallback: search for raw MS files in the current directory
          found_files <- list.files(pattern = "\\\\.(CDF|mzML|mzXML|mzData)\$", ignore.case = TRUE, full.names = TRUE)
          if (length(found_files) > 0) {
            message("input_spectraPaths.txt not found. Using discovered MS files: ", paste(found_files, collapse = ", "))
            input_spectraPaths <- found_files
          } else {
            stop("Error: 'input_spectraPaths.txt' not found and no MS files (.CDF, .mzML, etc.) found in the working directory.")
          }
        }
        
        # Read spectra metadata for the first pass
        if (file.exists("input_spectraMetadata.csv")) {
          input_spectraMetadata <- read.csv("input_spectraMetadata.csv", stringsAsFactors = FALSE)
        } else {
          # Create default metadata if not provided
          input_spectraMetadata <- data.frame(
            sampleType = rep("sample type 1", length(input_spectraPaths)),
            stringsAsFactors = FALSE
          )
        }
        
        # Read all study spectra paths for the second pass
        if (file.exists("new_spectraPaths.txt")) {
          new_spectraPaths <- readLines("new_spectraPaths.txt")
        } else {
          message("new_spectraPaths.txt not found. Re-using input_spectraPaths for the second pass.")
          new_spectraPaths <- input_spectraPaths
        }
        
        # Read spectra metadata for the second pass
        if (file.exists("new_spectraMetadata.csv")) {
          new_spectraMetadata <- read.csv("new_spectraMetadata.csv", stringsAsFactors = FALSE)
        } else {
          # Create default metadata if not provided
          new_spectraMetadata <- data.frame(
            Group = rep("Group 1", length(new_spectraPaths)),
            stringsAsFactors = FALSE
          )
        }
        
        
        # ==========================================
        # 2. INITIALIZE AND RUN INITIAL ANNOTATION
        # ==========================================
        
        # Initialize peakPantheRAnnotation object
        init_annotation <- peakPantheRAnnotation(
          spectraPaths = input_spectraPaths, 
          targetFeatTable = input_targetFeatTable, 
          spectraMetadata = input_spectraMetadata
        )
        
        # Run initial parallel annotation
        annotation_result <- peakPantheR_parallelAnnotation(
          init_annotation, 
          ncores = 0, 
          curveModel = 'skewedGaussian', 
          verbose = TRUE
        )
        
        data_annotation <- annotation_result\$annotation
        
        
        # ==========================================
        # 3. DIAGNOSTICS AND PARAMETER OPTIMIZATION
        # ==========================================
        
        # Establish updated ROI (uROI) and fallback integration regions (FIR)
        updated_annotation <- annotationParamsDiagnostic(data_annotation, verbose = TRUE)
        
        # Define colors for diagnostic plots based on sample types
        uniq_sType <- sort(unique(spectraMetadata(updated_annotation)\$sampleType), na.last = TRUE)
        col_sType <- unname( setNames(rainbow(length(uniq_sType)), uniq_sType)[spectraMetadata(updated_annotation)\$sampleType] )
        
        # Create output directory for diagnostic results
        output_folder <- "./diagnostic_output"
        dir.create(output_folder, showWarnings = FALSE, recursive = TRUE)
        
        # Save diagnostic parameters and plots to disk
        outputAnnotationDiagnostic(
          updated_annotation, 
          saveFolder = output_folder, 
          savePlots = TRUE, 
          sampleColour = col_sType, 
          verbose = TRUE, 
          ncores = 2
        )
        
        
        # ==========================================
        # 4. LOAD OPTIMIZED PARAMETERS AND RESET
        # ==========================================
        
        # Load the updated parameters from the generated CSV file
        update_csv_path <- file.path(output_folder, "annotationParameters_summary.csv")
        new_annotation <- peakPantheR_loadAnnotationParamsCSV(update_csv_path)
        
        # Reset Fallback Integration Regions (FIR)
        new_annotation <- resetFIR(new_annotation)
        
        # Reset annotation with all study samples and enable uROI and FIR
        new_annotation <- resetAnnotation(
          new_annotation, 
          spectraPaths = new_spectraPaths, 
          spectraMetadata = new_spectraMetadata, 
          useUROI = TRUE, 
          useFIR = TRUE
        )
        
        
        # ==========================================
        # 5. RUN FINAL PARALLEL ANNOTATION
        # ==========================================
        
        # Run final parallel annotation on all study samples
        new_annotation_result <- peakPantheR_parallelAnnotation(
          new_annotation, 
          ncores = 0, 
          verbose = FALSE
        )
        
        final_annotation <- new_annotation_result\$annotation
        
        
        # ==========================================
        # 6. EXPORT FINAL RESULTS
        # ==========================================
        
        # Define colors for final diagnostic plots based on study groups
        uniq_group <- sort(unique(spectraMetadata(final_annotation)\$Group), na.last = TRUE)
        col_group <- unname( setNames(rainbow(length(uniq_group)), uniq_group)[spectraMetadata(final_annotation)\$Group] )
        
        # Create output directory for final results
        final_output_folder <- "./final_output"
        dir.create(final_output_folder, showWarnings = FALSE, recursive = TRUE)
        
        # Save final diagnostic plots and parameters
        outputAnnotationDiagnostic(
          final_annotation, 
          saveFolder = final_output_folder, 
          savePlots = TRUE, 
          sampleColour = col_group, 
          verbose = TRUE
        )
        
        # Extract and print peak tables for the first sample
        first_sample_peaks <- peakTables(final_annotation)[[1]]
        write.csv(first_sample_peaks, file = file.path(final_output_folder, "first_sample_peakTable.csv"), row.names = FALSE)
        
        # Extract and save peak area table across all samples
        peak_area_table <- annotationTable(final_annotation, column = 'peakArea')
        write.csv(peak_area_table, file = file.path(final_output_folder, "final_peakArea_table.csv"))
        
        # Export all annotation results to disk
        outputAnnotationResult(
          final_annotation, 
          saveFolder = final_output_folder, 
          annotationName = 'ProjectName', 
          verbose = TRUE
        )
        
        # Save the final annotation object as an RDS file for downstream R analysis
        saveRDS(final_annotation, file = file.path(final_output_folder, "final_annotation_object.rds"))
        
        message("Pipeline completed successfully. Results exported to '", final_output_folder, "'.")

    writeLines(c(
        '"BIOC_PEAKPANTHER_PARALLEL_ANNOTATION":',
        paste0('    peakPantheR: ', as.character(packageVersion('peakPantheR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_parallel_annotation.csv versions.yml
    """
}

workflow BIOC_PEAKPANTHER_PARALLEL_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input_spectraPaths, input_targetFeatTable ] ]

    main:
    BIOC_PEAKPANTHER_PARALLEL_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_PEAKPANTHER_PARALLEL_ANNOTATION.out.tables
    plots    = BIOC_PEAKPANTHER_PARALLEL_ANNOTATION.out.plots
    objects  = BIOC_PEAKPANTHER_PARALLEL_ANNOTATION.out.objects
    versions = BIOC_PEAKPANTHER_PARALLEL_ANNOTATION.out.versions
}
