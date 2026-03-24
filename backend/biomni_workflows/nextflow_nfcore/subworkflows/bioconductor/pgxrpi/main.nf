#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pgxRpi
// The package is an R wrapper for Progenetix REST API built upon the Beacon v2 protocol. Its purpose i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pgxRpi/inst/doc/Introduction_1_load_metadata.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("pgxRpi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PGXRPI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pgxrpi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pgxrpi:1.2.3--r44_0' :
        'quay.io/biocontainers/bioconductor-pgxrpi:1.2.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pgxrpi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pgxrpi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pgxrpi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pgxRpi)
    library(jsonlite)

    # --- Pgxloader [] ---
    # Key functions: pgxLoader
    ---------------------------------------------------------------------
    all_filters <- pgxLoader(type="filtering_terms")
    head(all_filters)
    # --- Pgxloader [] ---
    # Key functions: pgxLoader, pgxMetaplot
    ---------------------------------------------------------------------
    # query metadata of individuals with lung adenocarcinoma
    luad_inds <- pgxLoader(type="individuals",filters="NCIT:C3512")
    # use 70 years old as the splitting condition
    pgxMetaplot(data=luad_inds, group_id="age_iso", condition="P70Y", pval=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pgxrpi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pgxrpi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pgxrpi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PGXRPI:", paste0("    pgxrpi: ", packageVersion("pgxRpi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pgxrpi_results.csv
    touch ${prefix}_pgxrpi_output.rds
    echo "BIOC_PGXRPI:" > versions.yml
    echo "    pgxrpi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PGXRPI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PGXRPI(ch_input)

    emit:
    results  = BIOC_PGXRPI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PGXRPI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PGXRPI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PGXRPI.out.versions  // channel: path(versions.yml)
}
