#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AlpsNMR
// Reads Bruker NMR data directories both zipped and unzipped. It provides automated and efficient sign
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AlpsNMR/inst/doc/Vig01-introduction-to-alpsnmr.R
// Upstream  : dplyr, readxl
// Downstream: none
//
// Install: BiocManager::install("AlpsNMR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ALPSNMR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-alpsnmr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-alpsnmr:4.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-alpsnmr:4.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_alpsnmr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_alpsnmr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_alpsnmr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AlpsNMR)
    library(jsonlite)

    # --- dir_ls [] ---
    # Key functions: dir_ls, nmr_read_samples, nmr_meta_add, nmr_meta_get, nmr_autophase
    zip_files <- fs::dir_ls(MeOH_plasma_extraction_dir, glob = "*.zip")
    dataset <- nmr_read_samples(sample_names = zip_files)
    dataset <- nmr_meta_add(dataset, metadata = annotations, by = "NMRExperiment")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_alpsnmr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_alpsnmr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_alpsnmr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ALPSNMR:", paste0("    alpsnmr: ", packageVersion("AlpsNMR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alpsnmr_results.csv
    touch ${prefix}_alpsnmr_output.rds
    echo "BIOC_ALPSNMR:" > versions.yml
    echo "    alpsnmr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ALPSNMR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ALPSNMR(ch_input)

    emit:
    results  = BIOC_ALPSNMR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ALPSNMR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ALPSNMR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ALPSNMR.out.versions  // channel: path(versions.yml)
}
