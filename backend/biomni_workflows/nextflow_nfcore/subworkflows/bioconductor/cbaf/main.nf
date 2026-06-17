#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cbaf — single_study_analysis
// Retrieve, analyze, and visualize multi-omic data across subgroups of a single cancer study.
// Input: genes, studyName
// Container: quay.io/biocontainers/bioconductor-cbaf:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: cbaf, jsonlite
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Query and download subgroup data using obtainOneStudy() (or automatically via processOneStudy())
//  * 2. [Core Analysis] Calculate statistics (frequency percentage, ratio, mean, median) using automatedStatistics()
//  * 3. [Visualization & Output] Generate heatmaps for the calculated statistics using heatmapOutput()
//  * 4. [Visualization & Output] Export results to Excel spreadsheets using xlsxOutput()

nextflow.enable.dsl = 2

process BIOC_CBAF_SINGLE_STUDY_ANALYSIS {
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
            
            # Load required libraries
            library(cbaf)
            
            # ==========================================
            # 1. READ USER INPUT FILES
            # ==========================================
            
            # Read 'genes' input (named list of gene symbol vectors)
            if (file.exists("genes.rds")) {
              genes <- readRDS("genes.rds")
            } else if (file.exists("genes.json")) {
              if (!requireNamespace("jsonlite", quietly = TRUE)) {
                install.packages("jsonlite", repos = "https://cloud.r-project.org")
              }
              genes <- jsonlite::read_json("genes.json", simplifyVector = TRUE)
            } else if (file.exists("genes.txt")) {
              genes <- dget("genes.txt")
            } else {
              stop("Error: Required input file 'genes' (genes.rds, genes.json, or genes.txt) not found in the working directory.")
            }
            
            # Read 'studyName' input (character string of a standard cBioPortal cancer study name)
            if (file.exists("studyName.txt")) {
              studyName <- trimws(readLines("studyName.txt", warn = FALSE)[1])
            } else if (file.exists("studyName.rds")) {
              studyName <- readRDS("studyName.rds")
            } else {
              stop("Error: Required input file 'studyName' (studyName.txt or studyName.rds) not found in the working directory.")
            }
            
            # ==========================================
            # 2. PREPARE ENVIRONMENT
            # ==========================================
            
            # Clean local database cache for "test" to prevent halting if it already exists
            tryCatch({
              cleanDatabase("test")
            }, error = function(e) {
              message("Note: Local database 'test' was not present or could not be cleaned: ", e\$message)
            })
            
            # Remove any pre-existing output directories to ensure a clean run
            if (dir.exists("test output for multiple studies")) {
              unlink("test output for multiple studies", recursive = TRUE)
            }
            if (dir.exists("test output for single study")) {
              unlink("test output for single study", recursive = TRUE)
            }
            
            # ==========================================
            # 3. EXECUTE WORKFLOW (processOneStudy)
            # ==========================================
            
            # Run the single study analysis workflow exactly as documented
            processOneStudy(
              genes, 
              "test", 
              studyName, 
              "RNA-Seq", 
              desiredCaseList = 1,
              calculate = c("frequencyPercentage", "frequencyRatio", "meanValue", "medianValue"), 
              heatmapFileFormat = "TIFF"
            )
            
            # ==========================================
            # 4. POST-PROCESSING & OUTPUT VERIFICATION
            # ==========================================
            
            # Locate the generated output directory
            output_dirs <- list.dirs(pattern = "test output", recursive = FALSE)
            
            if (length(output_dirs) > 0) {
              message("Workflow completed successfully.")
              message("Outputs generated in directory: ", output_dirs[1])
              
              # List and verify all generated output files (Excel sheets and TIFF heatmaps)
              output_files <- list.files(output_dirs[1], recursive = TRUE, full.names = TRUE)
              for (file_path in output_files) {
                message("Created output file: ", file_path)
              }
              
              # Save a copy of the input parameters and run metadata as an RDS object
              run_metadata <- list(
                analyzed_genes = genes,
                study_name = studyName,
                output_directory = output_dirs[1],
                generated_files = output_files,
                timestamp = Sys.time()
              )
              saveRDS(run_metadata, file = "workflow_metadata.rds")
              message("Saved run metadata to 'workflow_metadata.rds'")
            } else {
              warning("Workflow finished, but no output directory starting with 'test output' was detected.")
            }

    writeLines(c(
        '"BIOC_CBAF_SINGLE_STUDY_ANALYSIS":',
        paste0('    cbaf: ', as.character(packageVersion('cbaf')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_study_analysis.csv versions.yml
    """
}

workflow BIOC_CBAF_SINGLE_STUDY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genes, studyName ] ]

    main:
    BIOC_CBAF_SINGLE_STUDY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CBAF_SINGLE_STUDY_ANALYSIS.out.tables
    plots    = BIOC_CBAF_SINGLE_STUDY_ANALYSIS.out.plots
    objects  = BIOC_CBAF_SINGLE_STUDY_ANALYSIS.out.objects
    versions = BIOC_CBAF_SINGLE_STUDY_ANALYSIS.out.versions
}
