#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MethylAid
// A visual and interactive web application using RStudio's shiny package. Bad quality samples are dete
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MethylAid/inst/doc/MethylAid.R
// Upstream  : BiocParallel, GEOquery, MethylAidData, minfiData, minfiDataEPIC
// Downstream: MethylAidData
//
// Install: BiocManager::install("MethylAid")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLAID {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylaid"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylaid:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methylaid:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylaid_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylaid_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylaid_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BatchJobsParam)
    library(jsonlite)

    # --- Fetch GEO dataset [] ---
    # Key functions: getGEO, pData
    library(GEOquery)
    gse <- getGEO("GSE42861")
    targets <- pData(phenoData(gse[[1]]))
    # --- Summarize analysis [] ---
    # Key functions: summarize, visualize, BatchJobsParam, combine
    library(BiocParallel)
    conffile <- system.file("scripts/config.R", package="MethylAid")
    BPPARAM <- BatchJobsParam(workers = 10,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylaid_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylaid_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylaid_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLAID:", paste0("    methylaid: ", packageVersion("MethylAid"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylaid_results.csv
    touch ${prefix}_methylaid_output.rds
    echo "BIOC_METHYLAID:" > versions.yml
    echo "    methylaid: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLAID_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLAID(ch_input)

    emit:
    results  = BIOC_METHYLAID.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLAID.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLAID.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLAID.out.versions  // channel: path(versions.yml)
}
