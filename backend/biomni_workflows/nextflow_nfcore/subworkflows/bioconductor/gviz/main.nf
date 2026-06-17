#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Gviz — numeric_data_visualization
// Visualize numeric genomic data (e.g., microarray signals, custom scores, or bedGraph files) using various plot types and grouping.
// Input: twoGroups, bgFile.bedGraph
// Container: quay.io/biocontainers/bioconductor-gviz:1.54.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, Gviz
// Visualizations: box plot, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load genomic coordinates and numeric data
//  * 2. [Input & Preparation] Construct a DataTrack object
//  * 3. [Visualization & Output] Plot the track using plotTracks with specific visualization types (e.g., histogram, boxplot, heatmap)
//  * 4. [Core Analysis] Group data and add a legend

nextflow.enable.dsl = 2

process BIOC_GVIZ_NUMERIC_DATA_VISUALIZATION {
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
    .bm_deps <- c("Gviz", "GenomicRanges")
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
        
        # Load required libraries
        library(Gviz)
        library(GenomicRanges)
        
        # 1. Load genomic coordinates and numeric data
        # Read the twoGroups GRanges object from the working directory
        if (file.exists("twoGroups")) {
          twoGroups <- readRDS("twoGroups")
        } else if (file.exists("twoGroups.rds")) {
          twoGroups <- readRDS("twoGroups.rds")
        } else {
          stop("Required input file 'twoGroups' (RDS format) not found in the working directory.")
        }
        
        # Define the path to the bedGraph file in the working directory
        bgFile <- "bgFile.bedGraph"
        if (!file.exists(bgFile)) {
          stop("Required input file 'bgFile.bedGraph' not found in the working directory.")
        }
        
        # 2. Construct a DataTrack object for the twoGroups data
        dTrack <- DataTrack(twoGroups, name = "uniform")
        
        # 3. Plot the track using plotTracks with specific visualization types
        # Save default plot
        pdf("plot1_uniform_default.pdf")
        plotTracks(dTrack)
        dev.off()
        
        # Save boxplot, average, and grid plot
        pdf("plot2_uniform_boxplot.pdf")
        plotTracks(dTrack, type = c("boxplot", "a", "g"))
        dev.off()
        
        # Save heatmap plot
        pdf("plot3_uniform_heatmap.pdf")
        plotTracks(dTrack, type = c("heatmap"), showSampleNames = TRUE, cex.sampleNames = 0.6)
        dev.off()
        
        # 4. Group data and add a legend
        # Dynamically determine grouping based on the number of metadata columns
        n_cols <- ncol(mcols(twoGroups))
        half_cols <- ceiling(n_cols / 2)
        user_groups <- rep(c("control", "treated"), times = c(half_cols, n_cols - half_cols))
        
        # Save grouped plot with confidence intervals
        pdf("plot4_uniform_grouped_confint.pdf")
        plotTracks(dTrack, groups = user_groups, type = c("a", "p", "confint"))
        dev.off()
        
        # Save grouped plot with legend
        pdf("plot5_uniform_grouped_legend.pdf")
        plotTracks(dTrack, groups = user_groups, type = c("a", "p"), legend = TRUE)
        dev.off()
        
        # Construct and plot DataTrack from the bedGraph file
        # Dynamically extract chromosome and genome from the user's GRanges object
        user_chr <- as.character(unique(seqnames(twoGroups)))[1]
        user_genome <- as.character(genome(twoGroups))[1]
        
        dTrack2 <- DataTrack(range = bgFile, genome = user_genome, type = "l", chromosome = user_chr, name = "bedGraph")
        
        pdf("plot6_bedGraph.pdf")
        plotTracks(dTrack2)
        dev.off()

    writeLines(c(
        '"BIOC_GVIZ_NUMERIC_DATA_VISUALIZATION":',
        paste0('    Gviz: ', as.character(packageVersion('Gviz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_numeric_data_visualization.csv versions.yml
    """
}

workflow BIOC_GVIZ_NUMERIC_DATA_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ twoGroups, bgFile.bedGraph ] ]

    main:
    BIOC_GVIZ_NUMERIC_DATA_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_GVIZ_NUMERIC_DATA_VISUALIZATION.out.tables
    plots    = BIOC_GVIZ_NUMERIC_DATA_VISUALIZATION.out.plots
    objects  = BIOC_GVIZ_NUMERIC_DATA_VISUALIZATION.out.objects
    versions = BIOC_GVIZ_NUMERIC_DATA_VISUALIZATION.out.versions
}
