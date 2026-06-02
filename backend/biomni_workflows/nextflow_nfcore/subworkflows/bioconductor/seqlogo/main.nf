#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: seqLogo
// seqLogo takes the position weight matrix of a DNA sequence motif and plots the corresponding sequenc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/seqLogo/inst/doc/seqLogo.R
// Upstream  : none
// Downstream: rGADEM, generegulation
//
// Install: BiocManager::install("seqLogo")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQLOGO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seqlogo"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seqlogo:1.72.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seqlogo:1.72.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seqlogo_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seqlogo_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seqlogo_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(seqLogo)
    library(jsonlite)

    # --- markdown [] ---
    # Key functions: markdown, latex

    # --- make P W M [] ---
    # Key functions: makePWM
    mFile <- system.file("extdata/pwm1", package="seqLogo")
    m <- read.table(mFile)
    p <- makePWM(m)
    # --- slot Names [] ---
    # Key functions: slotNames, pwm, consensus
    slotNames(p)
    pwm(p)
    ic(p)
    # --- seq Logo [] ---
    # Key functions: seqLogo
    seqLogo(p, ic.scale=FALSE)
    # --- make P W M [] ---
    # Key functions: makePWM, seqLogo
    r <- makePWM(m, alphabet="RNA")
    seqLogo(r, ic.scale=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seqlogo_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seqlogo_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seqlogo_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQLOGO:", paste0("    seqlogo: ", packageVersion("seqLogo"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seqlogo_results.csv
    touch ${prefix}_seqlogo_output.rds
    echo "BIOC_SEQLOGO:" > versions.yml
    echo "    seqlogo: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQLOGO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQLOGO(ch_input)

    emit:
    results  = BIOC_SEQLOGO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQLOGO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQLOGO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQLOGO.out.versions  // channel: path(versions.yml)
}
