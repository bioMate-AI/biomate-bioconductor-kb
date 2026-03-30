#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: illuminaio
// Tools for parsing Illumina's microarray output files, including IDAT.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/illuminaio/inst/doc/illuminaio.R
// Upstream  : IlluminaDataTestFiles
// Downstream: normalize450K, RnBeads, wateRmelon, EGSEA123
//
// Install: BiocManager::install("illuminaio")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ILLUMINAIO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-illuminaio"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-illuminaio:0.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-illuminaio:0.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_illuminaio_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_illuminaio_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_illuminaio_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(illuminaio)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: readIDAT
    library(illuminaio)
    library(IlluminaDataTestFiles)
    idatFile <- system.file("extdata", "idat", "4343238080_A_Grn.idat",
                            package = "IlluminaDataTestFiles")
    idat <- readIDAT(idatFile)
    # --- Readgenotyping [] ---
    # Key functions: readIDAT
    genotypeIdatFile <- system.file("extdata", "idat", "5723646052_R02C02_Grn.idat",
                            package = "IlluminaDataTestFiles")
    genotypeIdat <- readIDAT(genotypeIdatFile)
    names(genotypeIdat)
    # --- Importgenomestudio [] ---
    # Key functions: delim
    gsFile <- system.file("extdata", "gs", "4343238080_A_ProbeSummary.txt.gz",
                          package = "IlluminaDataTestFiles")
    gStudio <- read.delim(gsFile, sep = "\t", header = TRUE)
    idatData <- idatData[which(idatData[,"CodesBinData"] %in% gStudio[,"ProbeID"]),]
    gStudio <- gStudio[match(idatData[,"CodesBinData"], gStudio[,"ProbeID"]),]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_illuminaio_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_illuminaio_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_illuminaio_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ILLUMINAIO:", paste0("    illuminaio: ", packageVersion("illuminaio"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_illuminaio_results.csv
    touch ${prefix}_illuminaio_output.rds
    echo "BIOC_ILLUMINAIO:" > versions.yml
    echo "    illuminaio: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ILLUMINAIO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ILLUMINAIO(ch_input)

    emit:
    results  = BIOC_ILLUMINAIO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ILLUMINAIO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ILLUMINAIO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ILLUMINAIO.out.versions  // channel: path(versions.yml)
}
