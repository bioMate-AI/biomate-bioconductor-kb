#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: affyContam
// structured corruption of cel file data to demonstrate QA effectiveness
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/affyContam/inst/doc/affyContam.R
// Upstream  : SpikeIn, affy, affyMvout, affydata, limma
// Downstream: none
//
// Install: BiocManager::install("affyContam")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFYCONTAM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-affycontam"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-affycontam:1.64.0--r44_0' :
        'quay.io/biocontainers/bioconductor-affycontam:1.64.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_affycontam_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_affycontam_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_affycontam_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(affyContam)
    library(jsonlite)

    # --- Circular Contamination Simulation [setCircRegion] ---
    # Key functions: setCircRegion
    data(Dilution, package = "affydata")
    dilc_circ <- setCircRegion(
        Dilution,
        chip = 1,
        center = c(250, 250),
        rad = 80,
        val = 8000
    )

    # --- Rectangular Contamination Simulation [setRectRegion] ---
    # Key functions: setRectRegion
    data(Dilution, package = "affydata")
    dilc_rect <- setRectRegion(
        Dilution,
        chip = 2,
        x = 50:150,
        y = 100:200,
        val = 12000
    )

    # --- Spatial Artifact Visualization [image] ---
    # Key functions: image
    image(Dilution[, 1])
    image(dilc_circ[, 1])
    image(Dilution[, 2])
    image(dilc_rect[, 2])


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_affycontam_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_affycontam_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_affycontam_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AFFYCONTAM:", paste0("    affycontam: ", packageVersion("affyContam"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affycontam_results.csv
    touch ${prefix}_affycontam_output.rds
    echo "BIOC_AFFYCONTAM:" > versions.yml
    echo "    affycontam: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AFFYCONTAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AFFYCONTAM(ch_input)

    emit:
    results  = BIOC_AFFYCONTAM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AFFYCONTAM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AFFYCONTAM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AFFYCONTAM.out.versions  // channel: path(versions.yml)
}
