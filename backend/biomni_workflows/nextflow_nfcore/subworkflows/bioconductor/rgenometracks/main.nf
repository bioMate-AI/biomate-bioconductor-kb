#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rGenomeTracks
// rGenomeTracks package leverages the power of pyGenomeTracks software with the interactivity of R. py
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rGenomeTracks/inst/doc/rGenomeTracks.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rGenomeTracks")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RGENOMETRACKS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rgenometracks"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rgenometracks:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rgenometracks:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rgenometracks_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rgenometracks_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rgenometracks_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(rGenomeTracks)
    library(jsonlite)

    # --- Files [] ---
    # Key functions: files, bed
    ---------------------------------------------------------------------
    dirs <- list.files(system.file("extdata", package = "rGenomeTracks"), full.names = TRUE)
    # filter only bed files (without bedgraphs or narrowpeaks)
    bed_dirs <- grep(
      dirs,  pattern = ".bed(?!graph)", perl = TRUE, value = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rgenometracks_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rgenometracks_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rgenometracks_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RGENOMETRACKS:", paste0("    rgenometracks: ", packageVersion("rGenomeTracks"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rgenometracks_results.csv
    touch ${prefix}_rgenometracks_output.rds
    echo "BIOC_RGENOMETRACKS:" > versions.yml
    echo "    rgenometracks: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RGENOMETRACKS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RGENOMETRACKS(ch_input)

    emit:
    results  = BIOC_RGENOMETRACKS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RGENOMETRACKS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RGENOMETRACKS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RGENOMETRACKS.out.versions  // channel: path(versions.yml)
}
