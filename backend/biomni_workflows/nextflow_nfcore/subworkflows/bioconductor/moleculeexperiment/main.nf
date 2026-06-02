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

    # --- Import Spatial Transcriptomics Data [Data Loading] ---
    # Key functions: readXenium, readCosmx, readMerscope
    repo_xenium <- system.file("extdata", package = "MoleculeExperiment")
    repo_xenium <- paste0(repo_xenium, "/xenium_V1_FF_Mouse_Brain")
    me_xenium <- readXenium(
        repo_xenium,
        keepCols = "essential",
        addBoundaries = "cell"
    )
    repo_cosmx <- system.file("extdata", package = "MoleculeExperiment")
    repo_cosmx <- paste0(repo_cosmx, "/nanostring_Lung9_Rep1")
    me_cosmx <- readCosmx(
        repo_cosmx,
        keepCols = "essential",
        addBoundaries = "cell"
    )

    # --- Custom Object Construction [Data Processing] ---
    # Key functions: dataframeToMEList, MoleculeExperiment
    molecules_df <- data.frame(
        sample_id = rep(c("sample1", "sample2"), times = c(30, 20)),
        features = rep(c("gene1", "gene2"), times = c(20, 30)),
        x_coords = runif(50),
        y_coords = runif(50)
    )
    mol_list <- dataframeToMEList(
        molecules_df,
        dfType = "molecules",
        assayName = "detected",
        sampleCol = "sample_id",
        factorCol = "features",
        xCol = "x_coords",
        yCol = "y_coords"
    )
    toy_me <- MoleculeExperiment(molecules = mol_list)

    # --- Segmentation Mask Integration [Boundary Processing] ---
    # Key functions: readSegMask, boundaries<-, extent
    repo_dir <- system.file("extdata", package = "MoleculeExperiment")
    seg_mask <- paste0(repo_dir, "/BIDcell_segmask.tif")
    boundaries(toy_me, "BIDcell_segmentation") <- readSegMask(
        extent(toy_me, assayName = "detected"),
        path = seg_mask,
        assayName = "BIDcell_segmentation",
        sample_id = "sample1",
        background_value = 0
    )

    # --- Feature and Boundary Extraction [Data Extraction] ---
    # Key functions: molecules, boundaries, features, segmentIDs
    mol_flat <- molecules(me_xenium, assayName = "detected", flatten = TRUE)
    bound_flat <- boundaries(me_xenium, assayName = "cell", flatten = TRUE)
    feats <- features(me_xenium, assayName = "detected")[[1]]
    seg_ids <- segmentIDs(me_xenium, "cell")

    # --- Molecule Quantification [Quantification] ---
    # Key functions: countMolecules
    spe <- countMolecules(me_xenium)

    # --- Spatial Visualization [Visualisation] ---
    # Key functions: ggplot_me, geom_polygon_me, geom_point_me
    p <- ggplot_me() +
        geom_polygon_me(
            me_xenium,
            assayName = "cell",
            fill = "grey"
        ) +
        geom_point_me(
            me_xenium,
            byColour = "feature_id",
            selectFeatures = c("Nrn1", "Slc17a7")
        )


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
