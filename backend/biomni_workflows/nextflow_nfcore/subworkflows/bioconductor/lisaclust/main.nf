#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: lisaClust
// lisaClust provides a series of functions to identify and visualise regions of tissue where spatial a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/lisaClust/inst/doc/lisaClust.R
// Upstream  : BiocStyle, SingleCellExperiment, SpatialDatasets, ggplot2, spicyR
// Downstream: none
//
// Install: BiocManager::install("lisaClust")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LISACLUST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-lisaclust"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-lisaclust:1.14.4--r44_0' :
        'quay.io/biocontainers/bioconductor-lisaclust:1.14.4--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_lisaclust_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_lisaclust_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_lisaclust_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SingleCellExperiment)
    library(jsonlite)

    # --- Singlecellexperiment [] ---
    # Key functions: SingleCellExperiment
    ---------------------------------------------------------------------
    SCE <- SingleCellExperiment(colData = cells)
    SCE
    # --- Lisaclust [] ---
    # Key functions: lisaClust, colData
    ---------------------------------------------------------------------
    SCE <- lisaClust(SCE, k = 2)
    colData(SCE) |> head()
    # --- Hatchingplot [] ---
    # Key functions: hatchingPlot
    ---------------------------------------------------------------------
    hatchingPlot(SCE, useImages = c("s1", "s2"))
    # --- Lisa [] ---
    # Key functions: lisa
    ---------------------------------------------------------------------
    lisaCurves <- lisa(SCE, Rs = c(20, 50, 100))
    head(lisaCurves)
    # --- Kmeans [] ---
    # Key functions: kmeans, colData
    ---------------------------------------------------------------------
    # Custom clustering algorithm
    kM <- kmeans(lisaCurves, 2)
    # Storing clusters into colData
    colData(SCE)$custom_region <- paste("region", kM$cluster, sep = "_")
    # --- Spe Keren 2018 [] ---
    # Key functions: spe_Keren_2018
    ---------------------------------------------------------------------
    kerenSPE <- SpatialDatasets::spe_Keren_2018()
    # --- Coldata [] ---
    # Key functions: colData
    ---------------------------------------------------------------------
    colData(kerenSPE)[, c("imageID", "region")] |>
      head(20)
    # --- Regionmap [] ---
    # Key functions: regionMap
    ---------------------------------------------------------------------
    regionMap(kerenSPE,
      type = "bubble"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_lisaclust_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_lisaclust_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_lisaclust_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LISACLUST:", paste0("    lisaclust: ", packageVersion("lisaClust"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lisaclust_results.csv
    touch ${prefix}_lisaclust_output.rds
    echo "BIOC_LISACLUST:" > versions.yml
    echo "    lisaclust: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LISACLUST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LISACLUST(ch_input)

    emit:
    results  = BIOC_LISACLUST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LISACLUST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LISACLUST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LISACLUST.out.versions  // channel: path(versions.yml)
}
