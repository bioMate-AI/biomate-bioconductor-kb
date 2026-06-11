#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowcatchr — cell_tracking_and_kinematics
// Track flowing blood cells in time-lapse microscopy images and analyze their kinematic properties.
// Input: image.files
// Container: quay.io/biocontainers/bioconductor-flowcatchr:1.44.0--r45hdfd78af_0
// R packages: flowcatchR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWCATCHR_CELL_TRACKING_AND_KINEMATICS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-flowcatchr:1.44.0--r45hdfd78af_0"

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
    .bm_deps <- c("flowcatchR")
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
    library("flowcatchR")
    
    # Define and validate input path
    input_path <- "image.files"
    if (!file.exists(input_path)) {
      stop("Required input 'image.files' (folder or file containing paths) not found in the working directory.")
    }
    
    # Load raw images into a Frames object
    if (dir.exists(input_path)) {
      files <- list.files(input_path, pattern = "\\\\.(tiff|tif|png|jpg|jpeg)\$", ignore.case = TRUE, full.names = TRUE)
      if (length(files) == 0) {
        stop("No TIFF/JPG/PNG images found in 'image.files' directory.")
      }
      MesenteriumSubset <- read.Frames(image.files = input_path, nframes = length(files))
    } else {
      # If it's a file, assume it contains a list of image paths (one per line)
      file_paths <- readLines(input_path)
      file_paths <- file_paths[file_paths != ""]
      if (length(file_paths) == 0) {
        stop("The 'image.files' file is empty.")
      }
      MesenteriumSubset <- read.Frames(image.files = file_paths, nframes = length(file_paths))
    }
    
    # Extract the channel of interest (red for platelets)
    plateletsMesenterium <- channel.Frames(MesenteriumSubset, mode="red")
    
    # Preprocess and segment the frames
    preprocessedPlatelets <- preprocess.Frames(plateletsMesenterium,
                                               brush.size=3, brush.shape="disc",
                                               at.offset=0.15, at.wwidth=10, at.wheight=10,
                                               kern.size=3, kern.shape="disc",
                                               ws.tolerance=1, ws.radius=1)
    
    # Detect particles and extract features
    platelets <- particles(plateletsMesenterium, preprocessedPlatelets)
    
    # Filter out noise particles based on area
    selectedPlatelets <- select.particles(platelets, min.area=3)
    
    # Link particles across frames to form trajectories
    linkedPlatelets <- link.particles(platelets,  
                                      L=26, R=3,
                                      epsilon1=0, epsilon2=0,
                                      lambda1=1, lambda2=0,
                                      penaltyFunction=penaltyFunctionGenerator(),
                                      include.area=FALSE)
    
    # Extract trajectories into a TrajectorySet
    trajPlatelets <- trajectories(linkedPlatelets)
    
    # Calculate kinematic features
    allKinematicFeats.allPlatelets <- kinematics(trajPlatelets,
                                                 trajectoryIDs=NULL, # will select all trajectory IDs 
                                                 acquisitionFrequency=30, # value in milliseconds
                                                 scala=50, # 1 pixel is equivalent to ... micrometer
                                                 feature=NULL) # all kinematic features available
    
    # Create output directory
    output_dir <- "pipeline_output"
    dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
    
    # Save R objects
    saveRDS(selectedPlatelets, file = file.path(output_dir, "selected_platelets.rds"))
    saveRDS(trajPlatelets, file = file.path(output_dir, "trajectory_platelets.rds"))
    saveRDS(allKinematicFeats.allPlatelets, file = file.path(output_dir, "kinematic_features.rds"))
    
    # Export particles using package function
    export.particles(selectedPlatelets, dir = file.path(output_dir, "exported_particles"))
    
    # Generate and save diagnostic plots
    pdf(file.path(output_dir, "trajectories_2D_flat.pdf"))
    plot2D.TrajectorySet(trajPlatelets, MesenteriumSubset)
    dev.off()
    
    pdf(file.path(output_dir, "curvilinear_velocities_histogram.pdf"))
    allVelocities <- kinematics(trajPlatelets, feature="curvilinearVelocity")
    hist(allVelocities, breaks=10, probability=TRUE, col="cadetblue",
         xlab="Curvilinear Velocities Distribution",
         main="Trajectory Analysis: Curvilinear Velocities")
    lines(density(allVelocities, na.rm=TRUE), col="steelblue", lwd=2)
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to 'pipeline_output/'.\n")

    writeLines(c(
        '"BIOC_FLOWCATCHR_CELL_TRACKING_AND_KINEMATICS":',
        paste0('        flowcatchr: ', as.character(packageVersion("flowcatchr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cell_tracking_and_kinematics.csv versions.yml
    """
}

workflow BIOC_FLOWCATCHR_CELL_TRACKING_AND_KINEMATICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ image.files ] ]

    main:
    BIOC_FLOWCATCHR_CELL_TRACKING_AND_KINEMATICS(ch_input)

    emit:
    tables   = BIOC_FLOWCATCHR_CELL_TRACKING_AND_KINEMATICS.out.tables
    plots    = BIOC_FLOWCATCHR_CELL_TRACKING_AND_KINEMATICS.out.plots
    objects  = BIOC_FLOWCATCHR_CELL_TRACKING_AND_KINEMATICS.out.objects
    versions = BIOC_FLOWCATCHR_CELL_TRACKING_AND_KINEMATICS.out.versions
}
