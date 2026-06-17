#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regionReport — derfinder_base_level_report
// Generate a specialized HTML report for exploring single base-level results from a derfinder analysis.
// Input: prefix, optionsStats, fullCov
// Container: quay.io/biocontainers/bioconductor-regionreport:1.44.0--r45hdfd78af_0
// R packages: GenomeInfoDb, GenomicRanges, derfinder, regionReport
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomeInfoDb, GenomicRanges, derfinder, regionReport
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Merge chromosome-level derfinder results using mergeResults()
//  * 2. [Input & Preparation] Load the optionsStats.Rdata file
//  * 3. [Visualization & Output] Run derfinderReport() to compile the HTML report
//  * 4. [Visualization & Output] Open the report in a web browser using browseURL()

nextflow.enable.dsl = 2

process BIOC_REGIONREPORT_DERFINDER_BASE_LEVEL_REPORT {
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
    .bm_deps <- c("GenomeInfoDb", "GenomicRanges", "derfinder", "regionReport")
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
    library("regionReport")
    library("derfinder")
    library("GenomicRanges")
    library("GenomeInfoDb")
    
    # 1. Read User Inputs from the working directory
    if (!file.exists("prefix.txt")) {
        stop("Required input file 'prefix.txt' containing the path prefix not found.")
    }
    prefix <- readLines("prefix.txt", warn = FALSE)[1]
    
    if (!file.exists("fullCov.rds")) {
        stop("Required input file 'fullCov.rds' containing raw coverage data list not found.")
    }
    fullCov <- readRDS("fullCov.rds")
    chrs <- names(fullCov)
    
    if (!file.exists("optionsStats.Rdata")) {
        stop("Required input file 'optionsStats.Rdata' containing statistical options not found.")
    }
    
    # Load or build genomicState
    if (file.exists("genomicState.rds")) {
        genomicState <- readRDS("genomicState.rds")
    } else {
        # Fallback to NULL if genomicState.rds is missing to avoid hardcoding a specific genome
        genomicState <- NULL
    }
    
    # 2. Load the optionsStats.Rdata file
    load("optionsStats.Rdata", verbose = TRUE)
    
    # 3. Merge chromosome-level derfinder results
    mergeResults(
        chrs = chrs, prefix = prefix,
        genomicState = if (!is.null(genomicState)) genomicState\$fullGenome else NULL,
        optionsStats = optionsStats
    )
    
    # 4. Run derfinderReport() to compile the HTML report
    report <- derfinderReport(
        prefix = prefix, browse = FALSE,
        nBestRegions = 15, makeBestClusters = TRUE,
        fullCov = fullCov, optionsStats = optionsStats
    )
    
    # Open the report
    browseURL(report)
    
    # 5. Write named output files for meaningful results
    writeLines(report, "report_path.txt")
    
    merged_regions_file <- file.path(prefix, "fullRegions.Rdata")
    if (file.exists(merged_regions_file)) {
        load(merged_regions_file, verbose = TRUE)
        if (exists("fullRegions")) {
            saveRDS(fullRegions, "merged_fullRegions.rds")
            write.csv(as.data.frame(fullRegions), "merged_fullRegions.csv", row.names = FALSE)
        }
    }

    writeLines(c(
        '"BIOC_REGIONREPORT_DERFINDER_BASE_LEVEL_REPORT":',
        paste0('    regionReport: ', as.character(packageVersion('regionReport')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_derfinder_base_level_report.csv versions.yml
    """
}

workflow BIOC_REGIONREPORT_DERFINDER_BASE_LEVEL_REPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ prefix, optionsStats, fullCov ] ]

    main:
    BIOC_REGIONREPORT_DERFINDER_BASE_LEVEL_REPORT(ch_input)

    emit:
    tables   = BIOC_REGIONREPORT_DERFINDER_BASE_LEVEL_REPORT.out.tables
    plots    = BIOC_REGIONREPORT_DERFINDER_BASE_LEVEL_REPORT.out.plots
    objects  = BIOC_REGIONREPORT_DERFINDER_BASE_LEVEL_REPORT.out.objects
    versions = BIOC_REGIONREPORT_DERFINDER_BASE_LEVEL_REPORT.out.versions
}
