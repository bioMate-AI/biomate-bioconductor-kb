#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TrajectoryGeometry — trajectory_directionality_and_comparison
// Sample paths from single-cell trajectories, test them for directionality against randomized paths, and compare the directionality of two different trajectories.
// Input: single_cell_matrix, chol_pseudo_time, hep_pseudo_time
// Container: quay.io/biocontainers/bioconductor-trajectorygeometry:1.18.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RColorBrewer, TrajectoryGeometry, dplyr, ggplot2, rgl
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter and normalize pseudotime trajectories
//  * 2. [Core Analysis] Sample paths using samplePath
//  * 3. [Core Analysis] Test paths for directionality using testPathForDirectionality
//  * 4. [Visualization & Output] Plot path projections using plotPathProjectionCenterAndCircle
//  * 5. [Core Analysis] Analyze multiple sampled paths using analyseSingleCellTrajectory
//  * 6. [Visualization & Output] Compare trajectories and visualize statistics using visualiseTrajectoryStats

nextflow.enable.dsl = 2

process BIOC_TRAJECTORYGEOMETRY_TRAJECTORY_DIRECTIONALITY_AND_COMPARISON {
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
    
    # Set up colors
    colors = colorRampPalette(brewer.pal(11,'Spectral')[-6])(100)
    
    # Set random seed for reproducibility
    set.seed(42)
    
    # Helper function to load input files from the working directory
    load_input <- function(var_name) {
      rds_path <- paste0(var_name, ".rds")
      csv_path <- paste0(var_name, ".csv")
      tsv_path <- paste0(var_name, ".tsv")
      txt_path <- paste0(var_name, ".txt")
      
      if (file.exists(rds_path)) {
        message("Loading ", rds_path)
        return(readRDS(rds_path))
      } else if (file.exists(csv_path)) {
        message("Loading ", csv_path)
        df <- read.csv(csv_path, row.names = 1, check.names = FALSE)
        if (ncol(df) == 1) {
          vec <- df[[1]]
          names(vec) <- rownames(df)
          return(vec)
        }
        return(as.matrix(df))
      } else if (file.exists(tsv_path)) {
        message("Loading ", tsv_path)
        df <- read.delim(tsv_path, row.names = 1, check.names = FALSE)
        if (ncol(df) == 1) {
          vec <- df[[1]]
          names(vec) <- rownames(df)
          return(vec)
        }
        return(as.matrix(df))
      } else if (file.exists(txt_path)) {
        message("Loading ", txt_path)
        df <- read.table(txt_path, header = TRUE, row.names = 1, check.names = FALSE)
        if (ncol(df) == 1) {
          vec <- df[[1]]
          names(vec) <- rownames(df)
          return(vec)
        }
        return(as.matrix(df))
      } else {
        # Fallback: search for any file starting with the variable name
        all_files <- list.files()
        matching <- all_files[startsWith(all_files, var_name)]
        if (length(matching) > 0) {
          first_match <- matching[1]
          message("Loading matched file: ", first_match)
          if (grepl("\\\\.rds\$", first_match, ignore.case = TRUE)) {
            return(readRDS(first_match))
          } else {
            df <- read.csv(first_match, row.names = 1, check.names = FALSE)
            if (ncol(df) == 1) {
              vec <- df[[1]]
              names(vec) <- rownames(df)
              return(vec)
            }
            return(as.matrix(df))
          }
        }
        stop(paste("Error: Required input file not found for:", var_name))
      }
    }
    
    # 1. Read user input files
    single_cell_matrix <- load_input("single_cell_matrix")
    chol_pseudo_time <- load_input("chol_pseudo_time")
    hep_pseudo_time <- load_input("hep_pseudo_time")
    
    # 2. Filter and normalize pseudotime trajectories
    chol_attributes = single_cell_matrix[!is.na(chol_pseudo_time),]
    hep_attributes = single_cell_matrix[!is.na(hep_pseudo_time),]
    chol_pseudo_time = chol_pseudo_time[!is.na(chol_pseudo_time)]
    hep_pseudo_time = hep_pseudo_time[!is.na(hep_pseudo_time)]
    
    chol_pseudo_time_normalised =
        chol_pseudo_time  %>% {100*((. - min(.))/(max(.) -min(.)))}
    hep_pseudo_time_normalised =
        hep_pseudo_time %>% {100*((. - min(.))/(max(.)- min(.)))}
    
    # 3. Sample paths using samplePath
    cholPath = samplePath(chol_attributes, chol_pseudo_time_normalised)
    hepPath = samplePath(hep_attributes, hep_pseudo_time_normalised)
    
    # 4. Test paths for directionality using testPathForDirectionality
    cholAnswerPermutation = testPathForDirectionality(cholPath[,1:3],
        randomizationParams = c('byPermutation','permuteWithinColumns'),
        statistic = "mean",
        N = 100)
    
    hepAnswerPermutation = testPathForDirectionality(hepPath[,1:3],
        randomizationParams = c('byPermutation','permuteWithinColumns'),
        statistic = "mean",
        N = 100)
    
    cholAnswerSteps = testPathForDirectionality(cholPath[,1:3],
        randomizationParams = c('bySteps','preserveLengths'),
        statistic = "mean",
        N = 100)
    
    hepAnswerSteps = testPathForDirectionality(hepPath[,1:3],
        randomizationParams = c('bySteps','preserveLengths'),
        statistic = "mean",
        N = 100)
    
    # Save directionality test results to a CSV summary table
    summary_df <- data.frame(
      Trajectory = c("Cholangiocyte", "Hepatocyte", "Cholangiocyte", "Hepatocyte"),
      Method = c("Permutation", "Permutation", "Steps", "Steps"),
      P_Value = c(
        cholAnswerPermutation\$pValue,
        hepAnswerPermutation\$pValue,
        cholAnswerSteps\$pValue,
        hepAnswerSteps\$pValue
      )
    )
    write.csv(summary_df, "directionality_p_values.csv", row.names = FALSE)
    
    # Save detailed directionality test objects
    saveRDS(cholAnswerPermutation, "cholAnswerPermutation.rds")
    saveRDS(hepAnswerPermutation, "hepAnswerPermutation.rds")
    saveRDS(cholAnswerSteps, "cholAnswerSteps.rds")
    saveRDS(hepAnswerSteps, "hepAnswerSteps.rds")
    
    # 5. Plot path projections using plotPathProjectionCenterAndCircle
    tryCatch({
      plotPathProjectionCenterAndCircle(path=cholPath[,1:3],
          projection=cholAnswerPermutation\$sphericalData\$projections,
          center=cholAnswerPermutation\$sphericalData\$center,
          radius=cholAnswerPermutation\$sphericalData\$distance,
          color=colors[cut(1:10,breaks=100)],
          circleColor = "white",
          pathPointSize = 8,
          projectionPointSize = 8,
          newFigure=TRUE)
      
      # If rgl is available, save a snapshot of the 3D plot
      if (requireNamespace("rgl", quietly = TRUE)) {
        rgl::snapshot3d("chol_path_projection.png")
      }
    }, error = function(e) {
      warning("Could not plot or save 3D path projection: ", e\$message)
    })
    
    # 6. Analyze multiple sampled paths using analyseSingleCellTrajectory
    chol_answers = analyseSingleCellTrajectory(attributes = chol_attributes[,1:3],
        pseudotime = chol_pseudo_time_normalised,
        randomizationParams = c('byPermutation','permuteWithinColumns'),
        statistic = "mean",
        nSamples = 100,
        N = 1)
    
    hep_answers = analyseSingleCellTrajectory(hep_attributes[,1:3],
        hep_pseudo_time_normalised,
        randomizationParams = c('byPermutation','permuteWithinColumns'),
        statistic = "mean",
        nSamples = 100,
        N = 1)
    
    # Save trajectory analysis objects
    saveRDS(chol_answers, "chol_answers.rds")
    saveRDS(hep_answers, "hep_answers.rds")
    
    # 7. Compare trajectories and visualize statistics using visualiseTrajectoryStats
    cholResultDistance = visualiseTrajectoryStats(chol_answers, "distance")
    hepResultDistance = visualiseTrajectoryStats(hep_answers, "distance")
    
    # Save individual trajectory distance plots
    ggsave("chol_result_distance_plot.pdf", plot = cholResultDistance\$plot, width = 6, height = 5)
    ggsave("hep_result_distance_plot.pdf", plot = hepResultDistance\$plot, width = 6, height = 5)
    
    # Compare the two trajectories directly
    distanceComparison = visualiseTrajectoryStats(chol_answers, "distance",
        traj2Data = hep_answers)
    
    final_comparison_plot <- distanceComparison\$plot +
        scale_x_discrete(labels=c("Cholangiocyte","Hepatocyte"))
    
    # Save the final comparison plot
    ggsave("distance_comparison_plot.pdf", plot = final_comparison_plot, width = 6, height = 5)
    
    message("Pipeline completed successfully. Outputs saved to the working directory.")

    writeLines(c(
        '"BIOC_TRAJECTORYGEOMETRY_TRAJECTORY_DIRECTIONALITY_AND_COMPARISON":',
        paste0('    TrajectoryGeometry: ', as.character(packageVersion('TrajectoryGeometry')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trajectory_directionality_and_comparison.csv versions.yml
    """
}

workflow BIOC_TRAJECTORYGEOMETRY_TRAJECTORY_DIRECTIONALITY_AND_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ single_cell_matrix, chol_pseudo_time, hep_pseudo_time ] ]

    main:
    BIOC_TRAJECTORYGEOMETRY_TRAJECTORY_DIRECTIONALITY_AND_COMPARISON(ch_input)

    emit:
    tables   = BIOC_TRAJECTORYGEOMETRY_TRAJECTORY_DIRECTIONALITY_AND_COMPARISON.out.tables
    plots    = BIOC_TRAJECTORYGEOMETRY_TRAJECTORY_DIRECTIONALITY_AND_COMPARISON.out.plots
    objects  = BIOC_TRAJECTORYGEOMETRY_TRAJECTORY_DIRECTIONALITY_AND_COMPARISON.out.objects
    versions = BIOC_TRAJECTORYGEOMETRY_TRAJECTORY_DIRECTIONALITY_AND_COMPARISON.out.versions
}
