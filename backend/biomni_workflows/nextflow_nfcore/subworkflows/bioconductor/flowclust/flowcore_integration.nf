#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowClust — flowcore_integration
// Integrate flowClust clustering into a flowCore gating workflow using tmixFilter, Subset, split, and subsetting gates.
// Input: rituximab2
// Container: quay.io/biocontainers/bioconductor-flowclust:3.48.0--r45h01b2380_0
// R packages: flowClust, flowCore
// Bioconductor: 3.20 | R: 4.4
// Requires: flowClust, flowCore
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a tmixFilter object
//  * 2. [Core Analysis] Apply the filter to the flowFrame
//  * 3. [Core Analysis] Subset or split the flowFrame based on the filter results
//  * 4. [Core Analysis] Combine tmixFilter with standard flowCore gates (e.g., rectangleGate) using %subset%

nextflow.enable.dsl = 2

process BIOC_FLOWCLUST_FLOWCORE_INTEGRATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("flowClust", "flowCore")
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
    library(flowClust)
    library(flowCore)
    
    # Read the user input file 'rituximab2' from the working directory
    # We check for both 'rituximab2' and 'rituximab2.rds' to be robust
    if (file.exists("rituximab2")) {
      rituximab2 <- readRDS("rituximab2")
    } else if (file.exists("rituximab2.rds")) {
      rituximab2 <- readRDS("rituximab2.rds")
    } else {
      stop("Required input file 'rituximab2' (or 'rituximab2.rds') not found in the working directory.")
    }
    
    # 1. Create a tmixFilter object
    s2filter <- tmixFilter("s2filter", c("FL1.H", "FL3.H"), K = 3, B = 100)
    
    # 2. Apply the filter to the flowFrame
    res2f <- filter(rituximab2, s2filter)
    
    # 3. Subset or split the flowFrame based on the filter results
    sub_frame <- Subset(rituximab2, res2f)
    split_frames <- split(rituximab2, res2f, population = list(sc1 = 1:2, sc2 = 3))
    
    # 4. Combine tmixFilter with standard flowCore gates (e.g., rectangleGate) using %subset%
    rectGate <- rectangleGate(
      filterId = "rectRegion",
      "FL1.H" = c(0, 400),
      "FL3.H" = c(0, 800)
    )
    MBCfilter <- tmixFilter("MBCfilter", c("FL1.H", "FL3.H"), K = 2, B = 100)
    final_filtered <- filter(rituximab2, MBCfilter %subset% rectGate)
    
    # Write meaningful output files
    # Save the RDS objects of the results
    saveRDS(res2f, "res2f_filter_result.rds")
    saveRDS(sub_frame, "subset_flowFrame.rds")
    saveRDS(split_frames, "split_flowFrames.rds")
    saveRDS(final_filtered, "final_filtered_result.rds")
    
    # Save a summary table of cell counts at different stages
    summary_df <- data.frame(
      Stage = c("Original rituximab2", "Subset (res2f)", "Split sc1 (clusters 1-2)", "Split sc2 (cluster 3)"),
      CellCount = c(nrow(rituximab2), nrow(sub_frame), nrow(split_frames\$sc1), nrow(split_frames\$sc2))
    )
    write.csv(summary_df, "flow_summary.csv", row.names = FALSE)
    
    # Generate diagnostic plots
    pdf("flowClust_integration_plots.pdf", width = 10, height = 8)
    tryCatch({
      # Plot the tmixFilterResult if a plot method is available
      plot(rituximab2, res2f, main = "tmixFilter Clustering (K=3)")
    }, error = function(e) {
      warning("Could not plot res2f: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_FLOWCLUST_FLOWCORE_INTEGRATION":',
        paste0('    flowClust: ', as.character(packageVersion('flowClust')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowcore_integration.csv versions.yml
    """
}

workflow BIOC_FLOWCLUST_FLOWCORE_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rituximab2 ] ]

    main:
    BIOC_FLOWCLUST_FLOWCORE_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_FLOWCLUST_FLOWCORE_INTEGRATION.out.tables
    plots    = BIOC_FLOWCLUST_FLOWCORE_INTEGRATION.out.plots
    objects  = BIOC_FLOWCLUST_FLOWCORE_INTEGRATION.out.objects
    versions = BIOC_FLOWCLUST_FLOWCORE_INTEGRATION.out.versions
}
