#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scMitoMut
// This package is designed for calling lineage-informative mitochondrial mutations using single-cell s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scMitoMut/inst/doc/Analysis_colon_cancer_dataset.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("scMitoMut")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCMITOMUT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scmitomut"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scmitomut:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scmitomut:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scmitomut_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scmitomut_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scmitomut_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scMitoMut)
    library(jsonlite)

    # --- Open H5 File [] ---
    # Key functions: open_h5_file, h5ls
    ---------------------------------------------------------------------
    ## Open the h5 file as a scMitoMut object
    x <- open_h5_file(f_h5)
    str(x)
    ## Show what's in the h5 file
    # --- Filter Loc [] ---
    # Key functions: filter_loc
    ---------------------------------------------------------------------
    ## Filter mutation
    x <- filter_loc(
      mtmutObj = x,
      min_cell = 2,
    # --- Export Df [] ---
    # Key functions: export_df, export_af, export_pval, export_binary
    ---------------------------------------------------------------------
    ## Export the mutation data as data.frame
    m_df <- export_df(x)
    m_df[1:10, ]
    ## Export allele frequency data as data.matrix

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scmitomut_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scmitomut_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scmitomut_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCMITOMUT:", paste0("    scmitomut: ", packageVersion("scMitoMut"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scmitomut_results.csv
    touch ${prefix}_scmitomut_output.rds
    echo "BIOC_SCMITOMUT:" > versions.yml
    echo "    scmitomut: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCMITOMUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCMITOMUT(ch_input)

    emit:
    results  = BIOC_SCMITOMUT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCMITOMUT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCMITOMUT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCMITOMUT.out.versions  // channel: path(versions.yml)
}
