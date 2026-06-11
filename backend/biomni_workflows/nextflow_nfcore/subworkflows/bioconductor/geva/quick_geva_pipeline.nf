#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: geva — quick_geva_pipeline
// Perform the entire GEVA analysis pipeline quickly using a single shortcut function.
// Input: ginput
// Container: quay.io/biocontainers/bioconductor-geva:1.18.0--r45hdfd78af_0
// R packages: geva
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEVA_QUICK_GEVA_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-geva:1.18.0--r45hdfd78af_0"

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
    .bm_deps <- c("geva")
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
    
    # Load the required Bioconductor package
    library(geva)
    
    # --- Read the user input file (GEVAInput object) from the ---
    # The input is expected to be a serialized GEVAInput object named 'ginput.rds'
    if (!file.exists("ginput.rds")) {
      stop("Error: 'ginput.rds' not found in the working directory.")
    }
    ginput <- readRDS("ginput.rds")
    
    # --- Run the shortcut function geva.quick on the input data ---
    gresults <- geva.quick(ginput, resolution=0.25)
    
    # --- Re-analyze or fine-tune parameters by calling geva.quick ---
    gresults <- geva.quick(gresults, summary.method='median')
    
    # --- Write named output files for the meaningful results ---
    # Save the final GEVAResults object
    saveRDS(gresults, file = "gresults.rds")
    
    # Save the final classifications table as a CSV file
    res_table <- results.table(gresults)
    write.csv(res_table, file = "geva_results_table.csv", row.names = TRUE)
    
    # Extract and save the top genes table as a CSV file
    # We attempt to include "Symbol" if it exists in the feature table, otherwise fallback to default
    top_genes_df <- tryCatch({
      top.genes(gresults, add.cols = "Symbol")
    }, error = function(e) {
      top.genes(gresults)
    })
    write.csv(top_genes_df, file = "geva_top_genes.csv", row.names = TRUE)
    
    # Save the SV-plot of the final results as a PDF
    pdf("geva_results_plot.pdf", width = 9, height = 6)
    plot(gresults)
    dev.off()

    writeLines(c(
        '"BIOC_GEVA_QUICK_GEVA_PIPELINE":',
        paste0('        geva: ', as.character(packageVersion("geva")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_geva_pipeline.csv versions.yml
    """
}

workflow BIOC_GEVA_QUICK_GEVA_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ginput ] ]

    main:
    BIOC_GEVA_QUICK_GEVA_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GEVA_QUICK_GEVA_PIPELINE.out.tables
    plots    = BIOC_GEVA_QUICK_GEVA_PIPELINE.out.plots
    objects  = BIOC_GEVA_QUICK_GEVA_PIPELINE.out.objects
    versions = BIOC_GEVA_QUICK_GEVA_PIPELINE.out.versions
}
