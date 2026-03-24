#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PathoStat
// The purpose of this package is to perform Statistical Microbiome Analysis on metagenomics results fr
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/PathoStat/inst/doc/PathoStat-vignette.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PathoStat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PATHOSTAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pathostat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pathostat:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pathostat:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pathostat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pathostat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pathostat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PathoStat)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: runPathoStat
    require(PathoStat)
    runPathoStat()
    # --- Code Block 2 [] ---
    # Key functions: 1, namespace
    #> R version 4.4.1 (2024-06-14)
    #> Platform: x86_64-pc-linux-gnu
    #> Running under: Ubuntu 24.04.1 LTS
    #>
    #> Matrix products: default

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pathostat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pathostat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pathostat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PATHOSTAT:", paste0("    pathostat: ", packageVersion("PathoStat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathostat_results.csv
    touch ${prefix}_pathostat_output.rds
    echo "BIOC_PATHOSTAT:" > versions.yml
    echo "    pathostat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PATHOSTAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PATHOSTAT(ch_input)

    emit:
    results  = BIOC_PATHOSTAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PATHOSTAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PATHOSTAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PATHOSTAT.out.versions  // channel: path(versions.yml)
}
