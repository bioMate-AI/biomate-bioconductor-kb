#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TENxIO
// Provides a structured S4 approach to importing data files from the 10X pipelines. It mainly supports
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TENxIO/inst/doc/TENxIO.R
// Upstream  : rhdf5
// Downstream: VisiumIO
//
// Install: BiocManager::install("TENxIO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TENXIO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tenxio"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tenxio:1.8.2--r44_0' :
        'quay.io/biocontainers/bioconductor-tenxio:1.8.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tenxio_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tenxio_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tenxio_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentHub)
    library(TENxFileList)
    library(TENxFragments)
    library(TENxH5)
    library(jsonlite)

    # --- Showclass [] ---
    # Key functions: showClass
    ---------------------------------------------------------------------
    showClass("TENxFile")
    # --- Experimenthub [] ---
    # Key functions: ExperimentHub
    ---------------------------------------------------------------------
    hub <- ExperimentHub::ExperimentHub()
    hub["EH1039"]
    # --- Tenxh5 [] ---
    # Key functions: TENxH5
    ---------------------------------------------------------------------
    con <- TENxH5(h5f)
    con
    # --- Import [] ---
    # Key functions: import
    ---------------------------------------------------------------------
    import(con)
    # --- Tenxfilelist [] ---
    # Key functions: TENxFileList, import
    ---------------------------------------------------------------------
    con <- TENxFileList(fl)
    import(con)
    # --- Tenxfragments [] ---
    # Key functions: TENxFragments
    ---------------------------------------------------------------------
    tfr <- TENxFragments(fr)
    tfr
    # --- Import [] ---
    # Key functions: import
    ---------------------------------------------------------------------
    fra <- import(tfr)
    fra
    # --- Rowranges [] ---
    # Key functions: rowRanges
    ---------------------------------------------------------------------
    rowRanges(fra)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tenxio_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tenxio_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tenxio_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TENXIO:", paste0("    tenxio: ", packageVersion("TENxIO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tenxio_results.csv
    touch ${prefix}_tenxio_output.rds
    echo "BIOC_TENXIO:" > versions.yml
    echo "    tenxio: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TENXIO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TENXIO(ch_input)

    emit:
    results  = BIOC_TENXIO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TENXIO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TENXIO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TENXIO.out.versions  // channel: path(versions.yml)
}
