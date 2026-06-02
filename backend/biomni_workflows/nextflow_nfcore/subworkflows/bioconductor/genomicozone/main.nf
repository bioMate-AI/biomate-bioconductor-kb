#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GenomicOZone
// The package clusters gene activity along chromosome into zones, detects differential zones as outsta
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GenomicOZone/inst/doc/GenomicOZone.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GenomicOZone")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICOZONE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicozone"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicozone:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicozone:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicozone_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicozone_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicozone_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GOZDataSet)
    library(GenomicOZone)
    library(jsonlite)

    # --- Outstanding Zone Analysis [] ---
    # Key functions: GenomicOZone
    GOZ.ds <- GenomicOZone(GOZ.ds)


    # --- Feature Extraction [] ---
    # Key functions: extract_genes, extract_zones, extract_outstanding_zones, extract_zone_expression
    Gene.GRanges <- extract_genes(GOZ.ds)
    Zone.GRanges <- extract_zones(GOZ.ds)
    OZone.GRanges <- extract_outstanding_zones(
        GOZ.ds,
        alpha = 0.05,
        min.effect.size = 0.36
    )
    Zone.exp.mat <- extract_zone_expression(GOZ.ds)


    # --- Visualization [] ---
    # Key functions: plot_genome, plot_chromosomes, plot_zones
    plot_genome(GOZ.ds, plot.file = "genome.pdf",
        alpha = 0.05, min.effect.size = 0.36)
    plot_chromosomes(GOZ.ds, plot.file = "chromosomes.pdf",
        alpha = 0.05, min.effect.size = 0.36)
    plot_zones(GOZ.ds, plot.file = "zones.pdf",
        plot.all.zones = FALSE,
        alpha = 0.05, min.effect.size = 0.36)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicozone_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicozone_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicozone_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICOZONE:", paste0("    genomicozone: ", packageVersion("GenomicOZone"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicozone_results.csv
    touch ${prefix}_genomicozone_output.rds
    echo "BIOC_GENOMICOZONE:" > versions.yml
    echo "    genomicozone: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICOZONE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICOZONE(ch_input)

    emit:
    results  = BIOC_GENOMICOZONE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICOZONE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICOZONE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICOZONE.out.versions  // channel: path(versions.yml)
}
