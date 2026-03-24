#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Pedixplorer
// Routines to handle family data with a Pedigree object. The initial purpose was to create correlation
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Pedixplorer/inst/doc/Pedixplorer.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("Pedixplorer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PEDIXPLORER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pedixplorer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pedixplorer:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pedixplorer:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_pedixplorer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pedixplorer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pedixplorer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Pedigree)
    library(jsonlite)

    # --- Pedigree analysis [] ---
    # Key functions: Pedigree, with, kinship, mcols, generate_colors, rel, scales, fill
    mcols(ped2)$bald <- as.factor(c(0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1))
    ped2 <- generate_colors(ped2, col_aff = "bald", add_to_scale = TRUE)
    op <- par(mai = c(1.5, 0.2, 0.2, 0.2))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pedixplorer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pedixplorer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pedixplorer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PEDIXPLORER:", paste0("    pedixplorer: ", packageVersion("Pedixplorer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pedixplorer_results.csv
    touch ${prefix}_pedixplorer_output.rds
    echo "BIOC_PEDIXPLORER:" > versions.yml
    echo "    pedixplorer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PEDIXPLORER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_PEDIXPLORER(ch_input)

    emit:
    results  = BIOC_PEDIXPLORER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PEDIXPLORER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PEDIXPLORER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PEDIXPLORER.out.versions  // channel: path(versions.yml)
}
