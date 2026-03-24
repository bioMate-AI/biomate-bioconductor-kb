#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: VisiumIO
// The package allows users to readily import spatial data obtained from either the 10X website or from
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/VisiumIO/inst/doc/VisiumIO.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("VisiumIO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_VISIUMIO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-visiumio"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-visiumio:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-visiumio:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_visiumio_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_visiumio_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_visiumio_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TENxVisiumHD)
    library(TENxVisiumList)
    library(jsonlite)

    # --- Import Visium Data [] ---
    # Key functions: import
    ---------------------------------------------------------------------
    import(vis)
    # --- Import Multiple Visium Datasets [] ---
    # Key functions: dirs, path, TENxVisiumList
    ---------------------------------------------------------------------
    sample_dirs <- list.dirs(
        system.file(
            file.path("extdata", "10xVisium"), package = "VisiumIO"
        ),
    # --- Import Visium Data [] ---
    # Key functions: import
    ---------------------------------------------------------------------
    import(vlist)
    # --- Import Visium HD Data [] ---
    # Key functions: TENxVisiumHD, import
    ---------------------------------------------------------------------
    TENxVisiumHD(
        spacerangerOut = visfold, images = "lowres", bin_size = "002",
        format = "h5"
    ) |> import()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_visiumio_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_visiumio_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_visiumio_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_VISIUMIO:", paste0("    visiumio: ", packageVersion("VisiumIO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_visiumio_results.csv
    touch ${prefix}_visiumio_output.rds
    echo "BIOC_VISIUMIO:" > versions.yml
    echo "    visiumio: 0.0.0" >> versions.yml
    """
}


workflow BIOC_VISIUMIO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_VISIUMIO(ch_input)

    emit:
    results  = BIOC_VISIUMIO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_VISIUMIO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_VISIUMIO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_VISIUMIO.out.versions  // channel: path(versions.yml)
}
