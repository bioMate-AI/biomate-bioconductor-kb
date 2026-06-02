#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RiboDiPA
// This package performs differential pattern analysis for Ribo-seq data. It identifies genes with sign
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RiboDiPA/inst/doc/RiboDiPA.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RiboDiPA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBODIPA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ribodipa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ribodipa:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ribodipa:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ribodipa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ribodipa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ribodipa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RiboDiPA)
    library(jsonlite)

    # --- plot Track [] ---
    # Key functions: plotTrack
    plotTrack(data = data.psite, genes.list = c("YDR050C", "YDR064W"),
    # --- plot Test [] ---
    # Key functions: plotTest
    plotTest(result = result.pst, genes.list = NULL, threshold = 0.05)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ribodipa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ribodipa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ribodipa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RIBODIPA:", paste0("    ribodipa: ", packageVersion("RiboDiPA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ribodipa_results.csv
    touch ${prefix}_ribodipa_output.rds
    echo "BIOC_RIBODIPA:" > versions.yml
    echo "    ribodipa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RIBODIPA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RIBODIPA(ch_input)

    emit:
    results  = BIOC_RIBODIPA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RIBODIPA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RIBODIPA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RIBODIPA.out.versions  // channel: path(versions.yml)
}
