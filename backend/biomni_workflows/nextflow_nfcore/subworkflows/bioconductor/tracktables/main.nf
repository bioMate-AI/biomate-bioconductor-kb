#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tracktables — igv_session_and_html_report_generation
// Generate IGV session XML files and interactive HTML tracktable reports from genomics file paths and sample metadata.
// Input: FileSheet, SampleSheet
// Container: quay.io/biocontainers/bioconductor-tracktables:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: tracktables
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare the FileSheet and SampleSheet matrices
//  * 2. [Core Analysis] Generate the IGV session XML and metadata file using MakeIGVSession()
//  * 3. [Input & Preparation] Define custom IGV display parameters using igvParam()
//  * 4. [Visualization & Output] Generate the interactive HTML report using maketracktable()

nextflow.enable.dsl = 2

process BIOC_TRACKTABLES_IGV_SESSION_AND_HTML_REPORT_GENERATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required library
    library(tracktables)
    
    # Read user input files from the working directory
    # The pipeline expects "FileSheet.csv" and "SampleSheet.csv" to be present in the working directory.
    if (!file.exists("FileSheet.csv") || !file.exists("SampleSheet.csv")) {
      stop("Required input files 'FileSheet.csv' and/or 'SampleSheet.csv' are missing from the working directory.")
    }
    
    # Read FileSheet and convert to matrix as expected by tracktables
    FileSheet_df <- read.csv("FileSheet.csv", header = TRUE, stringsAsFactors = FALSE, na.strings = c("NA", ""))
    FileSheet <- as.matrix(FileSheet_df)
    
    # Read SampleSheet and convert to matrix
    SampleSheet_df <- read.csv("SampleSheet.csv", header = TRUE, stringsAsFactors = FALSE, na.strings = c("NA", ""))
    SampleSheet <- as.matrix(SampleSheet_df)
    
    # Ensure correct column names and structure
    required_file_cols <- c("SampleName", "bigwig", "interval", "bam")
    if (!all(required_file_cols %in% colnames(FileSheet))) {
      stop("FileSheet must contain columns: 'SampleName', 'bigwig', 'interval', 'bam'")
    }
    # Reorder columns to match exact expected order if necessary
    FileSheet <- FileSheet[, required_file_cols, drop = FALSE]
    
    if (!"SampleName" %in% colnames(SampleSheet)) {
      stop("SampleSheet must contain a 'SampleName' column.")
    }
    
    # Stage 2: Generate the IGV session XML and metadata file using MakeIGVSession()
    message("Generating IGV Session...")
    MakeIGVSession(
      SampleSheet = SampleSheet,
      FileSheet = FileSheet,
      igvdirectory = getwd(),
      "Example",
      "mm9"
    )
    
    # Stage 3: Generate the interactive HTML report using maketracktable()
    message("Generating first HTML report (IGVExample.html)...")
    HTMLreport <- maketracktable(
      fileSheet = FileSheet,
      SampleSheet = SampleSheet,
      filename = "IGVExample.html",
      basedirectory = getwd(),
      genome = "mm9"
    )
    
    # Save the first HTML report object
    saveRDS(HTMLreport, file = "HTMLreport_v1.rds")
    
    # Stage 4: Define custom IGV display parameters using igvParam() and generate second report
    message("Defining custom IGV display parameters...")
    igvDisplayParams <- igvParam(
      bigwig.autoScale = "false",
      bigwig.minimum = 1,
      bigwig.maximum = 5
    )
    
    message("Generating second HTML report with custom parameters (IGVex2.html)...")
    HTMLreport2 <- maketracktable(
      FileSheet,
      SampleSheet,
      "IGVex2.html",
      getwd(),
      "mm9",
      colourBy = "Antibody",
      igvParam = igvDisplayParams
    )
    
    # Save the second HTML report object
    saveRDS(HTMLreport2, file = "HTMLreport_v2.rds")
    
    message("Pipeline completed successfully. Outputs generated in the working directory.")

    writeLines(c(
        '"BIOC_TRACKTABLES_IGV_SESSION_AND_HTML_REPORT_GENERATION":',
        paste0('    tracktables: ', as.character(packageVersion('tracktables')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_igv_session_and_html_report_generation.csv versions.yml
    """
}

workflow BIOC_TRACKTABLES_IGV_SESSION_AND_HTML_REPORT_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ FileSheet, SampleSheet ] ]

    main:
    BIOC_TRACKTABLES_IGV_SESSION_AND_HTML_REPORT_GENERATION(ch_input)

    emit:
    tables   = BIOC_TRACKTABLES_IGV_SESSION_AND_HTML_REPORT_GENERATION.out.tables
    plots    = BIOC_TRACKTABLES_IGV_SESSION_AND_HTML_REPORT_GENERATION.out.plots
    objects  = BIOC_TRACKTABLES_IGV_SESSION_AND_HTML_REPORT_GENERATION.out.objects
    versions = BIOC_TRACKTABLES_IGV_SESSION_AND_HTML_REPORT_GENERATION.out.versions
}
