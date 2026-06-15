#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: trackViewer — chromatin_interaction_visualization
// Plot genomic interaction data (Hi-C/GInteractions) as a heatmap track alongside coverage tracks.
// Input: interactions.rds, coverage.rds
// Container: quay.io/biocontainers/bioconductor-trackviewer:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, InteractionSet, trackViewer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Convert GInteractions to track using gi2track
//  * 2. [Core Analysis] Set track style parameters (breaks, color)
//  * 3. [Visualization & Output] Plot using viewTracks

nextflow.enable.dsl = 2

process BIOC_TRACKVIEWER_CHROMATIN_INTERACTION_VISUALIZATION {
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
    .bm_deps <- c("trackViewer", "InteractionSet", "GenomicRanges")
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
    library(trackViewer)
    library(InteractionSet)
    library(GenomicRanges)
    
    # 1. Read user input files from the working directory
    gi <- readRDS("interactions.rds")
    ctcf <- readRDS("coverage.rds")
    
    # Convert the GRanges coverage data into a track object
    ctcf <- new("track", dat=ctcf, type="data")
    
    # 2. Dynamically define the genomic range from the interactions object
    regions_gi <- InteractionSet::regions(gi)
    chrom <- as.character(seqnames(regions_gi))[1]
    min_start <- min(start(regions_gi))
    max_end <- max(end(regions_gi))
    range <- GRanges(chrom, IRanges(min_start, max_end))
    
    # 3. Convert GInteractions to track using gi2track
    tr <- gi2track(gi)
    
    # 4. Set track style parameters (breaks, color)
    setTrackStyleParam(tr, "breaks", c(seq(from=0, to=50, by=10), 200))
    setTrackStyleParam(tr, "color", c("lightblue", "yellow", "red"))
    
    # 5. Save the track list object as an RDS file
    saveRDS(trackList(ctcf, tr, heightDist=c(1, 3)), "track_list.rds")
    
    # 6. Plot using viewTracks and save to a PDF file
    pdf("interaction_visualization.pdf", width=10, height=8)
    viewTracks(trackList(ctcf, tr, heightDist=c(1, 3)), gr=range, autoOptimizeStyle = TRUE)
    dev.off()

    writeLines(c(
        '"BIOC_TRACKVIEWER_CHROMATIN_INTERACTION_VISUALIZATION":',
        paste0('    trackViewer: ', as.character(packageVersion('trackViewer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromatin_interaction_visualization.csv versions.yml
    """
}

workflow BIOC_TRACKVIEWER_CHROMATIN_INTERACTION_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ interactions.rds, coverage.rds ] ]

    main:
    BIOC_TRACKVIEWER_CHROMATIN_INTERACTION_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_TRACKVIEWER_CHROMATIN_INTERACTION_VISUALIZATION.out.tables
    plots    = BIOC_TRACKVIEWER_CHROMATIN_INTERACTION_VISUALIZATION.out.plots
    objects  = BIOC_TRACKVIEWER_CHROMATIN_INTERACTION_VISUALIZATION.out.objects
    versions = BIOC_TRACKVIEWER_CHROMATIN_INTERACTION_VISUALIZATION.out.versions
}
