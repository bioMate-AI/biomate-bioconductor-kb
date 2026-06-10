#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TrajectoryGeometry — path_progression_and_randomization
// Generate randomized paths and check for consistent progression along a trajectory, including handling initial oscillations.
// Input: straight_path, crooked_path, oscillation
// Container: quay.io/biocontainers/bioconductor-trajectorygeometry:1.18.0--r45h575d39b_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TrajectoryGeometry
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate randomized paths using generateRandomPaths
//  * 2. [Core Analysis] Check for progression in a direction using pathProgression
//  * 3. [Core Analysis] Handle initial oscillations using pathProgression to find stable starting points

nextflow.enable.dsl = 2

process BIOC_TRAJECTORYGEOMETRY_PATH_PROGRESSION_AND_RANDOMIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        
        # Helper function to read input files robustly (supporting RDS and CSV)
        read_input <- function(name) {
          if (file.exists(paste0(name, ".rds"))) {
            return(as.matrix(readRDS(paste0(name, ".rds"))))
          } else if (file.exists(paste0(name, ".csv"))) {
            return(as.matrix(read.csv(paste0(name, ".csv"), row.names = 1)))
          } else if (file.exists(name)) {
            # Try reading as RDS first, then CSV
            res <- tryCatch({
              as.matrix(readRDS(name))
            }, error = function(e) {
              as.matrix(read.csv(name, row.names = 1))
            })
            return(res)
          } else {
            stop(paste("Required input file not found:", name))
          }
        }
        
        # Read user input files from the working directory
        straight_path <- read_input("straight_path")
        crooked_path  <- read_input("crooked_path")
        oscillation   <- read_input("oscillation")
        
        # Compute the center direction vectors using testPathForDirectionality
        # as required for the pathProgression steps in the documented workflow.
        straight_ans <- testPathForDirectionality(
          straight_path,
          randomizationParams = c('bySteps', 'preserveLengths'),
          N = 10
        )
        straight_path_center <- straight_ans\$sphericalData\$center
        
        crooked_ans <- testPathForDirectionality(
          crooked_path,
          randomizationParams = c('bySteps', 'preserveLengths'),
          N = 10
        )
        crooked_path_center <- crooked_ans\$sphericalData\$center
        
        # --- Documented Stage 1: Generate randomized paths ---
        randomizationParams = c('bySteps','preserveLengths')
        Y = generateRandomPaths(path=straight_path,
                                randomizationParams=randomizationParams,
                                N=10)
        saveRDS(Y, "random_paths_bySteps.rds")
        
        randomizationParams = c('bySteps','preserveLengths','nonNegative')
        Y = generateRandomPaths(path=straight_path,
                                randomizationParams=randomizationParams,
                                N=10)
        saveRDS(Y, "random_paths_nonNegative.rds")
        
        # --- Documented Stage 2: Check for progression in a direction ---
        progress = pathProgression(straight_path,direction=straight_path_center)
        write.csv(as.data.frame(progress), "progress_straight.csv", row.names = FALSE)
        
        progress = pathProgression(crooked_path,from=6,direction=crooked_path_center)
        write.csv(as.data.frame(progress), "progress_crooked.csv", row.names = FALSE)
        
        # --- Documented Stage 3: Handle initial oscillations ---
        direction = oscillation[nrow(oscillation),] - oscillation[1,]
        progress = pathProgression(oscillation,direction=direction)
        write.csv(as.data.frame(progress), "progress_oscillation.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_TRAJECTORYGEOMETRY_PATH_PROGRESSION_AND_RANDOMIZATION":',
        paste0('    TrajectoryGeometry: ', as.character(packageVersion('TrajectoryGeometry')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_path_progression_and_randomization.csv versions.yml
    """
}

workflow BIOC_TRAJECTORYGEOMETRY_PATH_PROGRESSION_AND_RANDOMIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ straight_path, crooked_path, oscillation ] ]

    main:
    BIOC_TRAJECTORYGEOMETRY_PATH_PROGRESSION_AND_RANDOMIZATION(ch_input)

    emit:
    tables   = BIOC_TRAJECTORYGEOMETRY_PATH_PROGRESSION_AND_RANDOMIZATION.out.tables
    plots    = BIOC_TRAJECTORYGEOMETRY_PATH_PROGRESSION_AND_RANDOMIZATION.out.plots
    objects  = BIOC_TRAJECTORYGEOMETRY_PATH_PROGRESSION_AND_RANDOMIZATION.out.objects
    versions = BIOC_TRAJECTORYGEOMETRY_PATH_PROGRESSION_AND_RANDOMIZATION.out.versions
}
