#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biomformat
// This is an R package for interfacing with the BIOM format. This package includes basic tools for rea
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biomformat/inst/doc/biomformat.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("biomformat")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOMFORMAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biomformat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biomformat:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biomformat:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biomformat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biomformat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biomformat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biomformat)
    library(jsonlite)

    # --- biom_data [] ---
    # Key functions: biom_data
    biom_data(x1)
    biom_data(x2)
    # --- observation_metadata [] ---
    # Key functions: observation_metadata
    observation_metadata(x1)
    observation_metadata(x2)
    observation_metadata(x3)
    # --- sample_metadata [] ---
    # Key functions: sample_metadata
    sample_metadata(x1)
    sample_metadata(x2)
    sample_metadata(x3)
    # --- heatmap [] ---
    # Key functions: heatmap
    plot(biom_data(x4))
    boxplot(as(biom_data(x4), "vector"))
    heatmap(as(biom_data(x4), "matrix"))
    # --- write_biom [] ---
    # Key functions: write_biom
    outfile = tempfile()
    write_biom(x4, outfile)
    y = read_biom(outfile)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biomformat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biomformat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biomformat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOMFORMAT:", paste0("    biomformat: ", packageVersion("biomformat"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomformat_results.csv
    touch ${prefix}_biomformat_output.rds
    echo "BIOC_BIOMFORMAT:" > versions.yml
    echo "    biomformat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOMFORMAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOMFORMAT(ch_input)

    emit:
    results  = BIOC_BIOMFORMAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOMFORMAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOMFORMAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOMFORMAT.out.versions  // channel: path(versions.yml)
}
