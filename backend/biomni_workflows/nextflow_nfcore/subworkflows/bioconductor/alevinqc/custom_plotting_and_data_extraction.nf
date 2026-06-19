#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alevinqc — custom_plotting_and_data_extraction
// Read alevin QC data into R to inspect summary tables and generate individual diagnostic plots.
// Input: baseDir
// Container: quay.io/biocontainers/bioconductor-alevinqc:1.26.0--r45ha27e39d_0
// R packages: alevinQC, knitr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_ALEVINQC_CUSTOM_PLOTTING_AND_DATA_EXTRACTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-alevinqc:1.26.0--r45ha27e39d_0"

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
    .bm_deps <- c("alevinQC", "knitr")
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
    library(alevinQC)
    library(knitr)
    
    # Define the input directory as specified by the user
    baseDir <- "baseDir"
    
    # Verify that the input directory exists
    if (!dir.exists(baseDir)) {
      stop(paste("Error: The input directory '", baseDir, "' does not exist in the current working directory.\n",
                 "Please ensure the directory contains 'alevin/' and 'aux_info/' subdirectories and 'cmd_info.json'.", sep = ""))
    }
    
    # --- Read the alevin output into an R object using ---
    message("Reading Alevin QC data from: ", baseDir)
    alevin <- readAlevinQC(baseDir = baseDir)
    
    # Save the raw R object for downstream use
    saveRDS(alevin, file = "alevin_qc_data.rds")
    message("Saved alevin QC object to 'alevin_qc_data.rds'")
    
    # --- Inspect cell barcode tables and summary tables ---
    message("\n--- Cell Barcode Table (Head) ---")
    print(head(alevin\$cbTable))
    write.csv(alevin\$cbTable, file = "alevin_cbTable.csv", row.names = FALSE)
    
    message("\n--- Summary Table: Full Dataset ---")
    print(knitr::kable(alevin\$summaryTables\$fullDataset))
    write.csv(as.data.frame(alevin\$summaryTables\$fullDataset), file = "summaryTable_fullDataset.csv")
    
    message("\n--- Summary Table: Initial Whitelist ---")
    print(knitr::kable(alevin\$summaryTables\$initialWhitelist))
    write.csv(as.data.frame(alevin\$summaryTables\$initialWhitelist), file = "summaryTable_initialWhitelist.csv")
    
    message("\n--- Summary Table: Final Whitelist ---")
    print(knitr::kable(alevin\$summaryTables\$finalWhitelist))
    write.csv(as.data.frame(alevin\$summaryTables\$finalWhitelist), file = "summaryTable_finalWhitelist.csv")
    
    message("\n--- Version Table ---")
    print(knitr::kable(alevin\$versionTable))
    write.csv(as.data.frame(alevin\$versionTable), file = "versionTable.csv")
    
    # --- Generate individual plots and save them to a PDF ---
    pdf_filename <- "alevin_qc_plots.pdf"
    message("\nGenerating diagnostic plots and saving to '", pdf_filename, "'...")
    pdf(pdf_filename, width = 8, height = 6)
    
    # Call the exact documented plotting functions
    # Note: These functions return ggplot objects, so we wrap them in print() to render them to the PDF device.
    print(plotAlevinKneeRaw(alevin\$cbTable))
    print(plotAlevinBarcodeCollapse(alevin\$cbTable))
    print(plotAlevinQuant(alevin\$cbTable))
    print(plotAlevinKneeNbrGenes(alevin\$cbTable))
    
    dev.off()
    message("Plots successfully saved to '", pdf_filename, "'.")

    writeLines(c(
        '"BIOC_ALEVINQC_CUSTOM_PLOTTING_AND_DATA_EXTRACTION":',
        paste0('        alevinqc: ', as.character(packageVersion("alevinqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_plotting_and_data_extraction.csv versions.yml
    """
}

workflow BIOC_ALEVINQC_CUSTOM_PLOTTING_AND_DATA_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ baseDir ] ]

    main:
    BIOC_ALEVINQC_CUSTOM_PLOTTING_AND_DATA_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_ALEVINQC_CUSTOM_PLOTTING_AND_DATA_EXTRACTION.out.tables
    plots    = BIOC_ALEVINQC_CUSTOM_PLOTTING_AND_DATA_EXTRACTION.out.plots
    objects  = BIOC_ALEVINQC_CUSTOM_PLOTTING_AND_DATA_EXTRACTION.out.objects
    versions = BIOC_ALEVINQC_CUSTOM_PLOTTING_AND_DATA_EXTRACTION.out.versions
}
