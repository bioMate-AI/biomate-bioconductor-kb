#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifStack — interactive_motif_browsing
// Generate interactive, draggable motif plots using d3.js.
// Input: pfms, phylog
// Container: quay.io/biocontainers/bioconductor-motifstack:1.54.0--r45hdfd78af_0
// R packages: ade4, htmlwidgets, motifStack
// Bioconductor: 3.20 | R: 4.4
// Requires: ade4, htmlwidgets, motifStack
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Tree layout
//  * 2. [Core Analysis] Radial Phylogeny layout

nextflow.enable.dsl = 2

process BIOC_MOTIFSTACK_INTERACTIVE_MOTIF_BROWSING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("ade4", "htmlwidgets", "motifStack")
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
    library(motifStack)
    library(ade4)
    library(htmlwidgets)
    
    # Read the user input files from the working directory
    # The pipeline expects 'pfms.rds' (a list of PFM objects) and 'phylog.rds' (a phylog object)
    if (!file.exists("pfms.rds") || !file.exists("phylog.rds")) {
      stop("Required input files 'pfms.rds' and/or 'phylog.rds' are missing from the working directory.")
    }
    
    pfms <- readRDS("pfms.rds")
    phylog <- readRDS("phylog.rds")
    
    # Execute the interactive motif browsing workflow as documented
    # --- Tree layout ---
    widget_tree <- browseMotifs(
      pfms = pfms, 
      phylog = phylog, 
      layout = "tree", 
      yaxis = FALSE, 
      baseWidth = 6, 
      baseHeight = 15
    )
    
    # --- Radial Phylogeny layout ---
    widget_radial <- browseMotifs(
      pfms = pfms, 
      phylog = phylog, 
      layout = "radialPhylog", 
      yaxis = FALSE, 
      xaxis = FALSE, 
      baseWidth = 6, 
      baseHeight = 15
    )
    
    # Save the interactive HTML widgets to the working directory
    htmlwidgets::saveWidget(widget_tree, "browse_motifs_tree.html", selfcontained = TRUE)
    htmlwidgets::saveWidget(widget_radial, "browse_motifs_radial.html", selfcontained = TRUE)
    
    # Save the widget objects as RDS for downstream R compatibility
    saveRDS(widget_tree, "widget_tree.rds")
    saveRDS(widget_radial, "widget_radial.rds")
    
    cat("Workflow completed successfully. Outputs saved to 'browse_motifs_tree.html', 'browse_motifs_radial.html', 'widget_tree.rds', and 'widget_radial.rds'.\n")

    writeLines(c(
        '"BIOC_MOTIFSTACK_INTERACTIVE_MOTIF_BROWSING":',
        paste0('    motifStack: ', as.character(packageVersion('motifStack')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_motif_browsing.csv versions.yml
    """
}

workflow BIOC_MOTIFSTACK_INTERACTIVE_MOTIF_BROWSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pfms, phylog ] ]

    main:
    BIOC_MOTIFSTACK_INTERACTIVE_MOTIF_BROWSING(ch_input)

    emit:
    tables   = BIOC_MOTIFSTACK_INTERACTIVE_MOTIF_BROWSING.out.tables
    plots    = BIOC_MOTIFSTACK_INTERACTIVE_MOTIF_BROWSING.out.plots
    objects  = BIOC_MOTIFSTACK_INTERACTIVE_MOTIF_BROWSING.out.objects
    versions = BIOC_MOTIFSTACK_INTERACTIVE_MOTIF_BROWSING.out.versions
}
