#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: motifstack — ggplot2_motif_plotting
// Plot motifs within a ggplot2 framework using geom_motif.
// Input: pfm_object.rds
// Container: quay.io/biocontainers/bioconductor-motifstack:1.54.0--r45hdfd78af_0
// R packages: ggplot2, motifStack
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-motifstack:1.54.0--r45hdfd78af_0"

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
    .bm_deps <- c("ggplot2", "motifStack")
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
    library(ggplot2)
    
    # Read user input
    if (!file.exists("pfm_object.rds")) {
      stop("Error: 'pfm_object.rds' not found in the working directory.")
    }
    
    pfm_input <- readRDS("pfm_object.rds")
    
    # Ensure the object is a pfm (convert if it is a pcm)
    if (inherits(pfm_input, "pcm")) {
      pfm <- pcm2pfm(pfm_input)
    } else {
      pfm <- pfm_input
    }
    
    # First plotting workflow (using xmin, ymin, xmax, ymax)
    df <- data.frame(xmin=c(.25, .25), ymin=c(.25, .75), xmax=c(.75, .75), ymax=c(.5, 1), fontfamily=c("serif", "mono"), fontface=c(2, 1))
    df\$motif <- list(pfm, pfm)
    
    p1 <- ggplot(df, aes(xmin=xmin, ymin=ymin, xmax=xmax, ymax=ymax, motif=motif, fontfamily=fontfamily, fontface=fontface)) + 
      geom_motif() + 
      theme_bw() + 
      ylim(0, 1) + 
      xlim(0, 1)
    
    ggsave("motif_plot_coords.pdf", plot = p1, width = 7, height = 7)
    
    # Second plotting workflow (using x, y, width, height)
    df <- data.frame(x=.5, y=c(.25, .75), width=.5, height=.25, fontfamily=c("serif", "mono"), fontface=c(2, 1))
    df\$motif <- list(pfm, pfm)
    
    p2 <- ggplot(df, aes(x=x, y=y, width=width, height=height, motif=motif, fontfamily=fontfamily, fontface=fontface)) + 
      geom_motif(use.xy=TRUE) + 
      theme_bw() + 
      ylim(0, 1) + 
      xlim(0, 1)
    
    ggsave("motif_plot_xy.pdf", plot = p2, width = 7, height = 7)

    writeLines(c(
        '"BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING":',
        paste0('        motifstack: ', as.character(packageVersion("motifstack")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggplot2_motif_plotting.csv versions.yml
    """
}

workflow BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pfm_object.rds ] ]

    main:
    BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING(ch_input)

    emit:
    tables   = BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING.out.tables
    plots    = BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING.out.plots
    objects  = BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING.out.objects
    versions = BIOC_MOTIFSTACK_GGPLOT2_MOTIF_PLOTTING.out.versions
}
