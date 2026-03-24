#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ginmappeR
// Provides functionalities to translate gene or protein identifiers between state-of-art biological da
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/ginmappeR/inst/doc/ginmappeR.html
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ginmappeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GINMAPPER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ginmapper"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ginmapper:1.2.3--r44_0' :
        'quay.io/biocontainers/bioconductor-ginmapper:1.2.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ginmapper_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ginmapper_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ginmapper_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ginmappeR)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: getCARD2NCBIProtein
    library(ginmappeR)
    getCARD2NCBIProtein('3003955')
    # --- Code Block 2 [] ---
    # Key functions: getNCBIIdenticalProteins
    result <- getNCBIIdenticalProteins('AHA80958', format = 'dataframe')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ginmapper_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ginmapper_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ginmapper_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GINMAPPER:", paste0("    ginmapper: ", packageVersion("ginmappeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ginmapper_results.csv
    touch ${prefix}_ginmapper_output.rds
    echo "BIOC_GINMAPPER:" > versions.yml
    echo "    ginmapper: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GINMAPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GINMAPPER(ch_input)

    emit:
    results  = BIOC_GINMAPPER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GINMAPPER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GINMAPPER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GINMAPPER.out.versions  // channel: path(versions.yml)
}
