#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: epimutacions — leave_one_out_epimutation_analysis
// Identify epimutations in a single cohort without explicit case-control groups by comparing each individual sample against all other samples in the cohort.
// Input: GRset
// Container: quay.io/biocontainers/bioconductor-epimutacions:1.14.0--r45ha27e39d_0
// R packages: epimutacions, minfi
// Bioconductor: 3.20 | R: 4.4
// Requires: epimutacions, minfi
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the preprocessed GenomicRatioSet
//  * 2. [Core Analysis] Run leave-one-out epimutation detection using epimutations_one_leave_out

nextflow.enable.dsl = 2

process BIOC_EPIMUTACIONS_LEAVE_ONE_OUT_EPIMUTATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("epimutacions", "minfi")
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
    library(epimutacions)
    library(minfi)
    
    # 1. Load the preprocessed GenomicRatioSet from the working directory
    # The pipeline expects "GRset.rds" containing the GenomicRatioSet object
    GRset <- readRDS("GRset.rds")
    
    # 2. Run leave-one-out epimutation detection using epimutations_one_leave_out
    epi_mva_one_leave_out <- epimutations_one_leave_out(GRset)
    
    # 3. Write named output files for the results
    # Save the complete results table as a CSV file
    write.csv(epi_mva_one_leave_out, "epi_mva_one_leave_out.csv", row.names = FALSE)
    
    # Save the results as an RDS object for downstream R analysis
    saveRDS(epi_mva_one_leave_out, "epi_mva_one_leave_out.rds")

    writeLines(c(
        '"BIOC_EPIMUTACIONS_LEAVE_ONE_OUT_EPIMUTATION_ANALYSIS":',
        paste0('    epimutacions: ', as.character(packageVersion('epimutacions')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_leave_one_out_epimutation_analysis.csv versions.yml
    """
}

workflow BIOC_EPIMUTACIONS_LEAVE_ONE_OUT_EPIMUTATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GRset ] ]

    main:
    BIOC_EPIMUTACIONS_LEAVE_ONE_OUT_EPIMUTATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_EPIMUTACIONS_LEAVE_ONE_OUT_EPIMUTATION_ANALYSIS.out.tables
    plots    = BIOC_EPIMUTACIONS_LEAVE_ONE_OUT_EPIMUTATION_ANALYSIS.out.plots
    objects  = BIOC_EPIMUTACIONS_LEAVE_ONE_OUT_EPIMUTATION_ANALYSIS.out.objects
    versions = BIOC_EPIMUTACIONS_LEAVE_ONE_OUT_EPIMUTATION_ANALYSIS.out.versions
}
