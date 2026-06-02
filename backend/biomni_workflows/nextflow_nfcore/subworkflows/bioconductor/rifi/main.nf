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
    library(rifi)
    library(TI_fit)
    library(TUgether)
    library(jsonlite)

    # --- Transcription Profiling and Fitting [] ---
    # Key functions: rifi_preprocess, rifi_fit
    data(preprocess_minimal)
    fit_minimal <- rifi_fit(
        inp = preprocess_minimal,
        cores = 2,
        viz = FALSE,
        restr = 0.2,
        decay = seq(.08, 0.11, by = .02),
        delay = seq(0, 10, by = .1),
        k = seq(0.1, 1, 0.2),
        bg = 0.2,
        TI_k = seq(0, 1, by = 0.5),
        TI_decay = c(0.05, 0.1, 0.2, 0.5, 0.6),
        TI = seq(0, 1, by = 0.5),
        TI_delay = seq(0, 2, by = 0.5),
        TI_rest_delay = seq(0, 2, by = 0.5),
        TI_bg = 0
    )


    # --- Fragmentation and Statistical Analysis [] ---
    # Key functions: rifi_fragmentation, rifi_stats
    data(penalties_minimal)
    fragmentation_minimal <- rifi_fragmentation(
        inp = penalties_minimal,
        cores = 2
    )
    Path <- gzfile(system.file("extdata", "gff_e_coli.gff3.gz",
                               package = "rifi"))
    stats_minimal <- rifi_stats(
        inp = fragmentation_minimal,
        dista = 300,
        path = Path
    )

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
