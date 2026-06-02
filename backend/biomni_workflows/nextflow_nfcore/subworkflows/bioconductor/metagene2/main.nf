#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: metagene2
// This package produces metagene plots to compare coverages of sequencing experiments at selected grou
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/metagene2/inst/doc/metagene2.R
// Upstream  : GenomicFeatures, knitr
// Downstream: none
//
// Install: BiocManager::install("metagene2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METAGENE2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metagene2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metagene2:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metagene2:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metagene2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metagene2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metagene2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(metagene2)
    library(jsonlite)

    # --- Coverage Profiling and Plotting [] ---
    # Key functions: produce_metagene
    example_design <- data.frame(
        Samples = bam_files,
        align1 = c(1, 1, 0, 0, 2),
        align2 = c(0, 0, 1, 1, 2)
    )
    mg$produce_metagene(
        design = example_design,
        title = "Demo metagene plot"
    )


    # --- Coverage Extraction and Manipulation [] ---
    # Key functions: get_regions, get_raw_coverages
    processed_regions <- mg$get_regions()
    coverages <- mg$get_raw_coverages()
    mg_copy <- mg$clone(deep = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metagene2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metagene2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metagene2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METAGENE2:", paste0("    metagene2: ", packageVersion("metagene2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metagene2_results.csv
    touch ${prefix}_metagene2_output.rds
    echo "BIOC_METAGENE2:" > versions.yml
    echo "    metagene2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METAGENE2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METAGENE2(ch_input)

    emit:
    results  = BIOC_METAGENE2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METAGENE2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METAGENE2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METAGENE2.out.versions  // channel: path(versions.yml)
}
