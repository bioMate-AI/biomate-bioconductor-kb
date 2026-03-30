#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpaNorm
// This package implements the spatially aware library size normalisation algorithm, SpaNorm. SpaNorm n
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpaNorm/inst/doc/SpaNorm.R
// Upstream  : SpatialExperiment, ggplot2, patchwork
// Downstream: none
//
// Install: BiocManager::install("SpaNorm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPANORM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spanorm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spanorm:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-spanorm:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spanorm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spanorm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spanorm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpaNorm)
    library(jsonlite)

    # --- Filtergenes [] ---
    # Key functions: filterGenes
    ---------------------------------------------------------------------
    # filter genes expressed in 20% of spots
    keep = filterGenes(HumanDLPFC, 0.2)
    table(keep)
    # subset genes
    # --- Metadata [] ---
    # Key functions: metadata
    ---------------------------------------------------------------------
    # manually retrieve model
    fit.spanorm = metadata(HumanDLPFC)$SpaNorm
    fit.spanorm

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spanorm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spanorm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spanorm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPANORM:", paste0("    spanorm: ", packageVersion("SpaNorm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spanorm_results.csv
    touch ${prefix}_spanorm_output.rds
    echo "BIOC_SPANORM:" > versions.yml
    echo "    spanorm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPANORM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPANORM(ch_input)

    emit:
    results  = BIOC_SPANORM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPANORM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPANORM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPANORM.out.versions  // channel: path(versions.yml)
}
