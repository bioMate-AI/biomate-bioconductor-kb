#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SingleMoleculeFootprinting
// SingleMoleculeFootprinting provides functions to analyze Single Molecule Footprinting (SMF) data. Fo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SingleMoleculeFootprinting/inst/doc/FootprintCharter.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SingleMoleculeFootprinting")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SINGLEMOLECULEFOOTPRINTING {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-singlemoleculefootprinting"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-singlemoleculefootprinting:2.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-singlemoleculefootprinting:2.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_singlemoleculefootprinting_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_singlemoleculefootprinting_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_singlemoleculefootprinting_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(IRanges)
    library(PlotAvgSMF)
    library(jsonlite)

    # --- Qread [] ---
    # Key functions: qread, GRanges, IRanges, PlotAvgSMF
    ---------------------------------------------------------------------
    Methylation = qs::qread(system.file("extdata", "Methylation_4.qs", package="SingleMoleculeFootprinting"))
    RegionOfInterest = GRanges("chr6", IRanges(88106000, 88106500))
    TFBSs = qs::qread(system.file("extdata", "TFBSs_1.qs", package="SingleMoleculeFootprinting"))
    PlotAvgSMF(MethGR = Methylation[[1]], RegionOfInterest = RegionOfInterest, TFBSs = TFBSs)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_singlemoleculefootprinting_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_singlemoleculefootprinting_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_singlemoleculefootprinting_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SINGLEMOLECULEFOOTPRINTING:", paste0("    singlemoleculefootprinting: ", packageVersion("SingleMoleculeFootprinting"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_singlemoleculefootprinting_results.csv
    touch ${prefix}_singlemoleculefootprinting_output.rds
    echo "BIOC_SINGLEMOLECULEFOOTPRINTING:" > versions.yml
    echo "    singlemoleculefootprinting: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SINGLEMOLECULEFOOTPRINTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SINGLEMOLECULEFOOTPRINTING(ch_input)

    emit:
    results  = BIOC_SINGLEMOLECULEFOOTPRINTING.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SINGLEMOLECULEFOOTPRINTING.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SINGLEMOLECULEFOOTPRINTING.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SINGLEMOLECULEFOOTPRINTING.out.versions  // channel: path(versions.yml)
}
