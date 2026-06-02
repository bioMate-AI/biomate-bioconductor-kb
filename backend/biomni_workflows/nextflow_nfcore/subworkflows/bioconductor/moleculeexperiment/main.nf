#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MoleculeExperiment
// MoleculeExperiment contains functions to create and work with objects from the new MoleculeExperimen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MoleculeExperiment/inst/doc/MoleculeExperiment.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("MoleculeExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOLECULEEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-moleculeexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-moleculeexperiment:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-moleculeexperiment:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_moleculeexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_moleculeexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_moleculeexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MoleculeExperiment)
    library(jsonlite)

    # --- Ggplot Me [] ---
    # Key functions: ggplot_me, geom_polygon_me, geom_point_me, coord_cartesian
    ---------------------------------------------------------------------
    ggplot_me() +
      geom_polygon_me(me, assayName = "cell", fill = "grey") +
      geom_point_me(me) +
      # zoom in to selected patch area
    # --- Countmolecules [] ---
    # Key functions: countMolecules
    ---------------------------------------------------------------------
    # transform ME to SPE object
    spe <- countMolecules(me)
    spe
    # --- Frame [] ---
    # Key functions: frame, runif
    ---------------------------------------------------------------------
    # --- Frame [] ---
    # Key functions: frame
    ---------------------------------------------------------------------
    # --- Dataframetomelist [] ---
    # Key functions: dataframeToMEList
    ---------------------------------------------------------------------
    # --- Moleculeexperiment [] ---
    # Key functions: MoleculeExperiment
    ---------------------------------------------------------------------
    toyME <- MoleculeExperiment(
      molecules = moleculesMEList,
      boundaries = boundariesMEList
    )
    # --- Ggplot Me [] ---
    # Key functions: ggplot_me, geom_polygon_me, geom_point_me, theme_classic
    ---------------------------------------------------------------------
    ggplot_me() +
      geom_polygon_me(toyME, assayName = "cell", byFill = "segment_id", colour = "black", alpha = 0.3) +
      geom_polygon_me(toyME, assayName = "BIDcell_segmentation", fill = NA, colour = "red" ) +
      geom_point_me(toyME, assayName = "detected", byColour = "feature_id", size = 1) +
    # --- Showmolecules [] ---
    # Key functions: showMolecules
    ---------------------------------------------------------------------
    showMolecules(me)
    # --- Showboundaries [] ---
    # Key functions: showBoundaries
    ---------------------------------------------------------------------
    showBoundaries(me)
    # --- Molecules [] ---
    # Key functions: molecules
    ---------------------------------------------------------------------
    molecules(me, assayName = "detected", flatten = TRUE)
    # --- Boundaries [] ---
    # Key functions: boundaries
    ---------------------------------------------------------------------
    boundaries(me, assayName = "cell", flatten = TRUE)
    # --- Features [] ---
    # Key functions: features
    ---------------------------------------------------------------------
    # get features in sample 1
    features(me, assayName = "detected")[[1]]
    # --- Segmentids [] ---
    # Key functions: segmentIDs
    ---------------------------------------------------------------------
    segmentIDs(me, "cell")
    # --- Ggplot Me [] ---
    # Key functions: ggplot_me, geom_polygon_me, geom_point_me, coord_cartesian
    ---------------------------------------------------------------------
    ggplot_me() +
      # add cell segments and colour by cell id
      geom_polygon_me(me, byFill = "segment_id", colour = "black", alpha = 0.1) +
      # add molecule points and colour by feature name
    # --- Extent [] ---
    # Key functions: extent, subset_by_extent, ggplot_me, geom_polygon_me, geom_point_me, ggtitle
    ---------------------------------------------------------------------
    new_extent = extent(meMerscope, "detected") - c(0, 100, 0, 0)
    # new_extent = c(xmin = 924, xmax = 950, ymin = 26290, ymax = 26330)
    new_extent
    me_sub = subset_by_extent(meMerscope, new_extent)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_moleculeexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_moleculeexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_moleculeexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOLECULEEXPERIMENT:", paste0("    moleculeexperiment: ", packageVersion("MoleculeExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_moleculeexperiment_results.csv
    touch ${prefix}_moleculeexperiment_output.rds
    echo "BIOC_MOLECULEEXPERIMENT:" > versions.yml
    echo "    moleculeexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOLECULEEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOLECULEEXPERIMENT(ch_input)

    emit:
    results  = BIOC_MOLECULEEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOLECULEEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOLECULEEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOLECULEEXPERIMENT.out.versions  // channel: path(versions.yml)
}
