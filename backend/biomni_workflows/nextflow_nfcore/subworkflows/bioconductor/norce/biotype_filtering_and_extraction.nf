#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NoRCE — biotype_filtering_and_extraction
// Filter and extract biotype-specific gene lists from GTF annotation files.
// Input: annotation.gtf
// Container: quay.io/biocontainers/bioconductor-norce:1.22.0--r45hdfd78af_0
// R packages: NoRCE
// Bioconductor: 3.20 | R: 4.4
// Requires: NoRCE
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter GTF file for specific biotypes of interest
//  * 2. [Input & Preparation] Extract gene-biotype relationships to create a 2D matrix

nextflow.enable.dsl = 2

process BIOC_NORCE_BIOTYPE_FILTERING_AND_EXTRACTION {
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
    .bm_deps <- c("NoRCE")
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
    library(NoRCE)
    
    # Define the user input file
    fileImport <- "annotation.gtf"
    
    # Verify that the input file exists
    if (!file.exists(fileImport)) {
      stop(paste("Required input file '", fileImport, "' not found in the working directory.", sep = ""))
    }
    
    # Stage 1: Filter GTF file for specific biotypes of interest
    biotypes <- c('unprocessed_pseudogene', 'transcribed_unprocessed_pseudogene')
    extrResult <- filterBiotype(fileImport, biotypes)
    
    # Stage 2: Extract gene-biotype relationships to create a 2D matrix
    gtf <- extractBiotype(gtfFile = fileImport)
    
    # Save the meaningful results to output files
    # Save filtered biotype results
    saveRDS(extrResult, file = "filtered_biotype_results.rds")
    if (is.data.frame(extrResult) || is.matrix(extrResult)) {
      write.csv(extrResult, file = "filtered_biotype_results.csv", row.names = FALSE)
    } else if (is.list(extrResult)) {
      # If it's a list of data frames or other structures, save as RDS and try to write a summary
      capture.output(print(extrResult), file = "filtered_biotype_results_summary.txt")
    }
    
    # Save extracted gene-biotype matrix
    saveRDS(gtf, file = "extracted_biotype_matrix.rds")
    if (is.data.frame(gtf) || is.matrix(gtf)) {
      write.csv(gtf, file = "extracted_biotype_matrix.csv", row.names = TRUE)
    } else {
      capture.output(print(gtf), file = "extracted_biotype_matrix_summary.txt")
    }
    
    message("Workflow completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_NORCE_BIOTYPE_FILTERING_AND_EXTRACTION":',
        paste0('    NoRCE: ', as.character(packageVersion('NoRCE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biotype_filtering_and_extraction.csv versions.yml
    """
}

workflow BIOC_NORCE_BIOTYPE_FILTERING_AND_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ annotation.gtf ] ]

    main:
    BIOC_NORCE_BIOTYPE_FILTERING_AND_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_NORCE_BIOTYPE_FILTERING_AND_EXTRACTION.out.tables
    plots    = BIOC_NORCE_BIOTYPE_FILTERING_AND_EXTRACTION.out.plots
    objects  = BIOC_NORCE_BIOTYPE_FILTERING_AND_EXTRACTION.out.objects
    versions = BIOC_NORCE_BIOTYPE_FILTERING_AND_EXTRACTION.out.versions
}
