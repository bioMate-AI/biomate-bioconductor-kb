#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ioniser — minion_quality_control
// Read FAST5 files, summarize their contents, and generate various quality control plots.
// Input: /path/to/data/*.fast5
// Container: quay.io/biocontainers/bioconductor-ioniser:2.34.0--r45hdfd78af_0
// R packages: dplyr, ggplot2, gridExtra, IONiseR, minionsummarydata, ShortRead
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: heatmap

nextflow.enable.dsl = 2

process BIOC_IONISER_MINION_QUALITY_CONTROL {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ioniser:2.34.0--r45hdfd78af_0"

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
    .bm_deps <- c("dplyr", "ggplot2", "gridExtra", "IONiseR", "minionsummarydata", "ShortRead")
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
    library(IONiseR)
    library(ggplot2)
    library(gridExtra)
    library(dplyr)
    library(ShortRead)
    
    # --- List FAST5 files from the user-specified directory ---
    fast5files <- list.files(path = "/path/to/data/", pattern = ".fast5\$", full.names = TRUE)
    
    if (length(fast5files) == 0) {
      stop("No FAST5 files found in /path/to/data/")
    }
    
    # --- Read summaries using readFast5Summary() ---
    example.summary <- readFast5Summary( fast5files )
    
    # Save the summary object to disk
    saveRDS(example.summary, file = "fast5_summary.rds")
    
    # Map the summary object to the variables used in the documented code
    s.typhi.rep1 <- example.summary
    s.typhi.rep3 <- example.summary
    
    # --- Extract basecalled data using baseCalled() ---
    bc_all <- baseCalled(s.typhi.rep1)
    write.csv(bc_all, file = "basecalled_all.csv", row.names = FALSE)
    
    # Subset safely in case there are fewer than 2 reads in the dataset
    tryCatch({
      if (nrow(bc_all) >= 2) {
        bc_subset <- baseCalled(s.typhi.rep1[1:2])
        write.csv(bc_subset, file = "basecalled_subset.csv", row.names = FALSE)
      } else {
        message("Fewer than 2 reads available; skipping subsetting step.")
      }
    }, error = function(e) {
      message("Error during subsetting: ", e\$message)
    })
    
    # --- Plot read accumulation and active channels ---
    pdf("qc_plots_accumulation_active.pdf", width = 12, height = 6)
    p1 <- plotReadAccumulation(s.typhi.rep1)
    p2 <- plotActiveChannels(s.typhi.rep1)
    grid.arrange(p1, p2, ncol = 2)
    dev.off()
    
    # --- Plot read categories and qualities ---
    pdf("qc_plots_categories_quals.pdf", width = 12, height = 6)
    p1 <- plotReadCategoryCounts(s.typhi.rep1)
    p2 <- plotReadCategoryQuals(s.typhi.rep1)
    grid.arrange(p1, p2, ncol = 2)
    dev.off()
    
    # --- Plot event and base production rates ---
    pdf("qc_plots_rates.pdf", width = 12, height = 6)
    p1 <- plotEventRate(s.typhi.rep1)
    p2 <- plotBaseProductionRate(s.typhi.rep1)
    grid.arrange(p1, p2, ncol = 2)
    dev.off()
    
    # --- Generate flow cell layout plots ---
    pdf("qc_plots_layout.pdf", width = 12, height = 6)
    p1 <- layoutPlot(s.typhi.rep1, attribute = "nreads")
    p2 <- layoutPlot(s.typhi.rep1, attribute = "kb")
    grid.arrange(p1, p2, ncol = 2)
    dev.off()
    
    # --- Generate custom channel heatmaps ---
    read_count_2D <- baseCalled(s.typhi.rep1) %>% ## start with base called reads
      filter(strand == 'template') %>% ## keep template so we don't count things twice
      left_join(readInfo(s.typhi.rep1), by = 'id') %>% ## channel stored in @readInfo slot, match by id column
      group_by(channel) %>% ## group according to channel
      summarise(d2_count = length(which(full_2D == TRUE)), ## count those with full 2D status
                d2_prop = length(which(full_2D == TRUE)) / n()) ## divide by total count of reads from channel
    
    write.csv(read_count_2D, file = "read_count_2D.csv", row.names = FALSE)
    
    pdf("qc_plots_channel_heatmap.pdf", width = 12, height = 6)
    p1 <- channelHeatmap(read_count_2D, zValue = 'd2_count')
    p2 <- channelHeatmap(read_count_2D, zValue = 'd2_prop')
    grid.arrange(p1, p2, ncol = 2)
    dev.off()
    
    # --- Plot channel activity over time ---
    pdf("qc_plots_channel_activity.pdf", width = 10, height = 6)
    z_scale = select(eventData(s.typhi.rep3), id, median_signal)
    channelActivityPlot( s.typhi.rep3, zScale = z_scale )
    dev.off()
    
    # --- Plot k-mer frequency correlation ---
    pdf("qc_plots_kmer_correlation.pdf", width = 8, height = 8)
    plotKmerFrequencyCorrelation( s.typhi.rep3, only2D = FALSE )
    dev.off()

    writeLines(c(
        '"BIOC_IONISER_MINION_QUALITY_CONTROL":',
        paste0('        ioniser: ', as.character(packageVersion("ioniser")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_minion_quality_control.csv versions.yml
    """
}

workflow BIOC_IONISER_MINION_QUALITY_CONTROL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ /path/to/data/*.fast5 ] ]

    main:
    BIOC_IONISER_MINION_QUALITY_CONTROL(ch_input)

    emit:
    tables   = BIOC_IONISER_MINION_QUALITY_CONTROL.out.tables
    plots    = BIOC_IONISER_MINION_QUALITY_CONTROL.out.plots
    objects  = BIOC_IONISER_MINION_QUALITY_CONTROL.out.objects
    versions = BIOC_IONISER_MINION_QUALITY_CONTROL.out.versions
}
