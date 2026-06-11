#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cbaf — multiple_studies_analysis
// Retrieve, analyze, and compare multi-omic data across multiple different cancer studies.
// Input: genes, studies
// Container: quay.io/biocontainers/bioconductor-cbaf:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cbaf
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Query and download data for multiple studies using obtainMultipleStudies() (or automatically via processMultipleStudies())
//  * 2. [Core Analysis] Calculate statistics across studies using automatedStatistics()
//  * 3. [Visualization & Output] Generate comparative heatmaps using heatmapOutput()
//  * 4. [Visualization & Output] Export results to Excel spreadsheets using xlsxOutput()

nextflow.enable.dsl = 2

process BIOC_CBAF_MULTIPLE_STUDIES_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("cbaf")
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
    library(cbaf)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    # The pipeline expects 'genes' (a named list of gene symbol vectors)
    # and 'studies' (a character vector of cBioPortal study names)
    # to be present in the working directory as RDS files.
    
    if (file.exists("genes.rds")) {
      genes <- readRDS("genes.rds")
    } else if (file.exists("genes")) {
      genes <- readRDS("genes")
    } else {
      stop("Error: Input file 'genes' or 'genes.rds' not found in the working directory.")
    }
    
    if (file.exists("studies.rds")) {
      studies <- readRDS("studies.rds")
    } else if (file.exists("studies")) {
      studies <- readRDS("studies")
    } else {
      stop("Error: Input file 'studies' or 'studies.rds' not found in the working directory.")
    }
    
    # Validate input types
    if (!is.list(genes) || is.null(names(genes))) {
      stop("Error: 'genes' must be a named list of gene symbol vectors.")
    }
    if (!is.character(studies)) {
      stop("Error: 'studies' must be a character vector of cancer study names.")
    }
    
    # ==========================================
    # 2. Clean Database Cache (Avoid Halting)
    # ==========================================
    # cbaf will halt if the submissionName "test2" already exists locally.
    # We clean the database for "test2" to ensure a clean, reproducible run.
    tryCatch({
      cleanDatabase("test2")
    }, error = function(e) {
      message("Note: Database cleanup skipped or not required: ", e\$message)
    })
    
    # ==========================================
    # 3. Run Multiple Studies Analysis Pipeline
    # ==========================================
    # This high-level function automatically performs:
    #   1. obtainMultipleStudies() - Downloads data from cBioPortal
    #   2. automatedStatistics()   - Calculates frequencyPercentage and frequencyRatio
    #   3. heatmapOutput()         - Generates comparative heatmaps (TIFF format)
    #   4. xlsxOutput()            - Exports results to Excel spreadsheets
    processMultipleStudies(
      genes, 
      "test2", 
      studies, 
      "RNA-Seq", 
      calculate = c("frequencyPercentage", "frequencyRatio"), 
      heatmapFileFormat = "TIFF"
    )
    
    # ==========================================
    # 4. Verify and Document Outputs
    # ==========================================
    # The outputs are stored in "test2 output for multiple studies"
    output_dir <- "test2 output for multiple studies"
    if (dir.exists(output_dir)) {
      message("Analysis completed successfully.")
      message("Outputs generated in directory: ", output_dir)
      
      # List generated files for verification
      generated_files <- list.files(output_dir, recursive = TRUE, full.names = TRUE)
      print(generated_files)
      
      # Save a structured RDS log of the run and output file paths
      saveRDS(
        list(
          status = "success",
          input_studies = studies,
          input_genes = genes,
          output_directory = output_dir,
          generated_files = generated_files
        ),
        file = "pipeline_run_summary.rds"
      )
    } else {
      stop("Error: Output directory was not created. Pipeline may have failed.")
    }

    writeLines(c(
        '"BIOC_CBAF_MULTIPLE_STUDIES_ANALYSIS":',
        paste0('    cbaf: ', as.character(packageVersion('cbaf')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_studies_analysis.csv versions.yml
    """
}

workflow BIOC_CBAF_MULTIPLE_STUDIES_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genes, studies ] ]

    main:
    BIOC_CBAF_MULTIPLE_STUDIES_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CBAF_MULTIPLE_STUDIES_ANALYSIS.out.tables
    plots    = BIOC_CBAF_MULTIPLE_STUDIES_ANALYSIS.out.plots
    objects  = BIOC_CBAF_MULTIPLE_STUDIES_ANALYSIS.out.objects
    versions = BIOC_CBAF_MULTIPLE_STUDIES_ANALYSIS.out.versions
}
