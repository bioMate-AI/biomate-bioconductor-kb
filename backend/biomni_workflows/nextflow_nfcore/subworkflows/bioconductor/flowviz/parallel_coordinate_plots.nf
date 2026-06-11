#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowViz — parallel_coordinate_plots
// Visualize multi-dimensional flow cytometry data using parallel coordinate plots grouped by filter results.
// Input: GvHD
// Container: quay.io/biocontainers/bioconductor-flowviz:1.74.0--r45hdfd78af_0
// R packages: flowCore, flowViz
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowViz
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute filter results (e.g., norm2Filter)
//  * 2. [Visualization & Output] Plot using parallel with the filter argument

nextflow.enable.dsl = 2

process BIOC_FLOWVIZ_PARALLEL_COORDINATE_PLOTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("flowCore", "flowViz")
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
    library(flowCore)
    library(flowViz)
    
    # Read the user input file 'GvHD' from the working directory
    if (file.exists("GvHD")) {
      GvHD <- readRDS("GvHD")
    } else if (file.exists("GvHD.rds")) {
      GvHD <- readRDS("GvHD.rds")
    } else {
      stop("Error: Input file 'GvHD' or 'GvHD.rds' not found in the working directory.")
    }
    
    # Subset and transform the data as documented in the vignette
    GvHD <- GvHD[pData(GvHD)\$Patient == 6]
    tf <- transformList(from = colnames(GvHD)[3:7], tfun = asinh)
    GvHD <- tf %on% GvHD
    
    # Compute filter results
    n2Filter <- norm2Filter("SSC-H", "FSC-H", scale = 2, filterId = "Lymphocytes")
    n2Filter.results <- filter(GvHD, n2Filter)
    
    # Generate the parallel coordinate plot
    p <- parallel(~ . | Visit, GvHD, filter = n2Filter.results, alpha = 0.01)
    
    # Save the plot to a PDF file
    pdf("parallel_coordinate_plot.pdf", width = 10, height = 8)
    print(p)
    dev.off()
    
    # Save the filter results as an RDS object
    saveRDS(n2Filter.results, "n2Filter_results.rds")
    
    # Extract and save filter statistics to a CSV file
    stats_list <- lapply(names(n2Filter.results), function(name) {
      res <- n2Filter.results[[name]]
      sum_res <- summary(res)
      data.frame(
        Sample = name,
        Total_Events = sum_res@count,
        Positive_Events = sum_res@true,
        Percent_Positive = sum_res@p
      )
    })
    stats_df <- do.call(rbind, stats_list)
    write.csv(stats_df, "filter_statistics.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_FLOWVIZ_PARALLEL_COORDINATE_PLOTS":',
        paste0('    flowViz: ', as.character(packageVersion('flowViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_parallel_coordinate_plots.csv versions.yml
    """
}

workflow BIOC_FLOWVIZ_PARALLEL_COORDINATE_PLOTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GvHD ] ]

    main:
    BIOC_FLOWVIZ_PARALLEL_COORDINATE_PLOTS(ch_input)

    emit:
    tables   = BIOC_FLOWVIZ_PARALLEL_COORDINATE_PLOTS.out.tables
    plots    = BIOC_FLOWVIZ_PARALLEL_COORDINATE_PLOTS.out.plots
    objects  = BIOC_FLOWVIZ_PARALLEL_COORDINATE_PLOTS.out.objects
    versions = BIOC_FLOWVIZ_PARALLEL_COORDINATE_PLOTS.out.versions
}
