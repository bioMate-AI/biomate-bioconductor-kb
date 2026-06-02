#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Cardinal
// Implements statistical & computational tools for analyzing mass spectrometry imaging datasets, inclu
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Cardinal/inst/doc/Cardinal3-guide.R
// Upstream  : CardinalWorkflows
// Downstream: CardinalWorkflows
//
// Install: BiocManager::install("Cardinal")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CARDINAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cardinal"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cardinal:3.8.3--r44_0' :
        'quay.io/biocontainers/bioconductor-cardinal:3.8.3--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_cardinal_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cardinal_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cardinal_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Cardinal)
    library(MassDataFrame)
    library(jsonlite)

    # --- Simulation of MS Imaging Data [] ---
    # Key functions: simulateSpectra, MassDataFrame, PositionDataFrame, MSImagingExperiment, simulateImage
    s <- simulateSpectra(n=9, npeaks=10, from=500, to=600)
    coord_grid <- expand.grid(x=1:3, y=1:3)
    run_fac <- factor(rep("run0", nrow(coord_grid)))
    fdata <- MassDataFrame(mz=s$mz)
    pdata <- PositionDataFrame(run=run_fac, coord=coord_grid)
    mse_sim <- MSImagingExperiment(
        spectraData=s$intensity,
        featureData=fdata,
        pixelData=pdata
    )
    mse_full <- simulateImage(preset=6, dim=c(32,32), baseline=0.5)


    # --- Subsetting and Feature Selection [] ---
    # Key functions: features, pixels, subsetFeatures, subsetPixels, convertMSImagingExperiment2Arrays
    mse_full <- simulateImage(preset=6, dim=c(32,32), baseline=0.5)
    fid <- features(mse_full, 1002 < mz, mz < 1004)
    pid <- pixels(mse_full, x <= 3, y <= 3, run == "runA1")
    mse_sub <- mse_full[fid, pid]
    mse_sub2 <- subsetFeatures(mse_full, 1002 < mz, mz < 1004)
    mse_sub3 <- subsetPixels(mse_full, x <= 3, y <= 3)
    msa_sub <- convertMSImagingExperiment2Arrays(mse_full)


    # --- Visualization and Image Generation [] ---
    # Key functions: plot, image, convertMSImagingExperiment2Arrays
    mse_full <- simulateImage(preset=6, dim=c(32,32), baseline=0.5)
    msa_full <- convertMSImagingExperiment2Arrays(mse_full)
    plot(msa_full, i=c(496, 1520), superpose=TRUE)
    image(mse_full, mz=1003.3, tolerance=0.5, units="mz")
    image(mse_full, mz=1003.3, smooth="gaussian", enhance="histogram")
    image(mse_full, mz=c(1003.3, 1663.6), superpose=TRUE, scale=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cardinal_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cardinal_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cardinal_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CARDINAL:", paste0("    cardinal: ", packageVersion("Cardinal"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cardinal_results.csv
    touch ${prefix}_cardinal_output.rds
    echo "BIOC_CARDINAL:" > versions.yml
    echo "    cardinal: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CARDINAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_CARDINAL(ch_input)

    emit:
    results  = BIOC_CARDINAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CARDINAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CARDINAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CARDINAL.out.versions  // channel: path(versions.yml)
}
