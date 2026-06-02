#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RTCA
// Import, analyze and visualize data from Roche(R) xCELLigence RTCA systems. The package imports real-
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RTCA/inst/doc/RTCAtransformation.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("RTCA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RTCA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rtca"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rtca:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rtca:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rtca_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rtca_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rtca_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RTCA)
    library(jsonlite)

    # --- Dataset [] ---
    # Key functions: csv, frame, new, parseRTCA
    ofile <-  system.file("extdata/testOutput.csv", package="RTCA")
    pfile <- system.file("extdata/testOutputPhenoData.csv", package="RTCA")
    pData <- read.csv(pfile, sep="\t", row.names="Well")
    # --- Smoothtransform [] ---
    # Key functions: smoothTransform
    xSmooth <- smoothTransform(x)
    # --- Interpolationtranform [] ---
    # Key functions: interpolationTransform
    xInter <- interpolationTransform(x)
    # --- Derivtransform [] ---
    # Key functions: derivativeTransform
    xDeriv <- derivativeTransform(x)
    # --- Rgrtransform [] ---
    # Key functions: rgrTransform
    xRgr <- rgrTransform(x)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rtca_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rtca_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rtca_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RTCA:", paste0("    rtca: ", packageVersion("RTCA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rtca_results.csv
    touch ${prefix}_rtca_output.rds
    echo "BIOC_RTCA:" > versions.yml
    echo "    rtca: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RTCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RTCA(ch_input)

    emit:
    results  = BIOC_RTCA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RTCA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RTCA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RTCA.out.versions  // channel: path(versions.yml)
}
