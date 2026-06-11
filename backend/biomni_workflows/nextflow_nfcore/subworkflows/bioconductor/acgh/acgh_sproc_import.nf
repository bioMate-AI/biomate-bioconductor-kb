#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: aCGH — acgh_sproc_import
// Import a batch of Sproc image analysis output files and combine them with clone mapping information.
// Input: sproc*.txt, human.clones.info.Jul03.txt
// Container: quay.io/biocontainers/bioconductor-acgh:1.88.0--r45ha27e39d_0
// R packages: aCGH
// Bioconductor: 3.20 | R: 4.4
// Requires: aCGH
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read Sproc files and mapping file using aCGH.read.Sprocs
//  * 2. [Visualization & Output] Plot basic frequency plot using plot

nextflow.enable.dsl = 2

process BIOC_ACGH_ACGH_SPROC_IMPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("aCGH")
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
    
    # Load required library
    library(aCGH)
    
    # Define data directory as the current working directory containing the user input files
    datadir <- "."
    
    # Define the mapping file path
    latest.mapping.file <-
    	file.path(datadir, "human.clones.info.Jul03.txt")
    
    # Read Sproc files and combine with clone mapping information
    ex.acgh <-
    	aCGH.read.Sprocs(dir(path = datadir,pattern = "sproc",
    			full.names = TRUE), latest.mapping.file,
    			chrom.remove.threshold = 23)
    
    # Save the resulting aCGH object as an RDS file
    saveRDS(ex.acgh, file = "ex_acgh.rds")
    
    # Export extracted log2 ratios and clone mapping information to CSV files
    write.csv(log2.ratios(ex.acgh), file = "log2_ratios.csv", row.names = TRUE)
    write.csv(clones.info(ex.acgh), file = "clones_info.csv", row.names = TRUE)
    
    # Plot basic frequency plot and save as PDF
    pdf("acgh_sproc_plot.pdf", width = 10, height = 8)
    plot(ex.acgh)
    dev.off()

    writeLines(c(
        '"BIOC_ACGH_ACGH_SPROC_IMPORT":',
        paste0('    aCGH: ', as.character(packageVersion('aCGH')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_acgh_sproc_import.csv versions.yml
    """
}

workflow BIOC_ACGH_ACGH_SPROC_IMPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sproc*.txt, human.clones.info.Jul03.txt ] ]

    main:
    BIOC_ACGH_ACGH_SPROC_IMPORT(ch_input)

    emit:
    tables   = BIOC_ACGH_ACGH_SPROC_IMPORT.out.tables
    plots    = BIOC_ACGH_ACGH_SPROC_IMPORT.out.plots
    objects  = BIOC_ACGH_ACGH_SPROC_IMPORT.out.objects
    versions = BIOC_ACGH_ACGH_SPROC_IMPORT.out.versions
}
