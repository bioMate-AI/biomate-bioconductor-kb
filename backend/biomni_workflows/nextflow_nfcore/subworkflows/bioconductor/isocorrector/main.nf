#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: isocorrector — stable_isotope_correction
// Correct mass spectrometry data from stable isotope labeling experiments for natural isotope abundance and tracer impurity.
// Input: MeasurementFile, ElementFile, MoleculeFile
// Container: quay.io/biocontainers/bioconductor-isocorrector:1.28.0--r45hdfd78af_0
// R packages: IsoCorrectoR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOCORRECTOR_STABLE_ISOTOPE_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-isocorrector:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("IsoCorrectoR")
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
    
    # 1. Load the IsoCorrectoR package
    library(IsoCorrectoR)
    
    # Helper function to locate user input files in the working directory
    find_input_file <- function(base_name) {
      extensions <- c("csv", "xlsx", "xls")
      for (ext in extensions) {
        filename <- paste0(base_name, ".", ext)
        if (file.exists(filename)) {
          return(filename)
        }
        # Case-insensitive check
        files <- list.files(".", pattern = paste0("^", base_name, "\\\\.", ext, "\$"), ignore.case = TRUE)
        if (length(files) > 0) {
          return(files[1])
        }
      }
      # Fallback to generic pattern matching
      files <- list.files(".", pattern = base_name, ignore.case = TRUE)
      if (length(files) > 0) {
        return(files[1])
      }
      # Default fallback
      return(paste0(base_name, ".csv"))
    }
    
    # Resolve paths for the required user input files
    measurement_path <- find_input_file("MeasurementFile")
    element_path <- find_input_file("ElementFile")
    molecule_path <- find_input_file("MoleculeFile")
    
    # Verify files exist before running to provide clear error messages
    if (!file.exists(measurement_path)) {
      stop(paste("Required MeasurementFile not found. Expected:", measurement_path))
    }
    if (!file.exists(element_path)) {
      stop(paste("Required ElementFile not found. Expected:", element_path))
    }
    if (!file.exists(molecule_path)) {
      stop(paste("Required MoleculeFile not found. Expected:", molecule_path))
    }
    
    # 2. Call the IsoCorrection function with paths to the files and desired parameters
    # ReturnResultsObject is set to TRUE to retrieve the results in the R session.
    results <- IsoCorrection(
      MeasurementFile = measurement_path,
      ElementFile = element_path,
      MoleculeFile = molecule_path,
      CorrectTracerImpurity = FALSE,
      CorrectTracerElementCore = TRUE,
      CalculateMeanEnrichment = TRUE,
      UltraHighRes = FALSE,
      DirOut = '.',
      FileOut = 'result',
      FileOutFormat = 'csv',
      ReturnResultsObject = TRUE,
      CorrectAlsoMonoisotopic = FALSE,
      CalculationThreshold = 10^-8,
      CalculationThreshold_UHR = 8,
      verbose = TRUE,
      Testmode = FALSE
    )
    
    # 3. Retrieve the returned list containing success status, results dataframes, log, and error messages
    if (!is.null(results)) {
      cat("Correction finished with status:", results\$success, "\n")
      
      # Save the complete results object as an RDS file
      saveRDS(results, file = "isocorrector_results.rds")
      
      # If there are errors or warnings, print them to the log
      if (results\$success == "FALSE" && !is.null(results\$error)) {
        cat("Error message:", results\$error, "\n")
      }
    } else {
      cat("Warning: IsoCorrection did not return a results object.\n")
    }

    writeLines(c(
        '"BIOC_ISOCORRECTOR_STABLE_ISOTOPE_CORRECTION":',
        paste0('        isocorrector: ', as.character(packageVersion("isocorrector")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_stable_isotope_correction.csv versions.yml
    """
}

workflow BIOC_ISOCORRECTOR_STABLE_ISOTOPE_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MeasurementFile, ElementFile, MoleculeFile ] ]

    main:
    BIOC_ISOCORRECTOR_STABLE_ISOTOPE_CORRECTION(ch_input)

    emit:
    tables   = BIOC_ISOCORRECTOR_STABLE_ISOTOPE_CORRECTION.out.tables
    plots    = BIOC_ISOCORRECTOR_STABLE_ISOTOPE_CORRECTION.out.plots
    objects  = BIOC_ISOCORRECTOR_STABLE_ISOTOPE_CORRECTION.out.objects
    versions = BIOC_ISOCORRECTOR_STABLE_ISOTOPE_CORRECTION.out.versions
}
