#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Voyager
// SpatialFeatureExperiment (SFE) is a new S4 class for working with spatial single-cell genomics data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Voyager/inst/doc/overview.R
// Upstream  : SFEData, SpatialExperiment, SpatialFeatureExperiment, ggplot2, pheatmap
// Downstream: none
//
// Install: BiocManager::install("Voyager")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VOYAGER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-voyager"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-voyager:1.8.1--r44_0' :
        'quay.io/biocontainers/bioconductor-voyager:1.8.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_voyager_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_voyager_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_voyager_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ElbowPlot)
    library(McKellarMuscleData)
    library(jsonlite)

    # --- Mckellarmuscledata [] ---
    # Key functions: McKellarMuscleData
    ---------------------------------------------------------------------
    sfe <- McKellarMuscleData()
    # --- Addimg [] ---
    # Key functions: addImg
    ---------------------------------------------------------------------
    sfe <- addImg(sfe, imageSource = "tissue_lowres_5a.jpeg", sample_id = "Vis5A",
                  image_id = "lowres", scale_fct = 1024/22208)
    # --- Mirrorimg [] ---
    # Key functions: mirrorImg
    ---------------------------------------------------------------------
    sfe <- mirrorImg(sfe, sample_id = "Vis5A", image_id = "lowres")
    # --- Coldata [] ---
    # Key functions: colData, logNormCounts
    ---------------------------------------------------------------------
    # Only use spots in tissue here
    sfe <- sfe[,colData(sfe)$in_tissue]
    sfe <- logNormCounts(sfe)
    sfe
    # --- Colgraph [] ---
    # Key functions: colGraph, findVisiumGraph
    ---------------------------------------------------------------------
    colGraph(sfe, "visium") <- findVisiumGraph(sfe)
    # --- Rununivariate [] ---
    # Key functions: runUnivariate, rowData
    ---------------------------------------------------------------------
    sfe <- runUnivariate(sfe, type = "moran", features = features_use,
                         colGraphName = "visium", swap_rownames = "symbol")
    # Look at the results
    rowData(sfe)[rowData(sfe)$symbol %in% features_use,]
    # --- Rununivariate [] ---
    # Key functions: runUnivariate, localResults
    ---------------------------------------------------------------------
    sfe <- runUnivariate(sfe, type = "localG", features = features_use,
                         colGraphName = "visium", include_self = TRUE,
                         swap_rownames = "symbol")
    # Look at the results
    # --- Modelgenevar [] ---
    # Key functions: modelGeneVar, getTopHVGs
    ---------------------------------------------------------------------
    gs <- modelGeneVar(sfe)
    hvgs <- getTopHVGs(gs, fdr.threshold = 0.01)
    # --- Calculatebivariate [] ---
    # Key functions: calculateBivariate
    ---------------------------------------------------------------------
    res <- calculateBivariate(sfe, "lee", hvgs)
    # --- Gettophvgs [] ---
    # Key functions: getTopHVGs, runMultivariate
    ---------------------------------------------------------------------
    hvgs2 <- getTopHVGs(gs, n = 1000)
    sfe <- runMultivariate(sfe, "multispati", colGraphName = "visium", subset_row = hvgs2,
                           nfposi = 10, nfnega = 10)
    # --- Plotspatialfeature [] ---
    # Key functions: plotSpatialFeature
    ---------------------------------------------------------------------
    plotSpatialFeature(sfe, c("nCounts", "Myh1"), colGeometryName = "spotPoly",
                       annotGeometryName = "myofiber_simplified",
                       aes_use = "color", linewidth = 0.5, fill = NA,
                       annot_aes = list(fill = "area"), swap_rownames = "symbol")
    # --- Plotlocalresult [] ---
    # Key functions: plotLocalResult
    ---------------------------------------------------------------------
    plotLocalResult(sfe, "localG", features = features_use,
                    colGeometryName = "spotPoly", divergent = TRUE,
                    diverge_center = 0, swap_rownames = "symbol",
                    image_id = "lowres", maxcell = 5e+4)
    # --- Elbowplot [] ---
    # Key functions: ElbowPlot, theme_bw
    ---------------------------------------------------------------------
    ElbowPlot(sfe, ndims = 10, nfnega = 10, reduction = "multispati") + theme_bw()
    # --- Spatialreduceddim [] ---
    # Key functions: spatialReducedDim
    ---------------------------------------------------------------------
    spatialReducedDim(sfe, "multispati", ncomponents = 2, image_id = "lowres",
                      maxcell = 5e+4, divergent = TRUE, diverge_center = 0)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_voyager_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_voyager_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_voyager_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VOYAGER:", paste0("    voyager: ", packageVersion("Voyager"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_voyager_results.csv
    touch ${prefix}_voyager_output.rds
    echo "BIOC_VOYAGER:" > versions.yml
    echo "    voyager: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VOYAGER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VOYAGER(ch_input)

    emit:
    results  = BIOC_VOYAGER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VOYAGER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VOYAGER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VOYAGER.out.versions  // channel: path(versions.yml)
}
