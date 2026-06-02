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

    # --- Gozdataset [] ---
    # Key functions: GOZDataSet, GenomicOZone
    ---------------------------------------------------------------------
    # Create an input object also checking for data format, consistency, and completeness
    GOZ.ds <- GOZDataSet(data = data,
                         colData = colData,
                         design = design,
    # --- Extract Genes [] ---
    # Key functions: extract_genes, extract_zones, extract_outstanding_zones, extract_zone_expression
    ---------------------------------------------------------------------
    # Extract gene/zone GRanges object
    Gene.GRanges <- extract_genes(GOZ.ds)
    head(Gene.GRanges)
    Zone.GRanges <- extract_zones(GOZ.ds)

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
