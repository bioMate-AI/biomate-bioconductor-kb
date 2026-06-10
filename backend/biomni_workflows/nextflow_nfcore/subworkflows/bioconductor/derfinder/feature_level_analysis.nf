#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: derfinder — feature_level_analysis
// Summarize base-level coverage data to a standard count matrix at the exon or gene level using a genomic annotation state.
// Input: fullCov, genomicState
// Container: quay.io/biocontainers/bioconductor-derfinder:1.44.0--r45hdfd78af_0
// R packages: GenomicRanges, derfinder
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, derfinder
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Summarize base-level coverage to exon-level counts using coverageToExon()

nextflow.enable.dsl = 2

process BIOC_DERFINDER_FEATURE_LEVEL_ANALYSIS {
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
    .bm_deps <- c("GenomicRanges", "derfinder")
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
        library(derfinder)
        library(GenomicRanges)
        
        # Define input file paths
        full_cov_path <- "fullCov.rds"
        genomic_state_path <- "genomicState.rds"
        
        # Check if input files exist
        if (!file.exists(full_cov_path)) {
          stop(paste("Required input file missing:", full_cov_path))
        }
        if (!file.exists(genomic_state_path)) {
          stop(paste("Required input file missing:", genomic_state_path))
        }
        
        # Load user inputs
        message("Loading input data...")
        fullCov <- readRDS(full_cov_path)
        genomicState <- readRDS(genomic_state_path)
        
        # Execute the documented workflow step
        message("Summarizing base-level coverage to exon-level counts...")
        exonCov <- coverageToExon(fullCov, genomicState\$fullGenome, L = 76)
        
        # Save the primary RDS output
        output_rds <- "exonCov.rds"
        message(paste("Saving full results to", output_rds))
        saveRDS(exonCov, file = output_rds)
        
        # Export the coverage matrix as a CSV file if available
        if (!is.null(exonCov)) {
          output_csv <- "exon_coverage_matrix.csv"
          message(paste("Exporting coverage matrix to", output_csv))
          write.csv(as.matrix(exonCov), file = output_csv, row.names = TRUE)
        }
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_DERFINDER_FEATURE_LEVEL_ANALYSIS":',
        paste0('    derfinder: ', as.character(packageVersion('derfinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_feature_level_analysis.csv versions.yml
    """
}

workflow BIOC_DERFINDER_FEATURE_LEVEL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fullCov, genomicState ] ]

    main:
    BIOC_DERFINDER_FEATURE_LEVEL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DERFINDER_FEATURE_LEVEL_ANALYSIS.out.tables
    plots    = BIOC_DERFINDER_FEATURE_LEVEL_ANALYSIS.out.plots
    objects  = BIOC_DERFINDER_FEATURE_LEVEL_ANALYSIS.out.objects
    versions = BIOC_DERFINDER_FEATURE_LEVEL_ANALYSIS.out.versions
}
