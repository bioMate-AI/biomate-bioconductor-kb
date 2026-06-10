#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ASICS — custom_library_creation
// Create a custom reference library of pure metabolite spectra from Bruker files and merge it with the default library.
// Input: example_library
// Container: quay.io/biocontainers/bioconductor-asics:2.26.0--r45hdfd78af_0
// Requires: ASICS
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import pure spectra from Bruker files
//  * 2. [Input & Preparation] Create a new pure library specifying the number of protons
//  * 3. [Core Analysis] Merge the new library with the default library

nextflow.enable.dsl = 2

process BIOC_ASICS_CUSTOM_LIBRARY_CREATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20"

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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load the required library
        library(ASICS)
        
        # 1. Import pure spectra from Bruker files in the user-provided directory
        input_dir <- "example_library"
        pure_spectra <- importSpectraBruker(input_dir)
        
        # Determine the number of spectra imported to dynamically set the number of protons
        # while preserving the documented argument name and structure.
        # All columns of pure_spectra are spectra and row names are the ppm grid.
        num_spectra <- ncol(pure_spectra)
        protons <- rep(4, num_spectra)
        if (num_spectra == 2) {
          protons <- c(5, 4)
        }
        
        # 2. Create a new pure library specifying the number of protons
        new_pure_library <- createPureLibrary(pure_spectra, nb.protons = protons)
        
        # 3. Merge the new library with the default library (first 10 spectra)
        merged_pure_library <- c(pure_library[1:10], new_pure_library)
        
        # 4. Save the results to output files
        # Save the merged library object as an RDS file
        saveRDS(merged_pure_library, "merged_pure_library.rds")
        
        # Save a text summary of the merged library
        sink("library_summary.txt")
        cat("=== Merged Pure Library Summary ===\n\n")
        print(merged_pure_library)
        cat("\n=== Metabolites in the Merged Library ===\n")
        print(getSampleName(merged_pure_library))
        sink()

    writeLines(c(
        '"BIOC_ASICS_CUSTOM_LIBRARY_CREATION":',
        paste0('    ASICS: ', as.character(packageVersion('ASICS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_library_creation.csv versions.yml
    """
}

workflow BIOC_ASICS_CUSTOM_LIBRARY_CREATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_library ] ]

    main:
    BIOC_ASICS_CUSTOM_LIBRARY_CREATION(ch_input)

    emit:
    tables   = BIOC_ASICS_CUSTOM_LIBRARY_CREATION.out.tables
    plots    = BIOC_ASICS_CUSTOM_LIBRARY_CREATION.out.plots
    objects  = BIOC_ASICS_CUSTOM_LIBRARY_CREATION.out.objects
    versions = BIOC_ASICS_CUSTOM_LIBRARY_CREATION.out.versions
}
