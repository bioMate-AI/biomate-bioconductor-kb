#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Rarr
// The Zarr specification defines a format for chunked, compressed, N-dimensional arrays.  It's design 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Rarr/inst/doc/Rarr.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Rarr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RARR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rarr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rarr:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rarr:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rarr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rarr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rarr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ZarrArray)
    library(jsonlite)

    # --- Image visualization [] ---
    # Key functions: zarr_overview, read_zarr_array, image, array, write_zarr_array, tempfile, create_empty_zarr_array, update_zarr_array
    x <- array(1:600, dim = c(10, 10, 6))
    path_to_new_zarr <- file.path(tempdir(), "new.zarr")
    write_zarr_array(x = x, zarr_array_path = path_to_new_zarr, chunk_dim = c(10, 5, 1))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rarr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rarr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rarr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RARR:", paste0("    rarr: ", packageVersion("Rarr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rarr_results.csv
    touch ${prefix}_rarr_output.rds
    echo "BIOC_RARR:" > versions.yml
    echo "    rarr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RARR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RARR(ch_input)

    emit:
    results  = BIOC_RARR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RARR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RARR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RARR.out.versions  // channel: path(versions.yml)
}
