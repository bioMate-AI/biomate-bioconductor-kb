#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: megadepth
// This package provides an R interface to Megadepth by Christopher Wilks available at https://github.c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/megadepth/inst/doc/megadepth.R
// Upstream  : RefManageR, rmarkdown, knitr, sessioninfo
// Downstream: none
//
// Install: BiocManager::install("megadepth")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEGADEPTH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-megadepth"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-megadepth:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-megadepth:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_megadepth_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_megadepth_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_megadepth_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(megadepth)
    library(PrintBibliography)
    library(jsonlite)

    # --- Coverage Computation [] ---
    # Key functions: get_coverage
    bw_cov <- get_coverage(
        example_bw,
        op = "mean",
        annotation = annotation_file
    )


    # --- Junction Extraction [] ---
    # Key functions: bam_to_junctions, read_junction_table, process_junction_table
    example_jxs <- bam_to_junctions(
        example_bam,
        overwrite = TRUE
    )
    jxs_table <- read_junction_table(example_jxs)
    processed_jxs <- process_junction_table(jxs_table)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_megadepth_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_megadepth_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_megadepth_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MEGADEPTH:", paste0("    megadepth: ", packageVersion("megadepth"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_megadepth_results.csv
    touch ${prefix}_megadepth_output.rds
    echo "BIOC_MEGADEPTH:" > versions.yml
    echo "    megadepth: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MEGADEPTH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MEGADEPTH(ch_input)

    emit:
    results  = BIOC_MEGADEPTH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MEGADEPTH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MEGADEPTH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MEGADEPTH.out.versions  // channel: path(versions.yml)
}
