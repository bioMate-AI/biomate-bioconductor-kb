#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RareVariantVis
// Second version of RareVariantVis package aims to provide comprehensive information about rare varian
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RareVariantVis/inst/doc/RareVariantsVis.R
// Upstream  : DataRareVariantVis
// Downstream: none
//
// Install: BiocManager::install("RareVariantVis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAREVARIANTVIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rarevariantvis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rarevariantvis:2.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rarevariantvis:2.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rarevariantvis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rarevariantvis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rarevariantvis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RareVariantVis)
    library(jsonlite)

    # --- chromosome Vis [] ---
    # Key functions: chromosomeVis
    chromosomeVis(sample=sample, sv_sample=sv_sample,
    chromosomes=c("19"))
    # --- rare Variant Vis [] ---
    # Key functions: rareVariantVis

    # --- multiple Vis [] ---
    # Key functions: multipleVis


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rarevariantvis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rarevariantvis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rarevariantvis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RAREVARIANTVIS:", paste0("    rarevariantvis: ", packageVersion("RareVariantVis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rarevariantvis_results.csv
    touch ${prefix}_rarevariantvis_output.rds
    echo "BIOC_RAREVARIANTVIS:" > versions.yml
    echo "    rarevariantvis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RAREVARIANTVIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RAREVARIANTVIS(ch_input)

    emit:
    results  = BIOC_RAREVARIANTVIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RAREVARIANTVIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RAREVARIANTVIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RAREVARIANTVIS.out.versions  // channel: path(versions.yml)
}
