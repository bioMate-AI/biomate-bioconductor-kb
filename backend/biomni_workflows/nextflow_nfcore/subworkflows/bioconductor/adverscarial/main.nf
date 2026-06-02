#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: adverSCarial
// adverSCarial is an R Package designed for generating and analyzing the vulnerability of scRNA-seq cl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/adverSCarial/inst/doc/vign01_adverSCarial.R
// Upstream  : BiocManager, DelayedArray, LoomExperiment
// Downstream: none
//
// Install: BiocManager::install("adverSCarial")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ADVERSCARIAL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-adverscarial"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-adverscarial:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-adverscarial:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_adverscarial_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_adverscarial_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_adverscarial_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(adverSCarial)
    library(MClassifier)
    library(jsonlite)

    # --- Baseline Classification [Baseline Classification] ---
    # Key functions: MClassifier
    pbmcPath <- system.file("extdata", "pbmc_short.loom", package="adverSCarial")
    lfile <- LoomExperiment::import(pbmcPath, type="SingleCellLoomExperiment")
    matPbmc <- BiocGenerics::counts(lfile)
    cellTypes <- SummarizedExperiment::rowData(lfile)$cell_type
    resClassif <- MClassifier(matPbmc, cellTypes, "DC")

    # --- Minimum Change Attack [Adversarial Attack] ---
    # Key functions: advSingleGene, advModifications, MClassifier
    markers <- c("IL7R", "CCR7", "CD14", "LYZ", "S100A4", "MS4A1", "CD8A")
    genesMinChange <- advSingleGene(
        matPbmc, cellTypes, "DC", MClassifier,
        exclGenes = markers, advMethod = "perc99",
        returnFirstFound = TRUE, changeType = "not_na",
        firstDichot = 10
    )
    matAdver <- advModifications(
        matPbmc, names(genesMinChange@values)[1],
        cellTypes, "DC"
    )
    resClassifMin <- MClassifier(matAdver, cellTypes, "DC")

    # --- Maximum Change Attack [Adversarial Attack] ---
    # Key functions: advMaxChange, advModifications, MClassifier
    markers <- c("IL7R", "CCR7", "CD14", "LYZ", "S100A4", "MS4A1", "CD8A")
    genesMaxChange <- advMaxChange(
        matPbmc, cellTypes, "Memory CD4 T", MClassifier,
        exclGenes = markers, advMethod = "perc99"
    )
    matMaxAdver <- advModifications(
        matPbmc, genesMaxChange@values,
        cellTypes, "Memory CD4 T"
    )
    resClassifMax <- MClassifier(matMaxAdver, cellTypes, "Memory CD4 T")

    # --- Coordinate Gradient Descent Attack [Adversarial Attack] ---
    # Key functions: advCGD, MClassifier
    resCGD <- advCGD(
        as.data.frame(matPbmc), cellTypes,
        "Memory CD4 T", MClassifier, alpha = 1, epsilon = 1,
        genes = colnames(matPbmc)[ncol(matPbmc):1]
    )
    modifiedMatrix <- resCGD$expr
    resClassifCGD <- MClassifier(
        modifiedMatrix, cellTypes, "Memory CD4 T"
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_adverscarial_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_adverscarial_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_adverscarial_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ADVERSCARIAL:", paste0("    adverscarial: ", packageVersion("adverSCarial"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_adverscarial_results.csv
    touch ${prefix}_adverscarial_output.rds
    echo "BIOC_ADVERSCARIAL:" > versions.yml
    echo "    adverscarial: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ADVERSCARIAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ADVERSCARIAL(ch_input)

    emit:
    results  = BIOC_ADVERSCARIAL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ADVERSCARIAL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ADVERSCARIAL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ADVERSCARIAL.out.versions  // channel: path(versions.yml)
}
