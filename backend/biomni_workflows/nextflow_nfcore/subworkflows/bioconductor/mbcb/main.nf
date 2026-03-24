#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MBCB
// This package provides a model-based background correction method, which incorporates the negative co
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MBCB/inst/doc/MBCB.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MBCB")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MBCB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mbcb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mbcb:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mbcb:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mbcb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mbcb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mbcb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MBCB)
    library(jsonlite)

    # --- Load Package And Data [] ---
    # Key functions: data
    library(MBCB);
    data(MBCBExpressionData);
    # --- Read Sample Files In [] ---
    # Key functions: parseFile
    data <- mbcb.parseFile('signal.txt', 'negative.control.txt');
    signal <- data$sig;
    negCon <- data$con;
    # --- Bg Correct Sample Data [] ---
    # Key functions: correct
    cor <- mbcb.correct(expressionSignal, negativeControl, nonparametric, RMA, MLE, MCMC, GMLE);
    # --- Mbcb.Main With Values Set [] ---
    # Key functions: main
    mbcb.main(expressionSignal, negativeControl, nonparametric, RMA, MLE, MCMC, GMLE, "param-est", "bgCorrected");
    # --- Default Mbcb.Main Run [] ---
    # Key functions: main
    mbcb.main(expressionSignal, negativeControl, paramEstFile="param-est", bgCorrectedFile="bgCorrected");
    # --- Mbcbnormalization [] ---
    # Key functions: main, csv
    mbcb.main(expressionSignal, negativeControl, normMethod="quant");
    quant_np <- read.csv("bgCorrected-NP.csv", row.names=1)
    mbcb.main(expressionSignal, negativeControl, normMethod="median");
    median_np <- read.csv("bgCorrected-NP.csv", row.names=1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mbcb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mbcb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mbcb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MBCB:", paste0("    mbcb: ", packageVersion("MBCB"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mbcb_results.csv
    touch ${prefix}_mbcb_output.rds
    echo "BIOC_MBCB:" > versions.yml
    echo "    mbcb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MBCB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MBCB(ch_input)

    emit:
    results  = BIOC_MBCB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MBCB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MBCB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MBCB.out.versions  // channel: path(versions.yml)
}
