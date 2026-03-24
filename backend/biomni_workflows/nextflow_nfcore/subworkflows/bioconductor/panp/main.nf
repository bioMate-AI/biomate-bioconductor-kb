#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: panp
// A function to make gene presence/absence calls based on distance from negative strand matching probe
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/panp/inst/doc/panp.R
// Upstream  : gcrma
// Downstream: none
//
// Install: BiocManager::install("panp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PANP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-panp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-panp:1.76.0--r44_0' :
        'quay.io/biocontainers/bioconductor-panp:1.76.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_panp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_panp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_panp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(panp)
    library(jsonlite)

    # --- data [] ---
    # Key functions: data
    data(gcrma.ExpressionSet)
    # --- calls [] ---
    # Key functions: calls
    PA <- pa.calls(gcrma.ExpressionSet)
    # --- Data [] ---
    # Key functions: exprs, density
    data(NSMPnames.hgu133a)	# read in the NSMP names list
    # create x and y ranges for NSMP intensities
    NSMP_x <- sort(exprs(gcrma.ExpressionSet)[NSMPnames.hgu133a,1], decreasing=TRUE)
    NSMP_y <- seq(0,1,1/(length(NSMP_x)-1))
    # Plot expression densities of all probesets, then just NSMPs

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_panp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_panp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_panp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PANP:", paste0("    panp: ", packageVersion("panp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_panp_results.csv
    touch ${prefix}_panp_output.rds
    echo "BIOC_PANP:" > versions.yml
    echo "    panp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PANP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PANP(ch_input)

    emit:
    results  = BIOC_PANP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PANP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PANP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PANP.out.versions  // channel: path(versions.yml)
}
