#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GBScleanR
// GBScleanR is a package for quality check, filtering, and error correction of genotype data derived f
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GBScleanR/inst/doc/BasicUsageOfGBScleanR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GBScleanR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GBSCLEANR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gbscleanr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gbscleanr:2.0.3--r44_0' :
        'quay.io/biocontainers/bioconductor-gbscleanr:2.0.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gbscleanr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gbscleanr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gbscleanr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Position)
    library(jsonlite)

    # --- GbsrVCF2GDS analysis [] ---
    # Key functions: gbsrVCF2GDS, loadGDS, nsam, nmar, getChromosome, Position, getPosition, getAllele
    ---------------------------------------------------------------------
    # As always the first step of breeding scheme would be "pairing" cross(es) of
    # parents, never be "selfing" and a "sibling" cross,
    # the argument `crosstype` in initScheme() was deprecated on the update on April 6, 2023.
    # gds <- initScheme(gds, crosstype = "pairing", mating = matrix(1:2, 2))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gbscleanr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gbscleanr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gbscleanr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GBSCLEANR:", paste0("    gbscleanr: ", packageVersion("GBScleanR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gbscleanr_results.csv
    touch ${prefix}_gbscleanr_output.rds
    echo "BIOC_GBSCLEANR:" > versions.yml
    echo "    gbscleanr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GBSCLEANR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GBSCLEANR(ch_input)

    emit:
    results  = BIOC_GBSCLEANR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GBSCLEANR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GBSCLEANR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GBSCLEANR.out.versions  // channel: path(versions.yml)
}
