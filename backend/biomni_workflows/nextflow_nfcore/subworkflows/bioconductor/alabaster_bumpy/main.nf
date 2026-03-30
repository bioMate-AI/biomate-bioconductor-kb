#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: alabaster.bumpy
// Save BumpyMatrix objects into file artifacts, and load them back into memory. This is a more portabl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/alabaster.bumpy/inst/doc/userguide.R
// Upstream  : BiocStyle, BumpyMatrix, S4Vectors
// Downstream: none
//
// Install: BiocManager::install("alabaster.bumpy")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALABASTER_BUMPY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alabaster_bumpy"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alabaster.bumpy:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-alabaster.bumpy:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alabaster_bumpy_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alabaster_bumpy_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alabaster_bumpy_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BumpyMatrix)
    library(DataFrame)
    library(jsonlite)

    # --- Dataframe [] ---
    # Key functions: DataFrame, runif, factor, sample, BumpyMatrix, split
    ---------------------------------------------------------------------
    library(BumpyMatrix)
    library(S4Vectors)
    df <- DataFrame(x=runif(100), y=runif(100))
    f <- factor(sample(letters[1:20], nrow(df), replace=TRUE), letters[1:20])
    # --- Readobject [] ---
    # Key functions: readObject
    ---------------------------------------------------------------------
    readObject(tmp)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alabaster_bumpy_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alabaster_bumpy_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alabaster_bumpy_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALABASTER_BUMPY:", paste0("    alabaster_bumpy: ", packageVersion("alabaster.bumpy"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alabaster_bumpy_results.csv
    touch ${prefix}_alabaster_bumpy_output.rds
    echo "BIOC_ALABASTER_BUMPY:" > versions.yml
    echo "    alabaster_bumpy: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALABASTER_BUMPY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALABASTER_BUMPY(ch_input)

    emit:
    results  = BIOC_ALABASTER_BUMPY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALABASTER_BUMPY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALABASTER_BUMPY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALABASTER_BUMPY.out.versions  // channel: path(versions.yml)
}
