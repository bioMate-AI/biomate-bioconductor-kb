#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cfdnakit
// This package provides basic functions for analyzing shallow whole-genome sequencing (~0.3X or more) 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cfdnakit/inst/doc/cfdnakit-vignette.R
// Upstream  : devtools
// Downstream: none
//
// Install: BiocManager::install("cfdnakit")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CFDNAKIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cfdnakit"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cfdnakit:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cfdnakit:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cfdnakit_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cfdnakit_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cfdnakit_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cfdnakit)
    library(jsonlite)

    # --- read a bam file and splited into 1000 KB non [] ---
    # Key functions: read_bamfile
    library(cfdnakit)
    # --- plot fragment length distribution [] ---
    # Key functions: plot_fragment_dist
    plot_fragment_dist(list("Plasma.Sample"=plasma_SampleBam))
    # --- plot fragment length distribution comparing to a healthy cfDNA [] ---
    # Key functions: plot_fragment_dist

    # --- getting fragment length profile [] ---
    # Key functions: get_fragment_profile

    # --- plot_sl_ratio [] ---
    # Key functions: plot_sl_ratio

    # --- Reading PoN samples [] ---
    # Key functions: get_zscore_profile

    # --- Reading PoN samples and plot scaled value [] ---
    # Key functions: segmentByPSCB, plot_transformed_sl
    sample_zscore_segment <- segmentByPSCB(sample_zscore)
    plot_transformed_sl(sample_zscore,sample_zscore_segment)
    # --- cnv calling and plot distance matrix [] ---
    # Key functions: call_cnv, plot_distance_matrix
    sample_cnv <- call_cnv(sample_zscore_segment,sample_zscore)
    plot_distance_matrix(sample_cnv)
    # --- get and print solution table [] ---
    # Key functions: get_solution_table
    solution_table <- get_solution_table(sample_cnv)
    # --- plot_cnv_solution [] ---
    # Key functions: plot_cnv_solution
    plot_cnv_solution(sample_cnv,selected_solution = 1)
    # --- calculate CES score [] ---
    # Key functions: calculate_CES_score
    calculate_CES_score(sample_zscore_segment)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cfdnakit_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cfdnakit_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cfdnakit_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CFDNAKIT:", paste0("    cfdnakit: ", packageVersion("cfdnakit"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cfdnakit_results.csv
    touch ${prefix}_cfdnakit_output.rds
    echo "BIOC_CFDNAKIT:" > versions.yml
    echo "    cfdnakit: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CFDNAKIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CFDNAKIT(ch_input)

    emit:
    results  = BIOC_CFDNAKIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CFDNAKIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CFDNAKIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CFDNAKIT.out.versions  // channel: path(versions.yml)
}
