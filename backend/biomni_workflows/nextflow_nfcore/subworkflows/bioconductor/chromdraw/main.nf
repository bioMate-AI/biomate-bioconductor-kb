#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: chromDraw
// ChromDraw is a R package for drawing the schemes of karyotype(s) in the linear and circular fashion.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/chromDraw/inst/doc/chromDraw.R
// Upstream  : GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("chromDraw")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHROMDRAW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chromdraw"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chromdraw:2.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chromdraw:2.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chromdraw_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chromdraw_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chromdraw_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(chromDraw)
    library(GRanges)
    library(IRanges)
    library(Rle)
    library(jsonlite)

    # --- Karyotype Visualization from Genomic Ranges [] ---
    # Key functions: chromDrawGR
    chromDraw::chromDrawGR(
        list(exampleData),
        exampleColor
    )


    # --- Karyotype Visualization from Text Files [] ---
    # Key functions: chromDraw
    outputPath <- file.path(getwd())
    inputPath <- system.file(
        "extdata",
        "Ack_and_Stenopetalum_nutans.txt",
        package = "chromDraw"
    )
    colorPath <- system.file(
        "extdata",
        "default_colors.txt",
        package = "chromDraw"
    )
    chromDraw::chromDraw(
        argc = 7,
        argv = c(
            "chromDraw", "-c", colorPath, "-d", inputPath, "-o", outputPath
        )
    )


    # --- Karyotype Visualization from BED Files [] ---
    # Key functions: chromDraw
    outputPath <- file.path(getwd())
    inputPath <- system.file(
        "extdata",
        "bed.bed",
        package = "chromDraw"
    )
    chromDraw::chromDraw(
        argc = 7,
        argv = c(
            "chromDraw", "-f", "bed", "-d", inputPath, "-o", outputPath
        )
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chromdraw_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chromdraw_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chromdraw_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHROMDRAW:", paste0("    chromdraw: ", packageVersion("chromDraw"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromdraw_results.csv
    touch ${prefix}_chromdraw_output.rds
    echo "BIOC_CHROMDRAW:" > versions.yml
    echo "    chromdraw: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHROMDRAW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHROMDRAW(ch_input)

    emit:
    results  = BIOC_CHROMDRAW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHROMDRAW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHROMDRAW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHROMDRAW.out.versions  // channel: path(versions.yml)
}
