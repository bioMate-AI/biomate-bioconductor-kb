#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flowcatchR
// flowcatchR is a set of tools to analyze in vivo microscopy imaging data, focused on tracking flowing
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flowcatchR/inst/doc/flowcatchr_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("flowcatchR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWCATCHR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flowcatchr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flowcatchr:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flowcatchr:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_flowcatchr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flowcatchr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flowcatchr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flowcatchR)
    library(jsonlite)


    # --- Helpmaintainer [] ---
    # Key functions: maintainer, flowcatchR, citation, inspect.Frames, raster
    maintainer("flowcatchR")
    citation("flowcatchR")
    library("flowcatchR")
    data("MesenteriumSubset")
    # printing summary information for the MesenteriumSubset object
    MesenteriumSubset
    inspect.Frames(MesenteriumSubset, nframes=9, display.method="raster")

    # --- Select Red [] ---
    # Key functions: channel.Frames, red, inspect.Frames, raster, preprocess.Frames, disc, crop.Frames
    plateletsMesenterium <- channel.Frames(MesenteriumSubset, mode="red")
    plateletsMesenterium
    inspect.Frames(plateletsMesenterium, nframes=9, display.method="raster")
    preprocessedPlatelets <- preprocess.Frames(plateletsMesenterium,
                                        brush.size=3, brush.shape="disc",
                                        at.offset=0.15, at.wwidth=10, at.wheight=10,
                                        kern.size=3, kern.shape="disc",
                                        ws.tolerance=1, ws.radius=1)
    preprocessedPlatelets
    inspect.Frames(preprocessedPlatelets, nframes=9, display.method="raster")
    croppedFrames <- crop.Frames(plateletsMesenterium,
                         cutLeft=6, cutRight=6,
                         cutUp=3, cutDown=3,
                         testing=FALSE)
    croppedFrames

    # --- Rotate Frames [] ---
    # Key functions: rotate.Frames, select.Frames, normalizeFrames, particles, select.particles
    rotatedFrames <- rotate.Frames(plateletsMesenterium, angle=30)
    rotatedFrames
    subsetFrames <- select.Frames(plateletsMesenterium,
                           framesToKeep=c(1:10,14:20))
    subsetFrames
    normFrames <- normalizeFrames(plateletsMesenterium,normFun = "median")
    platelets <- particles(plateletsMesenterium, preprocessedPlatelets)
    platelets
    selectedPlatelets <- select.particles(platelets, min.area=3)
    selectedPlatelets

    # --- Check Selection [] ---
    # Key functions: add.contours, inspect.Frames, particles, raster, penaltyFunctionGenerator, link.particles, export.particles, read.particles
    paintedPlatelets <- add.contours(raw.frames=MesenteriumSubset,
                                     binary.frames=preprocessedPlatelets,
                                     mode="particles")
    inspect.Frames(paintedPlatelets, nframes=9, display.method="raster")
    defaultPenalty <- penaltyFunctionGenerator()
    print(defaultPenalty)
    linkedPlatelets <- link.particles(platelets,  
                                      L=26, R=3,
                                      epsilon1=0, epsilon2=0,
                                      lambda1=1, lambda2=0,
                                      penaltyFunction=penaltyFunctionGenerator(),
                                      include.area=FALSE)
    linkedPlatelets

    ## ----expo-impo,eval=FALSE-----------------------------------------------------
    #  # export to csv format
    trajPlatelets <- trajectories(linkedPlatelets)
    trajPlatelets
    plot(trajPlatelets, MesenteriumSubset)

    # --- Overview Trajs [] ---
    # Key functions: plot2D.TrajectorySet, add.contours, trajectories, inspect.Frames, raster
    plot2D.TrajectorySet(trajPlatelets, MesenteriumSubset)
    paintedTrajectories <- add.contours(raw.frames=MesenteriumSubset,
                                        binary.frames=preprocessedPlatelets,  
                                        trajectoryset=trajPlatelets,
                                        mode="trajectories")
    paintedTrajectories
    inspect.Frames(paintedTrajectories,nframes=9,display.method="raster")
    traj11 <- add.contours(raw.frames=MesenteriumSubset,
                           binary.frames=preprocessedPlatelets,
                           trajectoryset=trajPlatelets,
                           mode="trajectories",
                           trajIDs=11)
    traj11
    inspect.Frames(traj11, nframes=9, display.method="raster")
    trajPlatelets[[11]]

    # --- Kinem Feats [] ---
    # Key functions: kinematics, density, curvilinearVelocity, cadetblue, steelblue, display, readImage, flowcatchR
    allKinematicFeats.allPlatelets <- kinematics(trajPlatelets,
                                                 trajectoryIDs=NULL, # will select all trajectory IDs 
                                                 acquisitionFrequency=30, # value in milliseconds
                                                 scala=50, # 1 pixel is equivalent to ... micrometer
                                                 feature=NULL) # all kinematic features available
    allKinematicFeats.allPlatelets
    allKinematicFeats.allPlatelets <- kinematics(trajPlatelets, feature="?")
    allVelocities <- kinematics(trajPlatelets, feature="curvilinearVelocity")

    hist(allVelocities, breaks=10, probability=TRUE, col="cadetblue",
         xlab="Curvilinear Velocities Distribution",
         main="Trajectory Analysis: Curvilinear Velocities")
    lines(density(allVelocities, na.rm=TRUE), col="steelblue", lwd=2)
    display(readImage(system.file("extdata/snapExp.jpg",package="flowcatchR")),
            method = "raster")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flowcatchr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flowcatchr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flowcatchr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLOWCATCHR:", paste0("    flowcatchr: ", packageVersion("flowcatchR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowcatchr_results.csv
    touch ${prefix}_flowcatchr_output.rds
    echo "BIOC_FLOWCATCHR:" > versions.yml
    echo "    flowcatchr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLOWCATCHR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FLOWCATCHR(ch_input)

    emit:
    results  = BIOC_FLOWCATCHR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLOWCATCHR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLOWCATCHR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLOWCATCHR.out.versions  // channel: path(versions.yml)
}
