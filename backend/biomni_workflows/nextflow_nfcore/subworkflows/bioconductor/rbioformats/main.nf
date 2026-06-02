#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RBioFormats
// An R package which interfaces the OME Bio-Formats Java library to allow reading of proprietary micro
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RBioFormats/inst/doc/RBioFormats.R
// Upstream  : EBImage, xml2
// Downstream: none
//
// Install: BiocManager::install("RBioFormats")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RBIOFORMATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rbioformats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rbioformats:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rbioformats:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rbioformats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rbioformats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rbioformats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RBioFormats)
    library(jsonlite)

    # --- Metadata Extraction [] ---
    # Key functions: read.metadata, metadata, coreMetadata
    img_file <- system.file("images", "nuclei.tif", package = "EBImage")
    meta_direct <- read.metadata(img_file)
    img <- read.image(img_file)
    meta_from_img <- metadata(img)
    core_meta <- coreMetadata(img)


    # --- OME-XML Metadata Parsing [] ---
    # Key functions: read.omexml
    img_file <- system.file("images", "nuclei.tif", package = "EBImage")
    xml_data <- read.omexml(img_file)


    # --- Mock Image Generation and Validation [] ---
    # Key functions: mockFile, read.image
    mock_path <- mockFile(
        sizeX = 256,
        sizeY = 256,
        pixelType = "uint16"
    )
    mock_img <- read.image(mock_path)
    mock_dims <- dim(mock_img)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rbioformats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rbioformats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rbioformats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RBIOFORMATS:", paste0("    rbioformats: ", packageVersion("RBioFormats"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rbioformats_results.csv
    touch ${prefix}_rbioformats_output.rds
    echo "BIOC_RBIOFORMATS:" > versions.yml
    echo "    rbioformats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RBIOFORMATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RBIOFORMATS(ch_input)

    emit:
    results  = BIOC_RBIOFORMATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RBIOFORMATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RBIOFORMATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RBIOFORMATS.out.versions  // channel: path(versions.yml)
}
