#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ASICS
// With a set of pure metabolite reference spectra, ASICS quantifies concentration of metabolites in a 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ASICS/inst/doc/ASICS.R
// Upstream  : ASICSdata
// Downstream: none
//
// Install: BiocManager::install("ASICS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-asics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-asics:2.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-asics:2.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_asics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_asics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_asics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ASICS)
    library(ASICSUsersGuide)
    library(jsonlite)

    # --- A S I C S Users Guide [] ---
    # Key functions: ASICSUsersGuide
    library(ASICS)
    ASICSUsersGuide(view = FALSE)
    # --- import Spectra Bruker [] ---
    # Key functions: importSpectraBruker
    current_path <- system.file("extdata", "example_spectra", package = "ASICS")
    spectra_data <- importSpectraBruker(current_path)
    # --- create Spectra [] ---
    # Key functions: createSpectra
    spectra_obj <- createSpectra(spectra_data)
    # --- A S I C S [] ---
    # Key functions: ASICS
    to_exclude <- matrix(c(4.5, 10), ncol = 2)
    resASICS <- ASICS(spectra_obj, exclusion.areas = to_exclude, verbose = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_asics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_asics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_asics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ASICS:", paste0("    asics: ", packageVersion("ASICS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_asics_results.csv
    touch ${prefix}_asics_output.rds
    echo "BIOC_ASICS:" > versions.yml
    echo "    asics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ASICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ASICS(ch_input)

    emit:
    results  = BIOC_ASICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ASICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ASICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ASICS.out.versions  // channel: path(versions.yml)
}
