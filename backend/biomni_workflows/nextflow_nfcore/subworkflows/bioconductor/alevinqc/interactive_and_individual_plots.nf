#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: alevinQC — interactive_and_individual_plots
// Read alevin QC data to generate an interactive Shiny application or produce individual diagnostic plots.
// Input: baseDir
// Container: quay.io/biocontainers/bioconductor-alevinqc:1.26.0--r45ha27e39d_0
// R packages: alevinQC, ggplot2, shiny
// Bioconductor: 3.20 | R: 4.4
// Requires: alevinQC, ggplot2, shiny
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a Shiny app object using alevinQCShiny()
//  * 2. [Core Analysis] Run the Shiny app using shiny::runApp()
//  * 3. [Input & Preparation] Read the QC data into R using readAlevinQC()
//  * 4. [Visualization & Output] Generate individual diagnostic plots using plotAlevinKneeRaw(), plotAlevinBarcodeCollapse(), plotAlevinQuant(), and plotAlevinKnee

nextflow.enable.dsl = 2

process BIOC_ALEVINQC_INTERACTIVE_AND_INDIVIDUAL_PLOTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20-slim"

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
    .bm_deps <- c("alevinQC", "ggplot2", "shiny")
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
    library(alevinQC)
    library(shiny)
    library(ggplot2)
    
    # Define the input directory containing alevin output files
    # The pipeline expects a directory named "baseDir" in the current working directory
    baseDir <- "baseDir"
    
    # Verify that the input directory exists
    if (!dir.exists(baseDir)) {
      stop(paste("Error: The input directory '", baseDir, "' does not exist in the working directory.", sep = ""))
    }
    
    # Verify that the required alevin files are present in the directory
    message("Checking alevin input files...")
    checkAlevinInputFiles(baseDir = baseDir)
    
    # 1. Create a Shiny app object
    message("Creating Shiny app object...")
    app <- alevinQCShiny(baseDir = baseDir, sampleId = "testSample")
    
    # 2. Run the Shiny app if in an interactive session
    if (interactive()) {
        message("Launching interactive Shiny app...")
        out <- shiny::runApp(app)
    } else {
        message("Non-interactive session detected. Skipping interactive Shiny app launch.")
    }
    
    # 3. Read the QC data into R
    message("Reading alevin QC data...")
    alevin <- readAlevinQC(baseDir = baseDir)
    
    # Save the parsed QC data object as an RDS file
    saveRDS(alevin, file = "alevin_qc_data.rds")
    
    # Export the cell barcode table to CSV
    if (!is.null(alevin\$cbTable)) {
        write.csv(alevin\$cbTable, file = "alevin_cbTable.csv", row.names = FALSE)
    }
    
    # Export summary tables to CSV
    if (!is.null(alevin\$summaryTables)) {
        if (!is.null(alevin\$summaryTables\$fullDataset)) {
            write.csv(as.data.frame(alevin\$summaryTables\$fullDataset), 
                      file = "alevin_summary_fullDataset.csv", row.names = TRUE)
        }
        if (!is.null(alevin\$summaryTables\$initialWhitelist)) {
            write.csv(as.data.frame(alevin\$summaryTables\$initialWhitelist), 
                      file = "alevin_summary_initialWhitelist.csv", row.names = TRUE)
        }
        if (!is.null(alevin\$summaryTables\$finalWhitelist)) {
            write.csv(as.data.frame(alevin\$summaryTables\$finalWhitelist), 
                      file = "alevin_summary_finalWhitelist.csv", row.names = TRUE)
        }
    }
    
    # Export version table to CSV
    if (!is.null(alevin\$versionTable)) {
        write.csv(as.data.frame(alevin\$versionTable), 
                  file = "alevin_versionTable.csv", row.names = TRUE)
    }
    
    # Print console previews of the data
    message("Preview of cbTable:")
    print(head(alevin\$cbTable))
    
    message("Preview of fullDataset summary:")
    print(alevin\$summaryTables\$fullDataset)
    
    # 4. Generate individual diagnostic plots and save them to a PDF
    message("Generating diagnostic plots...")
    pdf(file = "alevin_diagnostic_plots.pdf", width = 8, height = 6)
    
    # Plot 1: Raw Knee Plot
    p1 <- plotAlevinKneeRaw(alevin\$cbTable)
    print(p1)
    
    # Plot 2: Barcode Collapse Plot
    p2 <- plotAlevinBarcodeCollapse(alevin\$cbTable)
    print(p2)
    
    # Plot 3: Quantification Plot
    p3 <- plotAlevinQuant(alevin\$cbTable)
    print(p3)
    
    # Plot 4: Knee Number of Genes Plot
    p4 <- plotAlevinKneeNbrGenes(alevin\$cbTable)
    print(p4)
    
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to current working directory.")

    writeLines(c(
        '"BIOC_ALEVINQC_INTERACTIVE_AND_INDIVIDUAL_PLOTS":',
        paste0('    alevinQC: ', as.character(packageVersion('alevinQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_and_individual_plots.csv versions.yml
    """
}

workflow BIOC_ALEVINQC_INTERACTIVE_AND_INDIVIDUAL_PLOTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ baseDir ] ]

    main:
    BIOC_ALEVINQC_INTERACTIVE_AND_INDIVIDUAL_PLOTS(ch_input)

    emit:
    tables   = BIOC_ALEVINQC_INTERACTIVE_AND_INDIVIDUAL_PLOTS.out.tables
    plots    = BIOC_ALEVINQC_INTERACTIVE_AND_INDIVIDUAL_PLOTS.out.plots
    objects  = BIOC_ALEVINQC_INTERACTIVE_AND_INDIVIDUAL_PLOTS.out.objects
    versions = BIOC_ALEVINQC_INTERACTIVE_AND_INDIVIDUAL_PLOTS.out.versions
}
