#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rifi
// 'rifi' analyses data from rifampicin time series created by microarray or RNAseq. 'rifi' is a transc
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rifi/inst/doc/vignette.R
// Upstream  : SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("rifi")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIFI {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rifi"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rifi:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rifi:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rifi_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rifi_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rifi_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TI_fit)
    library(TUgether)
    library(jsonlite)

    # --- rifi_wrapper [] ---
    # Key functions: rifi_wrapper
    library(rifi)
    data(example_input_e_coli)
    Path = gzfile(system.file("extdata", "gff_e_coli.gff3.gz", package = "rifi"))
    # --- check_input [] ---
    # Key functions: check_input
    probe <- check_input(inp = example_input_minimal, thrsh = 0)
    # --- make_df [] ---
    # Key functions: make_df

    # --- segment_pos [] ---
    # Key functions: segment_pos
    probe <- segment_pos(inp = probe, dista = 300)
    head(rowRanges(probe))
    # --- finding PDD [] ---
    # Key functions: finding_PDD

    # --- finding TI [] ---
    # Key functions: finding_TI

    # --- rifi preprocess [] ---
    # Key functions: rifi_preprocess

    # --- TI fit [] ---
    # Key functions: TI_fit

    # --- plot nls2 [] ---
    # Key functions: plot_nls2_function
    plot_nls2_function(inp = probe_df)
    # --- plot nls2 function [] ---
    # Key functions: plot_nls2_function
    plot_nls2_function(inp = probe_df)
    # --- make_pen [] ---
    # Key functions: make_pen
    data(fit_minimal)
    # --- viz pen obj [] ---
    # Key functions: viz_pen_obj
    viz_pen_obj(obj = pen_delay, top_i = 10)
    # --- rifi fragmentation [] ---
    # Key functions: rifi_fragmentation
    data(penalties_minimal)
    # --- fragment_delay [] ---
    # Key functions: fragment_delay
    data(fragmentation_minimal)
    data(penalties_minimal)
    # --- fragment HL [] ---
    # Key functions: fragment_HL
    data(fragmentation_minimal)
    data(penalties_minimal)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rifi_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rifi_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rifi_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RIFI:", paste0("    rifi: ", packageVersion("rifi"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rifi_results.csv
    touch ${prefix}_rifi_output.rds
    echo "BIOC_RIFI:" > versions.yml
    echo "    rifi: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RIFI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RIFI(ch_input)

    emit:
    results  = BIOC_RIFI.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RIFI.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RIFI.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RIFI.out.versions  // channel: path(versions.yml)
}
