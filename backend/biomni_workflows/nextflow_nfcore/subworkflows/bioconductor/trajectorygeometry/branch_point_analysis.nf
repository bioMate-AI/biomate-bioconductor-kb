#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TrajectoryGeometry — branch_point_analysis
// Identify the branch point where two trajectories diverge and analyze the trajectory geometry starting from successive points.
// Input: chol_attributes, chol_pseudo_time, hep_attributes, hep_pseudo_time
// Container: quay.io/biocontainers/bioconductor-trajectorygeometry:1.18.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RColorBrewer, TrajectoryGeometry, dplyr, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate minimum distances between trajectories along pseudotime using distanceBetweenTrajectories
//  * 2. [Visualization & Output] Plot distances to identify the branch point
//  * 3. [Core Analysis] Analyze trajectory geometry starting from successive points using analyseBranchPoint
//  * 4. [Visualization & Output] Extract and visualize branch point statistics using visualiseBranchPointStats

nextflow.enable.dsl = 2

process BIOC_TRAJECTORYGEOMETRY_BRANCH_POINT_ANALYSIS {
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
    .bm_deps <- c("TrajectoryGeometry", "RColorBrewer", "dplyr", "ggplot2")
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
        library(TrajectoryGeometry)
        library(RColorBrewer)
        library(dplyr)
        library(ggplot2)
        
        # Set random seed for reproducibility
        set.seed(42)
        
        # Helper function to robustly load input files (RDS, CSV, TSV)
        load_input = function(base_name, is_matrix = FALSE) {
          extensions = c("", ".rds", ".csv", ".tsv", ".txt")
          for (ext in extensions) {
            file_path = paste0(base_name, ext)
            if (file.exists(file_path)) {
              # Try reading as RDS first
              obj = tryCatch(readRDS(file_path), error = function(e) NULL)
              if (!is.null(obj)) {
                if (is_matrix) return(as.matrix(obj))
                return(obj)
              }
              
              # Try reading as CSV/TSV
              sep = if (ext == ".tsv") "\t" else ","
              df = tryCatch(read.csv(file_path, sep = sep, header = TRUE, row.names = 1, check.names = FALSE), error = function(e) NULL)
              if (!is.null(df)) {
                if (is_matrix) {
                  return(as.matrix(df))
                } else {
                  # If it's a vector, it might be a single column with row names as cell IDs
                  if (ncol(df) == 1) {
                    vec = df[[1]]
                    names(vec) = rownames(df)
                    return(vec)
                  } else if (ncol(df) == 0) {
                    df_no_rn = read.csv(file_path, sep = sep, header = FALSE)
                    if (ncol(df_no_rn) == 1) {
                      return(df_no_rn[[1]])
                    }
                  }
                }
              }
              
              # Try reading as scan/lines for vector
              if (!is_matrix) {
                vec = tryCatch(scan(file_path, quiet = TRUE), error = function(e) NULL)
                if (!is.null(vec)) return(vec)
              }
            }
          }
          stop(paste("Error: Could not find or read input file for:", base_name))
        }
        
        # Read user input files from the working directory
        chol_attributes = load_input("chol_attributes", is_matrix = TRUE)
        chol_pseudo_time = load_input("chol_pseudo_time", is_matrix = FALSE)
        hep_attributes = load_input("hep_attributes", is_matrix = TRUE)
        hep_pseudo_time = load_input("hep_pseudo_time", is_matrix = FALSE)
        
        # 1. Calculate minimum distances between trajectories along pseudotime
        distances = distanceBetweenTrajectories(chol_attributes, chol_pseudo_time,
            hep_attributes)
        
        # 2. Plot distances to identify the branch point and save to PDF
        pdf("distances_plot.pdf")
        plot(distances\$pseudotime, distances\$distance,
            xlab = "cholangiocyte pseudotime", ylab = "minimum distance")
        dev.off()
        
        # Save distances data frame and RDS
        write.csv(distances, "distances.csv", row.names = FALSE)
        saveRDS(distances, "distances.rds")
        
        # 3. Analyze trajectory geometry starting from successive points
        pt_min = min(chol_pseudo_time, na.rm = TRUE)
        pt_max = max(chol_pseudo_time, na.rm = TRUE)
        pt_step = (pt_max - pt_min) / 10
        if (pt_step == 0) pt_step = 1
        
        num_cols = min(3, ncol(chol_attributes))
        
        chol_branch_point_results = analyseBranchPoint(chol_attributes[, 1:num_cols, drop = FALSE],
                                                chol_pseudo_time,
                                                randomizationParams = c("byPermutation",
                                                                "permuteWithinColumns"),
                                                statistic = "mean",
                                                start = pt_min,
                                                stop = pt_max,
                                                step = pt_step,
                                                nSamples = 100,
                                                N = 1)
        
        # Save branch point analysis results
        saveRDS(chol_branch_point_results, "chol_branch_point_results.rds")
        
        # 4. Extract and visualize branch point statistics
        cholBranchPointStats = visualiseBranchPointStats(chol_branch_point_results)
        
        # Save the plots to PDF files
        ggsave("chol_distance_plot.pdf", plot = cholBranchPointStats\$distancePlot)
        ggsave("chol_p_value_plot.pdf", plot = cholBranchPointStats\$pValuePlot)
        
        # Save the stats object
        saveRDS(cholBranchPointStats, "chol_branch_point_stats.rds")
        
        # Print plots to standard output/graphics device
        print(cholBranchPointStats\$distancePlot)
        print(cholBranchPointStats\$pValuePlot)

    writeLines(c(
        '"BIOC_TRAJECTORYGEOMETRY_BRANCH_POINT_ANALYSIS":',
        paste0('    TrajectoryGeometry: ', as.character(packageVersion('TrajectoryGeometry')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_branch_point_analysis.csv versions.yml
    """
}

workflow BIOC_TRAJECTORYGEOMETRY_BRANCH_POINT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ chol_attributes, chol_pseudo_time, hep_attributes, hep_pseudo_time ] ]

    main:
    BIOC_TRAJECTORYGEOMETRY_BRANCH_POINT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TRAJECTORYGEOMETRY_BRANCH_POINT_ANALYSIS.out.tables
    plots    = BIOC_TRAJECTORYGEOMETRY_BRANCH_POINT_ANALYSIS.out.plots
    objects  = BIOC_TRAJECTORYGEOMETRY_BRANCH_POINT_ANALYSIS.out.objects
    versions = BIOC_TRAJECTORYGEOMETRY_BRANCH_POINT_ANALYSIS.out.versions
}
