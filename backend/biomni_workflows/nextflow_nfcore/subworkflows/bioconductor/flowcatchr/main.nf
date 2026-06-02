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

    # --- Particle Identification [] ---
    # Key functions: particles, select.particles, add.contours
    platelets <- particles(plateletsMesenterium, preprocessedPlatelets)
    selectedPlatelets <- select.particles(platelets, min.area = 3)
    paintedPlatelets <- add.contours(
        raw.frames = MesenteriumSubset,
        binary.frames = preprocessedPlatelets,
        mode = "particles"
    )


    # --- Particle Tracking [] ---
    # Key functions: link.particles, trajectories, penaltyFunctionGenerator
    linkedPlatelets <- link.particles(
        platelets,
        L = 26, R = 3,
        epsilon1 = 0, epsilon2 = 0,
        lambda1 = 1, lambda2 = 0,
        penaltyFunction = penaltyFunctionGenerator(),
        include.area = FALSE
    )
    trajPlatelets <- trajectories(linkedPlatelets)


    # --- Kinematic Analysis [] ---
    # Key functions: kinematics
    allKinematicFeats <- kinematics(
        trajPlatelets,
        trajectoryIDs = NULL,
        acquisitionFrequency = 30,
        scala = 50,
        feature = NULL
    )
    allVelocities <- kinematics(trajPlatelets, feature = "curvilinearVelocity")

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
