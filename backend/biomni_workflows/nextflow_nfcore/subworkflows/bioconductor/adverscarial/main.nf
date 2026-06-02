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
    library(MClassifier)
    library(jsonlite)

    # --- min change attack [] ---
    # Key functions: import
    pbmcPath <- system.file("extdata", "pbmc_short.loom", package="adverSCarial")
    lfile <- import(pbmcPath, type="SingleCellLoomExperiment")
    # --- extract matrix data [] ---
    # Key functions: counts
    matPbmc <- counts(lfile)
    # --- row Data [] ---
    # Key functions: rowData
    cellTypes <- rowData(lfile)$cell_type
    # --- M Classifier [] ---
    # Key functions: MClassifier
    for ( cell_type in unique(cellTypes)){
    resClassif <- MClassifier(matPbmc, cellTypes, cell_type)
    print(paste0("Expected: ", cell_type, ", predicted: ", resClassif[1]))
    # --- search min change attack [] ---
    # Key functions: advSingleGene
    genesMinChange <- advSingleGene(matPbmc, cellTypes, "DC",
    # --- run min change attack [] ---
    # Key functions: advModifications
    matAdver <- advModifications(matPbmc, names(genesMinChange@values)[1], cellTypes, "DC")
    # --- verify the min change attack [] ---
    # Key functions: MClassifier
    resClassif <- MClassifier(matAdver, cellTypes, "DC")
    # --- search max change attack [] ---
    # Key functions: advMaxChange
    genesMaxChange <- advMaxChange(matPbmc, cellTypes, "Memory CD4 T", MClassifier,
    # --- run max change attack [] ---
    # Key functions: advModifications
    matMaxAdver <- advModifications(matPbmc, genesMaxChange@values, cellTypes, "Memory CD4 T")
    # --- verify max change attack [] ---
    # Key functions: MClassifier
    resClassif <- MClassifier(matMaxAdver, cellTypes, "Memory CD4 T")
    # --- adv C G D [] ---
    # Key functions: advCGD
    resCGD <- advCGD(as.data.frame(matPbmc), cellTypes,
    genes=colnames(matPbmc)[ncol(matPbmc):1])
    # --- M Classifier [] ---
    # Key functions: MClassifier
    MClassifier(modifiedMatrix, cellTypes, "Memory CD4 T")$prediction

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
