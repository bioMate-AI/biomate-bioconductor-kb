#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gmoviz — feature_diagram_plasmid_map
// Generate a circular plasmid map or complex construct diagram showing features, coverage, and custom links.
// Input: plasmid_features.gff3, plasmid_coverage.bam
// Container: quay.io/biocontainers/bioconductor-gmoviz:1.22.0--r45hdfd78af_0
// R packages: GenomicRanges, gmoviz, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, gmoviz, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define plasmid ideogram range
//  * 2. [Input & Preparation] Read features from GFF
//  * 3. [Input & Preparation] Read or simulate coverage data
//  * 4. [Visualization & Output] Plot the feature diagram with coverage

nextflow.enable.dsl = 2

process BIOC_GMOVIZ_FEATURE_DIAGRAM_PLASMID_MAP {
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
    .bm_deps <- c("GenomicRanges", "gmoviz", "rtracklayer")
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
    library(gmoviz)
    library(GenomicRanges)
    library(rtracklayer)
    
    # Define input file paths
    gff_input <- "plasmid_features.gff3"
    bam_input <- "plasmid_coverage.bam"
    
    # Check if input files exist
    if (!file.exists(gff_input)) {
      stop(paste("Required input file missing:", gff_input))
    }
    if (!file.exists(bam_input)) {
      stop(paste("Required input file missing:", bam_input))
    }
    
    # 1. Define plasmid ideogram range dynamically from the BAM file
    plasmid_ideogram <- getIdeogramData(bam_file = bam_input)
    seq_name <- as.character(seqnames(plasmid_ideogram)[1])
    
    # 2. Read features from GFF file
    plasmid_features <- getFeatures(
      gff_file = gff_input, 
      colour_by_type = FALSE, 
      colours = rich_colours
    )
    
    # 3. Read coverage data from BAM file
    # Using a window size of 10 and smoothing window of 20 for a balance of speed and detail
    coverage <- getCoverage(
      regions_of_interest = seq_name, 
      bam_file = bam_input, 
      window_size = 10, 
      smoothing_window_size = 20
    )
    
    # 4. Plot the feature diagram with coverage and save to PDF
    pdf("plasmid_map.pdf", width = 8, height = 8)
    featureDiagram(
      plasmid_ideogram, 
      plasmid_features, 
      track_height = 0.17, 
      coverage_rectangle = seq_name, 
      coverage_data = coverage, 
      label_track_height = 0.11, 
      space_between_sectors = 0, 
      xaxis_spacing = 30, 
      start_degree = 90
    )
    dev.off()
    
    # Save meaningful results to disk
    write.csv(as.data.frame(plasmid_features), "plasmid_features_extracted.csv", row.names = FALSE)
    saveRDS(plasmid_ideogram, "plasmid_ideogram.rds")
    saveRDS(coverage, "plasmid_coverage.rds")

    writeLines(c(
        '"BIOC_GMOVIZ_FEATURE_DIAGRAM_PLASMID_MAP":',
        paste0('    gmoviz: ', as.character(packageVersion('gmoviz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_feature_diagram_plasmid_map.csv versions.yml
    """
}

workflow BIOC_GMOVIZ_FEATURE_DIAGRAM_PLASMID_MAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ plasmid_features.gff3, plasmid_coverage.bam ] ]

    main:
    BIOC_GMOVIZ_FEATURE_DIAGRAM_PLASMID_MAP(ch_input)

    emit:
    tables   = BIOC_GMOVIZ_FEATURE_DIAGRAM_PLASMID_MAP.out.tables
    plots    = BIOC_GMOVIZ_FEATURE_DIAGRAM_PLASMID_MAP.out.plots
    objects  = BIOC_GMOVIZ_FEATURE_DIAGRAM_PLASMID_MAP.out.objects
    versions = BIOC_GMOVIZ_FEATURE_DIAGRAM_PLASMID_MAP.out.versions
}
