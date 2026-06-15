#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: asics — custom_reference_library_creation
// Create a custom reference library of pure metabolite spectra or merge new pure spectra with the default library for use in quantification.
// Input: pure_spectra_directory
// Container: quay.io/biocontainers/bioconductor-asics:2.26.0--r45hdfd78af_0
// R packages: ASICS
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASICS_CUSTOM_REFERENCE_LIBRARY_CREATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-asics:2.26.0--r45hdfd78af_0"

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
    .bm_deps <- c("ASICS")
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
    library(ASICS)
    
    # Define the input directory containing Bruker spectral files of pure metabolites
    pure_spectra_directory <- "pure_spectra_directory"
    
    # Validate input directory existence
    if (!dir.exists(pure_spectra_directory)) {
      stop(paste("Required input directory does not exist:", pure_spectra_directory))
    }
    
    # --- Import pure spectra using importSpectraBruker ---
    pure_spectra <- importSpectraBruker(pure_spectra_directory)
    
    # Determine the number of protons for each imported spectrum to match the input size
    num_spectra <- ncol(pure_spectra)
    protons <- rep(1, num_spectra)
    
    # --- Create a new PureLibrary object using createPureLibrary ---
    new_pure_library <- createPureLibrary(pure_spectra, nb.protons = protons)
    
    # --- Combine the new library with the default library using c() ---
    merged_pure_library <- c(pure_library[1:10], new_pure_library)
    
    # Save the merged library object as an RDS file
    saveRDS(merged_pure_library, file = "merged_pure_library.rds")
    
    # Export a summary table of the metabolites in the merged library
    library_summary <- data.frame(
      Index = seq_along(getSampleName(merged_pure_library)),
      MetaboliteName = getSampleName(merged_pure_library),
      stringsAsFactors = FALSE
    )
    write.csv(library_summary, file = "merged_pure_library_summary.csv", row.names = FALSE)
    
    cat("Custom reference library creation and merging completed successfully.\n")

    writeLines(c(
        '"BIOC_ASICS_CUSTOM_REFERENCE_LIBRARY_CREATION":',
        paste0('        asics: ', as.character(packageVersion("asics")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_reference_library_creation.csv versions.yml
    """
}

workflow BIOC_ASICS_CUSTOM_REFERENCE_LIBRARY_CREATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pure_spectra_directory ] ]

    main:
    BIOC_ASICS_CUSTOM_REFERENCE_LIBRARY_CREATION(ch_input)

    emit:
    tables   = BIOC_ASICS_CUSTOM_REFERENCE_LIBRARY_CREATION.out.tables
    plots    = BIOC_ASICS_CUSTOM_REFERENCE_LIBRARY_CREATION.out.plots
    objects  = BIOC_ASICS_CUSTOM_REFERENCE_LIBRARY_CREATION.out.objects
    versions = BIOC_ASICS_CUSTOM_REFERENCE_LIBRARY_CREATION.out.versions
}
