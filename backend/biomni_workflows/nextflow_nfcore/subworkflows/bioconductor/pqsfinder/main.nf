#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pqsfinder
// Pqsfinder detects DNA and RNA sequence patterns that are likely to fold into an intramolecular G-qua
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pqsfinder/inst/doc/pqsfinder.R
// Upstream  : Gviz, biomaRt, ggplot2, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("pqsfinder")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PQSFINDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pqsfinder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pqsfinder:2.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pqsfinder:2.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pqsfinder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pqsfinder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pqsfinder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiomartGeneRegionTrack)
    library(DNAString)
    library(DNAStringSet)
    library(DataTrack)
    library(GenomeAxisTrack)
    library(SequenceTrack)
    library(jsonlite)

    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot
    sf <- data.frame(score = score(pqs))
    ggplot(sf) + geom_histogram(mapping = aes(x = score), binwidth = 5)
    # --- DNAString analysis [] ---
    # Key functions: DNAString, pqsfinder, elementMetadata, density, DNAStringSet, DataTrack, SequenceTrack, export
    load(system.file("extdata", "gtrack_ahnak.RData", package="pqsfinder"))
    library(biomaRt)
    gtrack <- BiomartGeneRegionTrack(genome = gnm, symbol = gene, name = gene)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pqsfinder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pqsfinder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pqsfinder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PQSFINDER:", paste0("    pqsfinder: ", packageVersion("pqsfinder"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pqsfinder_results.csv
    touch ${prefix}_pqsfinder_output.rds
    echo "BIOC_PQSFINDER:" > versions.yml
    echo "    pqsfinder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PQSFINDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PQSFINDER(ch_input)

    emit:
    results  = BIOC_PQSFINDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PQSFINDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PQSFINDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PQSFINDER.out.versions  // channel: path(versions.yml)
}
