#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: swathxtend — build_extended_library
// Clean, check matching quality, align retention times, and merge a seed library and an add-on library to build and export an extended SWATH assay library.
// Input: seed_library.txt, addon_library.txt, hydro_index.txt
// Container: quay.io/biocontainers/bioconductor-swathxtend:2.32.0--r45hdfd78af_0
// R packages: SwathXtend
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SWATHXTEND_BUILD_EXTENDED_LIBRARY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-swathxtend:2.32.0--r45hdfd78af_0"

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
    .bm_deps <- c("SwathXtend")
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
    
    # Load required library
    if (!requireNamespace("SwathXtend", quietly = TRUE)) {
      stop("Package 'SwathXtend' is required but not installed.")
    }
    library(SwathXtend)
    
    # Define input file paths
    seed_file <- "seed_library.txt"
    addon_file <- "addon_library.txt"
    hydro_file <- "hydro_index.txt"
    
    # Verify required input files exist
    if (!file.exists(seed_file)) {
      stop(paste("Required input file missing:", seed_file))
    }
    if (!file.exists(addon_file)) {
      stop(paste("Required input file missing:", addon_file))
    }
    
    # --- Load libraries using readLibFile ---
    message("Reading library files...")
    Lib2 <- readLibFile(seed_file, clean = TRUE)
    Lib3 <- readLibFile(addon_file, clean = TRUE)
    
    # --- Clean libraries using cleanLib ---
    message("Cleaning libraries...")
    Lib2 <- cleanLib(Lib2, intensity.cutoff = 5, conf.cutoff = 0.99, 
                     nomod = FALSE, nomc = FALSE)
    Lib3 <- cleanLib(Lib3, intensity.cutoff = 5, conf.cutoff = 0.99, 
                     nomod = FALSE, nomc = FALSE)
    
    # --- Check matching quality using checkQuality ---
    message("Checking matching quality...")
    quality_metrics <- checkQuality(Lib2, Lib3)
    sink("matching_quality_metrics.txt")
    print(quality_metrics)
    sink()
    
    # --- Visualize matching quality ---
    message("Generating diagnostic plots...")
    pdf("matching_quality_plots.pdf", width = 8, height = 8)
    plotRTCor(Lib2, Lib3, "Seed Library", "Add-on Library")
    plotRTResd(Lib2, Lib3)
    plotRIICor(Lib2, Lib3)
    dev.off()
    
    # Generate multi-tab Excel sheet with all plots
    # Note: plotAll requires the openxlsx package internally
    tryCatch({
      plotAll(Lib2, Lib3, file = "allplots.xlsx")
    }, error = function(e) {
      warning("Could not generate allplots.xlsx: ", e\$message)
    })
    
    # --- Build the extended library using buildSpectraLibPair ---
    message("Building extended library (time-based alignment)...")
    Lib2_3 <- buildSpectraLibPair(seed_file, addon_file, clean = TRUE, 
                                  nomc = TRUE, nomod = TRUE, plot = FALSE, 
                                  outputFormat = "peakview",
                                  outputFile = "extended_library.txt")
    
    # --- Export the extended library using outputLib ---
    message("Exporting time-aligned extended library...")
    outputLib(Lib2_3, filename = "extended_library.txt", format = "peakview")
    
    # Optional: Hydrophobicity-based alignment if hydro_index.txt is provided
    if (file.exists(hydro_file)) {
      message("Hydrophobicity index file found. Building hydrophobicity-aligned library...")
      
      # Load hydrophobicity index
      hydro <- readLibFile(hydro_file, type = "hydro")
      
      # Build library using hydrophobicity-based alignment
      Lib2_3.hydro <- buildSpectraLibPair(seed_file, addon_file, hydro, 
                                          clean = TRUE, 
                                          nomc = TRUE, nomod = TRUE, plot = FALSE, 
                                          method = "hydro",
                                          outputFormat = "peakview",
                                          outputFile = "extended_library_hydro.txt")
      
      # Export the hydrophobicity-aligned library
      outputLib(Lib2_3.hydro, filename = "extended_library_hydro.txt", format = "peakview")
      message("Hydrophobicity-aligned library exported successfully.")
    } else {
      message("Optional hydro_index.txt not found. Skipping hydrophobicity-based alignment.")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SWATHXTEND_BUILD_EXTENDED_LIBRARY":',
        paste0('        swathxtend: ', as.character(packageVersion("swathxtend")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_build_extended_library.csv versions.yml
    """
}

workflow BIOC_SWATHXTEND_BUILD_EXTENDED_LIBRARY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seed_library.txt, addon_library.txt, hydro_index.txt ] ]

    main:
    BIOC_SWATHXTEND_BUILD_EXTENDED_LIBRARY(ch_input)

    emit:
    tables   = BIOC_SWATHXTEND_BUILD_EXTENDED_LIBRARY.out.tables
    plots    = BIOC_SWATHXTEND_BUILD_EXTENDED_LIBRARY.out.plots
    objects  = BIOC_SWATHXTEND_BUILD_EXTENDED_LIBRARY.out.objects
    versions = BIOC_SWATHXTEND_BUILD_EXTENDED_LIBRARY.out.versions
}
