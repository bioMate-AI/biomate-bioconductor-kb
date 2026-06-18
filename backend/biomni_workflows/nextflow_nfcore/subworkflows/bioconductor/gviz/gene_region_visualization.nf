#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Gviz — gene_region_visualization
// Visualize gene models and transcripts from local data frames or TxDb objects.
// Input: geneModels, hg19_knownGene_sample.sqlite
// Container: quay.io/biocontainers/bioconductor-gviz:1.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicFeatures, Gviz
// Visualizations: genomic tracks (Gviz)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load gene model data or connect to a TxDb database
//  * 2. [Input & Preparation] Construct a GeneRegionTrack
//  * 3. [Core Analysis] Customize transcript annotations and collapsing options
//  * 4. [Visualization & Output] Plot the track along with reference tracks (axis, ideogram)

nextflow.enable.dsl = 2

process BIOC_GVIZ_GENE_REGION_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("Gviz", "GenomicFeatures")
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
    
    # Load required Bioconductor libraries
    library(Gviz)
    library(GenomicFeatures)
    
    # ------------------------------------------------------------------------------
    # Stage 1: Load gene model data and connect to the TxDb database
    # ------------------------------------------------------------------------------
    
    # Read the user-provided geneModels data frame from the working directory
    if (file.exists("geneModels")) {
      geneModels <- tryCatch({
        readRDS("geneModels")
      }, error = function(e) {
        read.csv("geneModels", stringsAsFactors = FALSE)
      })
    } else if (file.exists("geneModels.csv")) {
      geneModels <- read.csv("geneModels.csv", stringsAsFactors = FALSE)
    } else if (file.exists("geneModels.rds")) {
      geneModels <- readRDS("geneModels.rds")
    } else {
      stop("Required input file 'geneModels' (or geneModels.csv/rds) not found in the working directory.")
    }
    
    # Extract chromosome and genome identifiers from the geneModels data frame
    chr <- if ("chromosome" %in% colnames(geneModels)) unique(geneModels\$chromosome)[1] else "chr7"
    gen <- if ("genome" %in% colnames(geneModels)) unique(geneModels\$genome)[1] else "mm9"
    if (is.null(gen) || is.na(gen)) gen <- "mm9"
    if (is.null(chr) || is.na(chr)) chr <- "chr7"
    
    # Connect to the local TxDb database file
    txdb_file <- "hg19_knownGene_sample.sqlite"
    if (!file.exists(txdb_file)) {
      stop("Required input file 'hg19_knownGene_sample.sqlite' not found in the working directory.")
    }
    txdb <- loadDb(txdb_file)
    
    # ------------------------------------------------------------------------------
    # Stage 2: Construct GeneRegionTrack and reference tracks
    # ------------------------------------------------------------------------------
    
    # Construct the main GeneRegionTrack from the loaded geneModels
    grtrack <- GeneRegionTrack(geneModels, genome = gen, chromosome = chr, name = "Gene Model")
    
    # Construct reference tracks (Axis and Ideogram)
    gtrack <- GenomeAxisTrack()
    
    # Safely attempt to fetch the IdeogramTrack from UCSC, falling back to GenomeAxisTrack if offline
    itrack <- tryCatch({
      IdeogramTrack(genome = gen, chromosome = chr)
    }, error = function(e) {
      warning("Could not fetch IdeogramTrack from UCSC. Using GenomeAxisTrack as a placeholder.")
      GenomeAxisTrack()
    })
    
    # Construct an AnnotationTrack using a subset of the user's geneModels to avoid loading bundled demo data
    atrack <- AnnotationTrack(
      start = geneModels\$start[1:min(10, nrow(geneModels))],
      end = geneModels\$end[1:min(10, nrow(geneModels))],
      chromosome = chr,
      genome = gen,
      name = "CpG"
    )
    
    # ------------------------------------------------------------------------------
    # Stage 3: Customize transcript annotations, collapsing options, and plot
    # ------------------------------------------------------------------------------
    
    # Plot 1: Combined reference and gene model tracks
    pdf("plot1_combined_tracks.pdf")
    plotTracks(list(itrack, gtrack, atrack, grtrack))
    dev.off()
    
    # Plot 2: Gene model track with transcript symbol annotations
    pdf("plot2_transcript_annotation.pdf")
    plotTracks(grtrack, transcriptAnnotation = "symbol")
    dev.off()
    
    # Plot 3: Gene model track with collapsed transcripts and arrow shapes
    pdf("plot3_collapsed_transcripts.pdf")
    plotTracks(grtrack, collapseTranscripts = TRUE, shape = "arrow", transcriptAnnotation = "symbol")
    dev.off()
    
    # ------------------------------------------------------------------------------
    # Stage 4: Visualize transcripts from the TxDb database
    # ------------------------------------------------------------------------------
    
    # Instantiate GeneRegionTrack directly from the TxDb object as documented
    tryCatch({
      GeneRegionTrack(txdb)
    }, error = function(e) {
      warning("Default GeneRegionTrack(txdb) instantiation failed or was skipped.")
    })
    
    # Construct a specific genomic region track from the TxDb database
    txTr <- GeneRegionTrack(txdb, chromosome = "chr6", start = 35000000, end = 40000000)
    
    # Plot 4: TxDb-derived gene region track
    pdf("plot4_txdb_track.pdf")
    plotTracks(txTr)
    dev.off()
    
    # ------------------------------------------------------------------------------
    # Save meaningful RDS objects
    # ------------------------------------------------------------------------------
    saveRDS(grtrack, "grtrack.rds")
    saveRDS(txTr, "txTr.rds")

    writeLines(c(
        '"BIOC_GVIZ_GENE_REGION_VISUALIZATION":',
        paste0('    Gviz: ', as.character(packageVersion('Gviz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_region_visualization.csv versions.yml
    """
}

workflow BIOC_GVIZ_GENE_REGION_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneModels, hg19_knownGene_sample.sqlite ] ]

    main:
    BIOC_GVIZ_GENE_REGION_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GVIZ_GENE_REGION_VISUALIZATION.out.tables
    plots    = BIOC_GVIZ_GENE_REGION_VISUALIZATION.out.plots
    objects  = BIOC_GVIZ_GENE_REGION_VISUALIZATION.out.objects
    versions = BIOC_GVIZ_GENE_REGION_VISUALIZATION.out.versions
}
