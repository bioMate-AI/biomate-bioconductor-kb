#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifStack — interactive_motif_browsing
// Generate interactive, draggable motif plots using d3.js.
// Input: pfms, phylog
// Container: quay.io/biocontainers/bioconductor-motifstack:1.54.0--r45hdfd78af_0
// Requires: ade4, htmlwidgets, motifStack
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Call browseMotifs with specified layout and dimensions

nextflow.enable.dsl = 2

process BIOC_MOTIFSTACK_INTERACTIVE_MOTIF_BROWSING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
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
    # 1. Tree layout
    widget_tree <- browseMotifs(
      pfms = pfms, 
      phylog = phylog, 
      layout = "tree", 
      yaxis = FALSE, 
      baseWidth = 6, 
      baseHeight = 15
    )
    
    # 2. Radial Phylogeny layout
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
