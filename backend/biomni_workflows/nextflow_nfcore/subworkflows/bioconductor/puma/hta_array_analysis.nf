#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: puma — hta_array_analysis
// Calculate gene and transcript expression levels from Affymetrix HTA 2.0 arrays.
// Input: celFiles
// Container: quay.io/biocontainers/bioconductor-puma:3.52.0--r45h01b2380_0
// R packages: oligo, puma
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PUMA_HTA_ARRAY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-puma:3.52.0--r45h01b2380_0"

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
    .bm_deps <- c("oligo", "puma")
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
    library(puma)
    library(oligo)
    
    # Search for raw Affymetrix HTA 2.0 array CEL files in the working directory
    celFiles <- list.celfiles(full.names = TRUE)
    
    if (length(celFiles) == 0) {
      stop("Error: No CEL files found in the current working directory. Please place your Affymetrix HTA 2.0 CEL files here.")
    }
    
    message(paste("Found", length(celFiles), "CEL file(s). Proceeding with analysis..."))
    
    # --- Read CEL files ---
    oligo.hta <- read.celfiles(celFiles)
    
    # --- Calculate gene and transcript expression levels using ---
    eset_gmhta <- gmhta(oligo.hta, gsnorm="none")
    
    # --- Write expression and standard error results to CSV files ---
    write.reslts(eset_gmhta\$gene, file="eset_gmhta_gene")
    write.reslts(eset_gmhta\$transcript, file="eset_gmhta_transcript")
    
    message("Analysis complete. Results written to 'eset_gmhta_gene' and 'eset_gmhta_transcript' CSV files.")

    writeLines(c(
        '"BIOC_PUMA_HTA_ARRAY_ANALYSIS":',
        paste0('        puma: ', as.character(packageVersion("puma")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hta_array_analysis.csv versions.yml
    """
}

workflow BIOC_PUMA_HTA_ARRAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ celFiles ] ]

    main:
    BIOC_PUMA_HTA_ARRAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PUMA_HTA_ARRAY_ANALYSIS.out.tables
    plots    = BIOC_PUMA_HTA_ARRAY_ANALYSIS.out.plots
    objects  = BIOC_PUMA_HTA_ARRAY_ANALYSIS.out.objects
    versions = BIOC_PUMA_HTA_ARRAY_ANALYSIS.out.versions
}
