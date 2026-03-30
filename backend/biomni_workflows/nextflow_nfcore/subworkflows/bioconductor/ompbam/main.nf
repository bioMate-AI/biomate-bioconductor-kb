#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ompBAM
// This packages provides C++ header files for developers wishing to create R packages that processes B
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ompBAM/inst/doc/ompBAM-API-Docs.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ompBAM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMPBAM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ompbam"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ompbam:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ompbam:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ompbam_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ompbam_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ompbam_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ompBAM)
    library(jsonlite)

    # --- Document [] ---
    # Key functions: document
    ---------------------------------------------------------------------
    devtools::document(pkg_path)
    # --- Load All [] ---
    # Key functions: load_all
    ---------------------------------------------------------------------
    devtools::load_all(pkg_path)
    # --- Idxstats [] ---
    # Key functions: idxstats, example_BAM
    ---------------------------------------------------------------------
    idxstats(ompBAM::example_BAM("Unsorted"), 2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ompbam_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ompbam_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ompbam_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMPBAM:", paste0("    ompbam: ", packageVersion("ompBAM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ompbam_results.csv
    touch ${prefix}_ompbam_output.rds
    echo "BIOC_OMPBAM:" > versions.yml
    echo "    ompbam: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMPBAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMPBAM(ch_input)

    emit:
    results  = BIOC_OMPBAM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMPBAM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMPBAM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMPBAM.out.versions  // channel: path(versions.yml)
}
