#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: abseqR
// AbSeq is a comprehensive bioinformatic pipeline for the analysis of sequencing datasets generated fr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/abseqR/inst/doc/abseqR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("abseqR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ABSEQR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-abseqr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-abseqr:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-abseqr:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_abseqr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_abseqr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_abseqr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SerialParam)
    library(jsonlite)

    # --- NormalizePath analysis [] ---
    # Key functions: include_graphics, normalizePath, read_png, tempdir, SerialParam, bpparam, abseqReport, report
    unscaled <- file.path(sdir, "diversity", "composition_logos", "CDR3", "PCR1_cumulative_logo.png")
    scaled <- file.path(sdir, "diversity", "composition_logos", "CDR3", "PCR1_cumulative_logo_scaled.png")
    img1 <-  rasterGrob(as.raster(readPNG(unscaled)), interpolate = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_abseqr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_abseqr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_abseqr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ABSEQR:", paste0("    abseqr: ", packageVersion("abseqR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_abseqr_results.csv
    touch ${prefix}_abseqr_output.rds
    echo "BIOC_ABSEQR:" > versions.yml
    echo "    abseqr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ABSEQR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_ABSEQR(ch_input)

    emit:
    results  = BIOC_ABSEQR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ABSEQR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ABSEQR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ABSEQR.out.versions  // channel: path(versions.yml)
}
