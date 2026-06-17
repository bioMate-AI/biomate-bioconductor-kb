#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: abseqr — multi_directory_comparison
// Compare all samples across two entirely different abseqPy output directories.
// Input: SRR_CTRL, SRR_EXP
// Container: quay.io/biocontainers/bioconductor-abseqr:1.28.0--r45hdfd78af_0
// R packages: abseqR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-abseqr:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("abseqR")
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
    library(abseqR)
    
    # Verify that the required user input directories exist in the working directory
    if (!dir.exists("SRR_CTRL")) {
        stop("Error: Input directory 'SRR_CTRL' not found in the working directory.")
    }
    
    if (!dir.exists("SRR_EXP")) {
        stop("Error: Input directory 'SRR_EXP' not found in the working directory.")
    }
    
    # --- Load S4 objects from the first abseqPy directory (Control) ---
    SRRControl <- abseqReport("SRR_CTRL")
    
    # --- Load S4 objects from the second abseqPy directory ---
    SRRExp <- abseqReport("SRR_EXP")
    
    # --- Combine all loaded samples using Reduce and the + operator ---
    all.samples <- Reduce("+", c(SRRControl, SRRExp))
    
    # --- Generate a comparative report for the combined collection ---
    report(all.samples, outputDir = "SRRControl_vs_SRRExp")
    
    # Save meaningful results as RDS objects for downstream analysis
    saveRDS(SRRControl, file = "SRRControl_loaded.rds")
    saveRDS(SRRExp, file = "SRRExp_loaded.rds")
    saveRDS(all.samples, file = "all_samples_combined.rds")

    writeLines(c(
        '"BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON":',
        paste0('        abseqr: ', as.character(packageVersion("abseqr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_directory_comparison.csv versions.yml
    """
}

workflow BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SRR_CTRL, SRR_EXP ] ]

    main:
    BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON(ch_input)

    emit:
    tables   = BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON.out.tables
    plots    = BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON.out.plots
    objects  = BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON.out.objects
    versions = BIOC_ABSEQR_MULTI_DIRECTORY_COMPARISON.out.versions
}
