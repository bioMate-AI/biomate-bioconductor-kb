#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: INPower
// An R package for computing the number of susceptibility SNPs and power of future studies
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/INPower/inst/doc/vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("INPower")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INPOWER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-inpower"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-inpower:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-inpower:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_inpower_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_inpower_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_inpower_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(INPower)
    library(jsonlite)

    # --- Data File [] ---
    # Key functions: file
    datafile <- system.file("sampleData", "data.rda", package="INPower")
    # --- Call1 [] ---
    # Key functions: INPower
    INPower(MAFs, betas, pow, span=0.5, binary.outcome=FALSE,
            sample.size=seq(25000,125000,by=25000),
            signif.lvl=10^(-7), tgv=0.8, k=seq(25,125,by=25))
    # --- Call2 [] ---
    # Key functions: INPower
    INPower(MAFs, betas, pow, span=0.5, binary.outcome=FALSE,
            sample.size=seq(25000,125000,by=25000),
            signif.lvl=10^(-7), k=seq(25,125,by=25))
    # --- Call3 [] ---
    # Key functions: INPower
    INPower(MAFs, betas, pow, span=0.5, binary.outcome=FALSE,
            sample.size=seq(25000,125000,by=25000),
            signif.lvl=10^(-7), multi.stage.option=list(al=5*10^(-5), pi=0.3),
            tgv=0.8 , k=seq(25,125,by=25))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_inpower_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_inpower_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_inpower_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INPOWER:", paste0("    inpower: ", packageVersion("INPower"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inpower_results.csv
    touch ${prefix}_inpower_output.rds
    echo "BIOC_INPOWER:" > versions.yml
    echo "    inpower: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INPOWER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INPOWER(ch_input)

    emit:
    results  = BIOC_INPOWER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INPOWER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INPOWER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INPOWER.out.versions  // channel: path(versions.yml)
}
