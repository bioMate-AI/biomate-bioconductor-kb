#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: erma
// Software and data to support epigenomic road map adventures.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/erma/inst/doc/erma.R
// Upstream  : BiocParallel, BiocStyle, DT, GenomicFiles, ggplot2
// Downstream: none
//
// Install: BiocManager::install("erma")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ERMA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-erma"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-erma:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-erma:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_erma_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_erma_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_erma_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(erma)
    library(jsonlite)


    # --- Dosetup [] ---
    # Key functions: suppressPackageStartupMessages
    suppressPackageStartupMessages({
    library(rtracklayer)
    library(BiocStyle)
    library(erma)
    library(GenomicFiles)
    library(ggplot2)
    library(grid)
    library(png)
    library(DT)
    })

    # --- Lkm [] ---
    # Key functions: mapmeta, datatable
    library(DT)
    library(erma)
    meta = mapmeta()
    kpc = c("Comments", "Epigenome.ID..EID.", "Epigenome.Mnemonic", "Quality.Rating", 
    "Standardized.Epigenome.name", "ANATOMY", "TYPE")
    datatable(as.data.frame(meta[,kpc]))

    # --- Lkst [] ---
    # Key functions: datatable
    data(states_25)
    datatable(states_25)

    # --- Dofig [] ---
    # Key functions: readPNG, grid.raster, erma
    library(png)
    im = readPNG(system.file("pngs/emparms.png", package="erma"))
    grid.raster(im)

    # --- Getgf [] ---
    # Key functions: makeErmaSet, cellTypes, datatable, colData
    ermaset = makeErmaSet()
    ermaset
    cellTypes(ermaset)[1:5]
    datatable(as.data.frame(colData(ermaset)[,kpc]))

    # --- Getgm [] ---
    # Key functions: flank, resize, genemodel
    uil33 = flank(resize(range(genemodel("IL33")), 1), width=50000)
    uil33

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_erma_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_erma_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_erma_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ERMA:", paste0("    erma: ", packageVersion("erma"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_erma_results.csv
    touch ${prefix}_erma_output.rds
    echo "BIOC_ERMA:" > versions.yml
    echo "    erma: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ERMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ERMA(ch_input)

    emit:
    results  = BIOC_ERMA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ERMA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ERMA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ERMA.out.versions  // channel: path(versions.yml)
}
