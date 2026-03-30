#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: seq.hotSPOT
// seq.hotSPOT provides a resource for designing effective sequencing panels to help improve mutation c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/seq.hotSPOT/inst/doc/hotSPOT-vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("seq.hotSPOT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQ_HOTSPOT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-seq_hotspot"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-seq.hotspot:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-seq.hotspot:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_seq_hotspot_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_seq_hotspot_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_seq_hotspot_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(seq.hotSPOT)
    library(jsonlite)

    # --- run amp finder [] ---
    # Key functions: amp_pool
    amps <- amp_pool(data = mutation_data, amp = 100)
    head(amps)
    # --- fw_hotspot [] ---
    # Key functions: fw_hotspot
    fw_bins <- fw_hotspot(bins = amps, data = mutation_data, amp = 100, len = 1000, include_genes = TRUE)
    head(fw_bins)
    # --- com_hotspot [] ---
    # Key functions: com_hotspot
    com_bins <- com_hotspot(fw_panel = fw_bins, bins = amps, data = mutation_data,
    head(com_bins)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_seq_hotspot_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_seq_hotspot_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_seq_hotspot_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SEQ_HOTSPOT:", paste0("    seq_hotspot: ", packageVersion("seq.hotSPOT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_seq_hotspot_results.csv
    touch ${prefix}_seq_hotspot_output.rds
    echo "BIOC_SEQ_HOTSPOT:" > versions.yml
    echo "    seq_hotspot: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SEQ_HOTSPOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SEQ_HOTSPOT(ch_input)

    emit:
    results  = BIOC_SEQ_HOTSPOT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SEQ_HOTSPOT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SEQ_HOTSPOT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SEQ_HOTSPOT.out.versions  // channel: path(versions.yml)
}
