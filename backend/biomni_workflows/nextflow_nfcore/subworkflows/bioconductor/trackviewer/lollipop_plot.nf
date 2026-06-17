#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: trackViewer — lollipop_plot
// Visualize genomic variants, mutations, or methylation sites as lollipop markers over gene/protein features.
// Input: variants.gr, features.gr
// Container: quay.io/biocontainers/bioconductor-trackviewer:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, trackViewer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare variant GRanges with metadata (score, color, shape)
//  * 2. [Input & Preparation] Prepare feature GRanges with metadata (fill, height)
//  * 3. [Visualization & Output] Plot using lolliplot

nextflow.enable.dsl = 2

process BIOC_TRACKVIEWER_LOLLIPOP_PLOT {
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
    .bm_deps <- c("trackViewer", "GenomicRanges")
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
    library(trackViewer)
    library(GenomicRanges)
    
    # Step 1: Read the declared user input files from the working directory
    # The files are expected to be RDS files containing GRanges objects.
    sample.gr <- readRDS("variants.gr")
    features <- readRDS("features.gr")
    
    # Step 2: Prepare variant GRanges with metadata (score, color, shape)
    # Ensure metadata columns exist; if not present in the input, assign sensible defaults.
    if (!"score" %in% colnames(mcols(sample.gr))) {
      sample.gr\$score <- 1
    }
    if (!"color" %in% colnames(mcols(sample.gr))) {
      sample.gr\$color <- "darkblue"
    }
    if (!"shape" %in% colnames(mcols(sample.gr))) {
      sample.gr\$shape <- "circle"
    }
    
    # Step 3: Prepare feature GRanges with metadata (fill, height)
    if (!"fill" %in% colnames(mcols(features))) {
      # Assign a default color palette to features if not specified
      features\$fill <- c("#FF8833", "#51C6E6", "#DFA32D", "#4B9CDF")[seq_along(features) %% 4 + 1]
    }
    if (!"height" %in% colnames(mcols(features))) {
      features\$height <- 0.05
    }
    
    # Step 4: Plot using lolliplot and save to a PDF file
    pdf("lollipop_plot.pdf", width = 10, height = 6)
    lolliplot(sample.gr, features)
    dev.off()
    
    # Step 5: Save the prepared GRanges objects and a summary table
    saveRDS(sample.gr, "prepared_variants.rds")
    saveRDS(features, "prepared_features.rds")
    
    variants_df <- as.data.frame(sample.gr)
    write.csv(variants_df, "variants_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_TRACKVIEWER_LOLLIPOP_PLOT":',
        paste0('    trackViewer: ', as.character(packageVersion('trackViewer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lollipop_plot.csv versions.yml
    """
}

workflow BIOC_TRACKVIEWER_LOLLIPOP_PLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ variants.gr, features.gr ] ]

    main:
    BIOC_TRACKVIEWER_LOLLIPOP_PLOT(ch_input)

    emit:
    tables   = BIOC_TRACKVIEWER_LOLLIPOP_PLOT.out.tables
    plots    = BIOC_TRACKVIEWER_LOLLIPOP_PLOT.out.plots
    objects  = BIOC_TRACKVIEWER_LOLLIPOP_PLOT.out.objects
    versions = BIOC_TRACKVIEWER_LOLLIPOP_PLOT.out.versions
}
