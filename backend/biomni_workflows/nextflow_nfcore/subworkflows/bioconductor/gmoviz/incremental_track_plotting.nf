#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gmoviz — incremental_track_plotting
// Build a highly customized circular plot track-by-track, generate legends, and save the final plot to a vector file.
// Input: genome.bam, features.gff3, numeric_data.bed
// Container: quay.io/biocontainers/bioconductor-gmoviz:1.22.0--r45hdfd78af_0
// Requires: GenomicRanges, IRanges, gmoviz
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read ideogram data
//  * 2. [Input & Preparation] Read features
//  * 3. [Input & Preparation] Load numeric data
//  * 4. [Core Analysis] Generate legends
//  * 5. [Visualization & Output] Initialize and plot tracks sequentially inside gmovizPlot

nextflow.enable.dsl = 2

process BIOC_GMOVIZ_INCREMENTAL_TRACK_PLOTTING {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("GenomicRanges", "gmoviz")
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
    library(gmoviz)
    library(GenomicRanges)
    
    # 1. Read ideogram data from the user-provided BAM file
    fly_ideogram_chr4_only <- getIdeogramData(bam_file = "genome.bam")
    
    # 2. Read features from the user-provided GFF3 file
    features <- getFeatures(gff_file = "features.gff3", colours = gmoviz::rich_colours)
    
    # 3. Load numeric data from the user-provided BED/TSV file robustly
    numeric_df <- read.table("numeric_data.bed", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    if (!all(c("chr", "start", "end") %in% colnames(numeric_df)) && !all(c("seqnames", "start", "end") %in% colnames(numeric_df))) {
      numeric_df <- read.table("numeric_data.bed", header = FALSE, sep = "\t", stringsAsFactors = FALSE)
      colnames(numeric_df)[1:3] <- c("chr", "start", "end")
      if (ncol(numeric_df) >= 4) {
        if (is.numeric(numeric_df[[4]])) {
          colnames(numeric_df)[4] <- "value"
        } else if (ncol(numeric_df) >= 5 && is.numeric(numeric_df[[5]])) {
          colnames(numeric_df)[5] <- "value"
        } else {
          numeric_df\$value <- 1.0
        }
      } else {
        numeric_df\$value <- 1.0
      }
    }
    if ("chr" %in% colnames(numeric_df)) {
      colnames(numeric_df)[colnames(numeric_df) == "chr"] <- "seqnames"
    }
    if (!"value" %in% colnames(numeric_df)) {
      if ("score" %in% colnames(numeric_df)) {
        numeric_df\$value <- numeric_df\$score
      } else {
        numeric_df\$value <- 1.0
      }
    }
    numeric_data <- GRanges(
      seqnames = numeric_df\$seqnames,
      ranges = IRanges(start = numeric_df\$start, end = numeric_df\$end),
      value = as.numeric(numeric_df\$value)
    )
    
    # 4. Generate legends
    legend <- makeLegends(
      feature_legend = TRUE, 
      feature_data = features, 
      feature_legend_title = "Regions of interest", 
      scatterplot_legend = TRUE, 
      scatterplot_legend_title = "Numeric data", 
      scatterplot_legend_labels = "value"
    )
    
    # 5. Initialize and plot tracks sequentially inside gmovizPlot
    gmovizPlot(file_name = "example.svg", file_type = "svg", plotting_functions = {
        gmovizInitialise(fly_ideogram_chr4_only, space_between_sectors = 25, start_degree = 78, xaxis_spacing = 30, sector_label_size = 1)
        drawScatterplotTrack(numeric_data, track_height = 0.14, yaxis_increment = 12)
        drawFeatureTrack(features, feature_label_cutoff = 80000, track_height = 0.15)
    }, legends = legend, title = "Chromosome 4", background_colour = "white", width = 8, height = 5.33, units = "in")
    
    # Save meaningful intermediate and final data structures
    saveRDS(fly_ideogram_chr4_only, "fly_ideogram_chr4_only.rds")
    saveRDS(features, "features.rds")
    saveRDS(numeric_data, "numeric_data.rds")
    write.csv(as.data.frame(features), "features.csv", row.names = FALSE)
    write.csv(as.data.frame(numeric_data), "numeric_data.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GMOVIZ_INCREMENTAL_TRACK_PLOTTING":',
        paste0('    gmoviz: ', as.character(packageVersion('gmoviz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_incremental_track_plotting.csv versions.yml
    """
}

workflow BIOC_GMOVIZ_INCREMENTAL_TRACK_PLOTTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome.bam, features.gff3, numeric_data.bed ] ]

    main:
    BIOC_GMOVIZ_INCREMENTAL_TRACK_PLOTTING(ch_input)

    emit:
    tables   = BIOC_GMOVIZ_INCREMENTAL_TRACK_PLOTTING.out.tables
    plots    = BIOC_GMOVIZ_INCREMENTAL_TRACK_PLOTTING.out.plots
    objects  = BIOC_GMOVIZ_INCREMENTAL_TRACK_PLOTTING.out.objects
    versions = BIOC_GMOVIZ_INCREMENTAL_TRACK_PLOTTING.out.versions
}
