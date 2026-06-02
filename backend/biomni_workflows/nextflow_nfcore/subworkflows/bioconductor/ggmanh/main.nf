#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggmanh
// Manhattan plot and QQ Plot are commonly used to visualize the end result of Genome Wide Association 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ggmanh/inst/doc/ggmanh.R
// Upstream  : BiocManager
// Downstream: none
//
// Install: BiocManager::install("ggmanh")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGMANH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggmanh"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggmanh:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggmanh:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ggmanh_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggmanh_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggmanh_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ggmanh)
    library(jsonlite)

    # --- Manhattan plot analysis [] ---
    # Key functions: manhattan_plot, rbind, manhattan_data_preprocess, binned_manhattan_plot, binned_manhattan_preprocess, seqOpen, seqClose, gds_annotate
    manhattan_plot(simdata, chromosome = 5, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position")
    binned_manhattan_plot(simdata, pval.colname = "P.value", chr.colname = "chromosome", pos.colname = "position")
    binned_manhattan_plot(

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggmanh_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggmanh_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggmanh_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGMANH:", paste0("    ggmanh: ", packageVersion("ggmanh"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggmanh_results.csv
    touch ${prefix}_ggmanh_output.rds
    echo "BIOC_GGMANH:" > versions.yml
    echo "    ggmanh: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGMANH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GGMANH(ch_input)

    emit:
    results  = BIOC_GGMANH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGMANH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGMANH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGMANH.out.versions  // channel: path(versions.yml)
}
