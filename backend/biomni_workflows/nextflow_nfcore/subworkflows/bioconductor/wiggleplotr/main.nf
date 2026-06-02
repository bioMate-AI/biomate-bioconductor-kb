#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: wiggleplotr
// Tools to visualise read coverage from sequencing experiments together with genomic annotations (gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/wiggleplotr/inst/doc/wiggleplotr.R
// Upstream  : GenomicFeatures, GenomicRanges, biomaRt, dplyr, ensembldb
// Downstream: none
//
// Install: BiocManager::install("wiggleplotr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_WIGGLEPLOTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-wiggleplotr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-wiggleplotr:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-wiggleplotr:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_wiggleplotr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_wiggleplotr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_wiggleplotr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(wiggleplotr)
    library(jsonlite)

    # --- Coverage Plotting [] ---
    # Key functions: plotCoverage, getGenotypePalette
    track_data <- data.frame(
        sample_id = c("S1", "S2"),
        condition = factor(c("Ctrl", "Trt")),
        scaling_factor = c(1, 1),
        bigWig = c("s1.bw", "s2.bw"),
        track_id = c("Ctrl", "Trt"),
        colour_group = c("Ctrl", "Trt")
    )
    p2 <- plotCoverage(
        exons,
        cdss,
        tx_meta,
        track_data,
        heights = c(2, 1),
        fill_palette = getGenotypePalette()
    )


    # --- Database Integration [] ---
    # Key functions: plotTranscriptsFromEnsembldb
    p3 <- plotTranscriptsFromEnsembldb(
        ensdb = "mock_ensdb",
        gene_names = "NCOA7",
        transcript_ids = c("ENST00000438495")
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_wiggleplotr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_wiggleplotr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_wiggleplotr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_WIGGLEPLOTR:", paste0("    wiggleplotr: ", packageVersion("wiggleplotr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wiggleplotr_results.csv
    touch ${prefix}_wiggleplotr_output.rds
    echo "BIOC_WIGGLEPLOTR:" > versions.yml
    echo "    wiggleplotr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_WIGGLEPLOTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_WIGGLEPLOTR(ch_input)

    emit:
    results  = BIOC_WIGGLEPLOTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_WIGGLEPLOTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_WIGGLEPLOTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_WIGGLEPLOTR.out.versions  // channel: path(versions.yml)
}
