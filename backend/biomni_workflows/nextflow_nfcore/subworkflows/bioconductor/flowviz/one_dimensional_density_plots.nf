#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowViz — one_dimensional_density_plots
// Visualize 1D kernel density estimates of flow cytometry channels with gate boundaries.
// Input: GvHD
// Container: quay.io/biocontainers/bioconductor-flowviz:1.74.0--r45hdfd78af_0
// R packages: flowCore, flowStats, flowViz
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowStats, flowViz
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define 1D filters (e.g., curv1Filter)
//  * 2. [Visualization & Output] Plot single-channel density with gate boundaries using densityplot
//  * 3. [Visualization & Output] Plot multi-channel density with a list of filters using densityplot

nextflow.enable.dsl = 2

process BIOC_FLOWVIZ_ONE_DIMENSIONAL_DENSITY_PLOTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20-deps"

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
    .bm_deps <- c("flowCore", "flowStats", "flowViz")
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
    
    # Load required packages
    library(flowCore)
    library(flowViz)
    library(flowStats)
    
    # -----------------------------------------------------------------------------
    # Stage 0: Read User Input and Preprocess
    # -----------------------------------------------------------------------------
    # Read the GvHD flowSet object from the working directory.
    # We support both RDS and RData formats for robustness.
    if (file.exists("GvHD.rds")) {
      GvHD <- readRDS("GvHD.rds")
    } else if (file.exists("GvHD")) {
      GvHD <- tryCatch({
        readRDS("GvHD")
      }, error = function(e) {
        env <- new.env()
        load("GvHD", envir = env)
        env[[ls(env)[1]]]
      })
    } else {
      stop("Required input file 'GvHD' or 'GvHD.rds' not found in the working directory.")
    }
    
    # Subset the flowSet to Patient 6 as described in the vignette
    GvHD <- GvHD[pData(GvHD)\$Patient == 6]
    
    # Transform the fluorescence channels using asinh
    tf <- transformList(from = colnames(GvHD)[3:7], tfun = asinh)
    GvHD <- tf %on% GvHD
    
    # Define gates needed for the multi-channel density plot
    rgate <- rectangleGate("FSC-H" = c(0, 400), "SSC-H" = c(-50, 300))
    rgate2 <- rgate * rectangleGate("FL1-H" = c(2, 4))
    
    # -----------------------------------------------------------------------------
    # Stage 1 & 2: Define 1D filters and Plot single-channel density
    # -----------------------------------------------------------------------------
    # Open PDF device for the single-channel density plot
    pdf("densityplot_single.pdf", width = 8, height = 6)
    
    # Plot single-channel density with gate boundaries using densityplot
    p1 <- densityplot(~ `FSC-H`, GvHD, filter = curv1Filter("FSC-H"))
    print(p1)
    
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 3: Plot multi-channel density with a list of filters
    # -----------------------------------------------------------------------------
    # Open PDF device for the multi-channel density plot
    pdf("densityplot_multi.pdf", width = 10, height = 6)
    
    # Plot multi-channel density with a list of filters using densityplot
    p2 <- densityplot(~ ., GvHD, channels = c("FSC-H", "SSC-H", "FL1-H"), 
                      filter = list(curv1Filter("FSC-H"), NULL, rgate2))
    print(p2)
    
    dev.off()

    writeLines(c(
        '"BIOC_FLOWVIZ_ONE_DIMENSIONAL_DENSITY_PLOTS":',
        paste0('    flowViz: ', as.character(packageVersion('flowViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_dimensional_density_plots.csv versions.yml
    """
}

workflow BIOC_FLOWVIZ_ONE_DIMENSIONAL_DENSITY_PLOTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ GvHD ] ]

    main:
    BIOC_FLOWVIZ_ONE_DIMENSIONAL_DENSITY_PLOTS(ch_input)

    emit:
    tables   = BIOC_FLOWVIZ_ONE_DIMENSIONAL_DENSITY_PLOTS.out.tables
    plots    = BIOC_FLOWVIZ_ONE_DIMENSIONAL_DENSITY_PLOTS.out.plots
    objects  = BIOC_FLOWVIZ_ONE_DIMENSIONAL_DENSITY_PLOTS.out.objects
    versions = BIOC_FLOWVIZ_ONE_DIMENSIONAL_DENSITY_PLOTS.out.versions
}
