#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: camera — isotope_detection_with_validation
// Perform targeted peak picking for isotopes and validate putative isotope clusters using database statistics.
// Input: microtofq
// Container: quay.io/biocontainers/bioconductor-camera:1.66.0--r45h01b2380_0
// R packages: CAMERA, xcms
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_CAMERA_ISOTOPE_DETECTION_WITH_VALIDATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-camera:1.66.0--r45h01b2380_0"

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
    .bm_deps <- c("CAMERA", "xcms")
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
    library("xcms")
    library("CAMERA")
    
    # Locate the raw LC-MS data files from the 'microtofq' directory in the working directory
    mzmlpath <- "microtofq"
    if (!dir.exists(mzmlpath)) {
      mzmlpath <- "."
    }
    
    file_list <- list.files(path = mzmlpath, pattern = "^.*\\\\.mzML\$",
                            all.files = TRUE, full.names = TRUE,
                            recursive = TRUE, ignore.case = TRUE,
                            include.dirs = FALSE, no.. = TRUE)
    
    if (length(file_list) == 0) {
      file_list <- list.files(path = mzmlpath, pattern = "^.*\\\\.(mzML|mzXML|CDF)\$",
                              all.files = TRUE, full.names = TRUE,
                              recursive = TRUE, ignore.case = TRUE,
                              include.dirs = FALSE, no.. = TRUE)
    }
    
    if (length(file_list) == 0) {
      stop("Error: No raw LC-MS data files (.mzML, .mzXML, or .CDF) found in 'microtofq' or the current working directory.")
    }
    
    # Select the first file as in the documented workflow
    file <- file_list[[1]]
    message("Processing file: ", file)
    
    # --- Perform peak picking targeting isotopes using ---
    xs    <- xcmsSet(
       files=file, method="centWaveWithPredictedIsotopeROIs",
       ppm=10, peakwidth=c(5,12), snthresh=25, prefilter=c(3,200)
    )
    
    # --- Initialize CAMERA annotation object ---
    an   <- xsAnnotate(xs, polarity="positive")
    
    # --- Group peaks by retention time ---
    an   <- groupFWHM(an, perfwhm = 1)
    
    # --- Detect and validate isotope clusters using database ---
    an   <- findIsotopesWithValidation(object = an, ppm = 10,
                                       mzabs = 0.01, intval="intb",
           maxcharge = 3)
    
    # --- Extract the annotated peak list ---
    peakTable <- getPeaklist(an)
    
    # Write outputs
    write.csv(peakTable, file = "annotated_peak_table.csv", row.names = FALSE)
    saveRDS(an, file = "xsAnnotate_object.rds")
    
    # Generate diagnostic plots
    pdf("pseudospectra_plots.pdf", width = 8, height = 6)
    num_pspectra <- length(an@pspectra)
    if (num_pspectra > 0) {
      for (i in seq_len(min(5, num_pspectra))) {
        tryCatch({
          plotPsSpectrum(an, pspec = i, maxlabel = 5)
        }, error = function(e) {
          message("Could not plot pseudospectrum ", i, ": ", e\$message)
        })
      }
    } else {
      plot.new()
      text(0.5, 0.5, "No pseudospectra detected to plot.")
    }
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to 'annotated_peak_table.csv', 'xsAnnotate_object.rds', and 'pseudospectra_plots.pdf'.")

    writeLines(c(
        '"BIOC_CAMERA_ISOTOPE_DETECTION_WITH_VALIDATION":',
        paste0('        camera: ', as.character(packageVersion("camera")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isotope_detection_with_validation.csv versions.yml
    """
}

workflow BIOC_CAMERA_ISOTOPE_DETECTION_WITH_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ microtofq ] ]

    main:
    BIOC_CAMERA_ISOTOPE_DETECTION_WITH_VALIDATION(ch_input)

    emit:
    tables   = BIOC_CAMERA_ISOTOPE_DETECTION_WITH_VALIDATION.out.tables
    plots    = BIOC_CAMERA_ISOTOPE_DETECTION_WITH_VALIDATION.out.plots
    objects  = BIOC_CAMERA_ISOTOPE_DETECTION_WITH_VALIDATION.out.objects
    versions = BIOC_CAMERA_ISOTOPE_DETECTION_WITH_VALIDATION.out.versions
}
