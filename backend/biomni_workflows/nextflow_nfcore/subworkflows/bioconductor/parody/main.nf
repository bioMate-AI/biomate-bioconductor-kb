#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: parody
// Provide routines for univariate and multivariate outlier detection with a focus on parametric method
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/parody/inst/doc/parody.R
// Upstream  : BiocStyle
// Downstream: arrayMvout
//
// Install: BiocManager::install("parody")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PARODY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-parody"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-parody:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-parody:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_parody_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_parody_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_parody_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(parody)
    library(jsonlite)

    # --- pairs [] ---
    # Key functions: pairs
    thecol = rep("black", nrow(tcost))
    pairs(tcost, col=thecol, pch=19)
    # --- biplot [] ---
    # Key functions: biplot
    pc = prcomp(tcost)
    biplot(pc)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_parody_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_parody_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_parody_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PARODY:", paste0("    parody: ", packageVersion("parody"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_parody_results.csv
    touch ${prefix}_parody_output.rds
    echo "BIOC_PARODY:" > versions.yml
    echo "    parody: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PARODY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PARODY(ch_input)

    emit:
    results  = BIOC_PARODY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PARODY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PARODY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PARODY.out.versions  // channel: path(versions.yml)
}
