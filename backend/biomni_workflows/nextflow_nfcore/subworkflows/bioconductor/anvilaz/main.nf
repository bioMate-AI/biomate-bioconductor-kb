#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AnVILAz
// The AnVIL is a cloud computing resource developed in part by the National Human Genome Research Inst
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AnVILAz/inst/doc/AnVILAzWorkspaces.R
// Upstream  : dplyr
// Downstream: none
//
// Install: BiocManager::install("AnVILAz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANVILAZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-anvilaz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-anvilaz:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-anvilaz:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_anvilaz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_anvilaz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_anvilaz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnVILAz)
    library(jsonlite)

    # --- Workspace Selection [] ---
    # Key functions: avworkspace
    AnVILAz::avworkspace("my-azure-namespace/my-azure-workspace")
    current_ws <- AnVILAz::avworkspace()


    # --- Resource Retrieval [] ---
    # Key functions: avworkspaces
    ws_list <- AnVILAz::avworkspaces()
    azure_workspaces <- ws_list[ws_list$platform == "Azure", ]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_anvilaz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_anvilaz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_anvilaz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANVILAZ:", paste0("    anvilaz: ", packageVersion("AnVILAz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_anvilaz_results.csv
    touch ${prefix}_anvilaz_output.rds
    echo "BIOC_ANVILAZ:" > versions.yml
    echo "    anvilaz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANVILAZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANVILAZ(ch_input)

    emit:
    results  = BIOC_ANVILAZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANVILAZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANVILAZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANVILAZ.out.versions  // channel: path(versions.yml)
}
