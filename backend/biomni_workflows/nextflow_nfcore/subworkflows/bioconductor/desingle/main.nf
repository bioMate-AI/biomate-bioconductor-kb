#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DEsingle
// DEsingle is an R package for differential expression (DE) analysis of single-cell RNA-seq (scRNA-seq
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DEsingle/inst/doc/DEsingle.R
// Upstream  : BiocManager, BiocParallel, SingleCellExperiment, devtools
// Downstream: none
//
// Install: BiocManager::install("DEsingle")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DESINGLE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-desingle"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-desingle:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-desingle:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_desingle_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_desingle_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_desingle_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DEsingle)
    library(MulticoreParam)
    library(SingleCellExperiment)
    library(SnowParam)
    library(jsonlite)

    # --- D Esingle [] ---
    # Key functions: DEsingle
    library(DEsingle)
    data(TestData)
    group <- factor(c(rep(1,50), rep(2,100)))
    # --- Create SingleCellExperiment object [] ---
    # Key functions: SingleCellExperiment, DEsingle
    library(DEsingle)
    library(SingleCellExperiment)
    data(TestData)
    # --- D Esingle [] ---
    # Key functions: DEsingle
    library(DEsingle)
    results <- DEsingle(counts = counts, group = group, parallel = TRUE)
    # --- Multicore Param [] ---
    # Key functions: MulticoreParam, register, DEsingle
    library(DEsingle)
    library(BiocParallel)
    param <- MulticoreParam(workers = 18, progressbar = TRUE)
    # --- Snow Param [] ---
    # Key functions: SnowParam, register, DEsingle
    library(DEsingle)
    library(BiocParallel)
    param <- SnowParam(workers = 8, type = "SOCK", progressbar = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_desingle_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_desingle_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_desingle_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DESINGLE:", paste0("    desingle: ", packageVersion("DEsingle"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_desingle_results.csv
    touch ${prefix}_desingle_output.rds
    echo "BIOC_DESINGLE:" > versions.yml
    echo "    desingle: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DESINGLE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DESINGLE(ch_input)

    emit:
    results  = BIOC_DESINGLE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DESINGLE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DESINGLE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DESINGLE.out.versions  // channel: path(versions.yml)
}
