#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alevinqc — static_qc_report
// Validate alevin output files and generate a static HTML or PDF quality control report.
// Input: baseDir
// Container: quay.io/biocontainers/bioconductor-alevinqc:1.26.0--r45ha27e39d_0
// R packages: alevinQC
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_ALEVINQC_STATIC_QC_REPORT {
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
    .bm_deps <- c("alevinQC")
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
    
    # Load required library
    library(alevinQC)
    
    # Define user input directory (must exist in the working directory)
    baseDir <- "baseDir"
    
    # Verify input directory exists
    if (!dir.exists(baseDir)) {
      stop(paste("Error: Input directory 'baseDir' not found in the working directory.",
                 "Please ensure the 'baseDir' directory containing 'alevin/', 'aux_info/',",
                 "and 'cmd_info.json' is present."))
    }
    
    # --- Check that all required alevin files are available ---
    message("Checking Alevin input files...")
    checkAlevinInputFiles(baseDir = baseDir)
    
    # Define output directory
    outputDir <- "output"
    if (!dir.exists(outputDir)) {
      dir.create(outputDir, recursive = TRUE)
    }
    
    # --- Generate the QC report ---
    message("Generating static QC report...")
    alevinQCReport(baseDir = baseDir, sampleId = "testSample", 
                   outputFile = "alevinReport.html", 
                   outputFormat = "html_document",
                   outputDir = outputDir, forceOverwrite = TRUE)
    
    # --- Extract and save additional meaningful results (tables ---
    message("Reading Alevin QC data for exporting tables and plots...")
    alevin <- readAlevinQC(baseDir = baseDir)
    
    # Save tables
    write.csv(alevin\$cbTable, file = file.path(outputDir, "cbTable.csv"), row.names = FALSE)
    
    # Summary tables
    if (!is.null(alevin\$summaryTables\$fullDataset)) {
      write.csv(as.data.frame(alevin\$summaryTables\$fullDataset), 
                file = file.path(outputDir, "summaryTable_fullDataset.csv"))
    }
    if (!is.null(alevin\$summaryTables\$initialWhitelist)) {
      write.csv(as.data.frame(alevin\$summaryTables\$initialWhitelist), 
                file = file.path(outputDir, "summaryTable_initialWhitelist.csv"))
    }
    if (!is.null(alevin\$summaryTables\$finalWhitelist)) {
      write.csv(as.data.frame(alevin\$summaryTables\$finalWhitelist), 
                file = file.path(outputDir, "summaryTable_finalWhitelist.csv"))
    }
    if (!is.null(alevin\$versionTable)) {
      write.csv(as.data.frame(alevin\$versionTable), 
                file = file.path(outputDir, "versionTable.csv"))
    }
    
    # Save plots to PDF
    pdf(file.path(outputDir, "alevin_qc_plots.pdf"), width = 8, height = 6)
    tryCatch({
      print(plotAlevinKneeRaw(alevin\$cbTable))
    }, error = function(e) message("Could not plot KneeRaw: ", e\$message))
    
    tryCatch({
      print(plotAlevinBarcodeCollapse(alevin\$cbTable))
    }, error = function(e) message("Could not plot BarcodeCollapse: ", e\$message))
    
    tryCatch({
      print(plotAlevinQuant(alevin\$cbTable))
    }, error = function(e) message("Could not plot Quant: ", e\$message))
    
    tryCatch({
      print(plotAlevinKneeNbrGenes(alevin\$cbTable))
    }, error = function(e) message("Could not plot KneeNbrGenes: ", e\$message))
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to 'output/' directory.")

    writeLines(c(
        '"BIOC_ALEVINQC_STATIC_QC_REPORT":',
        paste0('        alevinqc: ', as.character(packageVersion("alevinqc")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_static_qc_report.csv versions.yml
    """
}

workflow BIOC_ALEVINQC_STATIC_QC_REPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ baseDir ] ]

    main:
    BIOC_ALEVINQC_STATIC_QC_REPORT(ch_input)

    emit:
    tables   = BIOC_ALEVINQC_STATIC_QC_REPORT.out.tables
    plots    = BIOC_ALEVINQC_STATIC_QC_REPORT.out.plots
    objects  = BIOC_ALEVINQC_STATIC_QC_REPORT.out.objects
    versions = BIOC_ALEVINQC_STATIC_QC_REPORT.out.versions
}
