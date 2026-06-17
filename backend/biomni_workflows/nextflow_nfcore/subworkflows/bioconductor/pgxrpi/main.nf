#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pgxRpi — process_local_pgxseg
// Extract segment data, metadata, calculate CNV frequencies, and visualize survival data from a local `.pgxseg` file.
// Input: example.pgxseg
// Container: quay.io/biocontainers/bioconductor-pgxrpi:1.6.0--r45hdfd78af_0
// R packages: GenomicRanges, pgxRpi
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PGXRPI_PROCESS_LOCAL_PGXSEG {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-pgxrpi:1.6.0--r45hdfd78af_0"

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
    .bm_deps <- c("GenomicRanges", "pgxRpi")
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
    library(pgxRpi)
    library(GenomicRanges)
    
    # Define the input file path (exactly as requested, from the working directory)
    file_name <- "example.pgxseg"
    
    # Check if the file exists to avoid immediate failure
    if (!file.exists(file_name)) {
      stop(paste("Required input file", file_name, "not found in the working directory."))
    }
    
    # --- Extract segment data using pgxSegprocess ---
    message("Extracting segment data...")
    seg <- pgxSegprocess(file=file_name, return_seg = TRUE)
    
    # Save segment data
    if (is.data.frame(seg)) {
      write.csv(seg, "extracted_segments.csv", row.names = FALSE)
    } else {
      saveRDS(seg, "extracted_segments.rds")
    }
    
    # --- Extract metadata using pgxSegprocess ---
    message("Extracting metadata...")
    meta <- pgxSegprocess(file=file_name, return_metadata = TRUE)
    
    # Save metadata
    if (is.data.frame(meta)) {
      write.csv(meta, "extracted_metadata.csv", row.names = FALSE)
    } else {
      saveRDS(meta, "extracted_metadata.rds")
    }
    
    # --- Visualize survival data using Kaplan-Meier plots ---
    message("Generating Kaplan-Meier survival plots...")
    pdf("survival_plots.pdf", width = 8, height = 6)
    
    tryCatch({
      pgxSegprocess(file=file_name, show_KM_plot = TRUE)
    }, error = function(e) {
      message("Warning: KM plot 1 failed: ", e\$message)
    })
    
    tryCatch({
      pgxSegprocess(file=file_name, show_KM_plot = TRUE, group_id = 'histological_diagnosis_id')
    }, error = function(e) {
      message("Warning: KM plot 2 failed: ", e\$message)
    })
    
    tryCatch({
      pgxSegprocess(file=file_name, show_KM_plot = TRUE, pval=TRUE, palette='npg')
    }, error = function(e) {
      message("Warning: KM plot 3 failed: ", e\$message)
    })
    
    dev.off()
    
    # --- Calculate CNV frequency based on metadata grouping ---
    message("Calculating CNV frequencies...")
    frequency <- pgxSegprocess(file=file_name, return_frequency = TRUE)
    saveRDS(frequency, "cnv_frequency_default.rds")
    
    frequency_2 <- pgxSegprocess(file=file_name, return_frequency = TRUE, group_id ='icdo_morphology_id')
    saveRDS(frequency_2, "cnv_frequency_by_morphology.rds")
    
    # --- Extract all data types simultaneously ---
    message("Extracting all data types simultaneously...")
    info <- pgxSegprocess(file=file_name, show_KM_plot = TRUE, return_seg = TRUE, return_metadata = TRUE, return_frequency = TRUE)
    saveRDS(info, "all_extracted_info.rds")
    
    message("Pipeline completed successfully. Outputs saved.")

    writeLines(c(
        '"BIOC_PGXRPI_PROCESS_LOCAL_PGXSEG":',
        paste0('        pgxRpi: ', as.character(packageVersion("pgxRpi")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_process_local_pgxseg.csv versions.yml
    """
}

workflow BIOC_PGXRPI_PROCESS_LOCAL_PGXSEG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.pgxseg ] ]

    main:
    BIOC_PGXRPI_PROCESS_LOCAL_PGXSEG(ch_input)

    emit:
    tables   = BIOC_PGXRPI_PROCESS_LOCAL_PGXSEG.out.tables
    plots    = BIOC_PGXRPI_PROCESS_LOCAL_PGXSEG.out.plots
    objects  = BIOC_PGXRPI_PROCESS_LOCAL_PGXSEG.out.objects
    versions = BIOC_PGXRPI_PROCESS_LOCAL_PGXSEG.out.versions
}
