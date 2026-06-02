#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Guitar
// The package is designed for visualization of RNA-related genomic features with respect to the landma
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Guitar/inst/doc/Guitar-Overview.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Guitar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GUITAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-guitar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-guitar:2.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-guitar:2.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_guitar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_guitar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_guitar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GuitarPlot)
    library(jsonlite)

    # --- label=quick plot [] ---
    # Key functions: GuitarPlot
    count <- GuitarPlot(txGenomeVer = "mm10",
    # --- Guitar coordiantes [] ---
    # Key functions: loadDb, makeGuitarTxdb, getTxdb
    txdb_file <- system.file("extdata", "mm10_toy.sqlite",
    txdb <- loadDb(txdb_file)
    guitarTxdb <- makeGuitarTxdb(txdb = txdb, txPrimaryOnly = FALSE)
    # --- label=example [] ---
    # Key functions: GuitarPlot
    GuitarPlot(txTxdb =  txdb,
    # --- label=parameter 1 [] ---
    # Key functions: GuitarPlot
    GuitarPlot(txTxdb = txdb,
    # --- label=parameter 2 [] ---
    # Key functions: GuitarPlot
    GuitarPlot(txTxdb = txdb,
    # --- label=mm10 example [] ---
    # Key functions: loadDb, GuitarPlot
    stBedFiles <- list(system.file("extdata", "m6A_mm10_exomePeak_1000peaks_bed12.bed",
    system.file("extdata", "m6A_mm10_exomePeak_1000peaks_bed6.bed",
    txdb_file <- system.file("extdata", "mm10_toy.sqlite",
    # --- label=GuitarTxdb [] ---
    # Key functions: makeGuitarTxdb
    guitarTxdb <- makeGuitarTxdb(txdb = txdb,
    txMrnaComponentProp = c(0.1,0.15,0.6,0.05,0.1),
    txLncrnaComponentProp = c(0.2,0.6,0.2),
    # --- label=Check [] ---
    # Key functions: GuitarPlot
    gcl <- list(guitarTxdb$tx$tx)
    GuitarPlot(txTxdb  = txdb,
    pltTxType =  c("tx"),
    # --- label=tx comp [] ---
    # Key functions: GuitarPlot
    type <- paste(mcols(GuitarCoords)$componentType,mcols(GuitarCoords)$txType)
    key <- unique(type)
    landmark <- list(1,2,3,4,5,6,7,8,9,10,11)
    # --- label=mrna comp [] ---
    # Key functions: GuitarPlot
    GuitarPlot(txTxdb  = txdb ,
    pltTxType =  c("mrna"),
    # --- label=comp [] ---
    # Key functions: GuitarPlot
    GuitarPlot(txTxdb  = txdb ,
    pltTxType =  c("ncrna"),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_guitar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_guitar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_guitar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GUITAR:", paste0("    guitar: ", packageVersion("Guitar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_guitar_results.csv
    touch ${prefix}_guitar_output.rds
    echo "BIOC_GUITAR:" > versions.yml
    echo "    guitar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GUITAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GUITAR(ch_input)

    emit:
    results  = BIOC_GUITAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GUITAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GUITAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GUITAR.out.versions  // channel: path(versions.yml)
}
