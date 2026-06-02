#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CeTF
// This package provides the necessary functions for performing the Partial Correlation coefficient wit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CeTF/inst/doc/CeTF.R
// Upstream  : airway, dplyr, kableExtra, knitr
// Downstream: none
//
// Install: BiocManager::install("CeTF")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CETF {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cetf"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cetf:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cetf:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cetf_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cetf_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cetf_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CeTF)
    library(PCIT)
    library(SmearPlot)
    library(jsonlite)

    # --- PCIT Analysis [] ---
    # Key functions: PCIT
    PCIT_input_untrt <- PCIT_input[, grep("_untrt", colnames(PCIT_input))]
    PCIT_input_trt <- PCIT_input[, grep("_trt", colnames(PCIT_input))]
    PCIT_out_untrt <- PCIT(PCIT_input_untrt, tolType = "mean")
    PCIT_out_trt <- PCIT(PCIT_input_trt, tolType = "mean")


    # --- Regulatory Impact Factor Analysis [] ---
    # Key functions: RIF
    TFs_subset <- rownames(PCIT_input)[rownames(PCIT_input) %in% TFs]
    Target <- setdiff(rownames(PCIT_input), TFs_subset)
    RIF_input <- PCIT_input[c(Target, TFs_subset), ]
    RIF_out <- RIF(input = RIF_input,
                   nta = length(Target),
                   ntf = length(TFs_subset),
                   nSamples1 = 4,
                   nSamples2 = 4)


    # --- Integrated Analysis Pipeline [] ---
    # Key functions: runAnalysis
    out <- runAnalysis(mat = counts,
                       conditions = c("untrt", "trt"),
                       lfc = 5,
                       padj = 0.05,
                       TFs = TFs,
                       nSamples1 = 4,
                       nSamples2 = 4,
                       tolType = "mean",
                       diffMethod = "Reverter",
                       data.type = "counts")


    # --- Network and Diagnostic Visualisation [] ---
    # Key functions: histPlot, densityPlot, SmearPlot, netConditionsPlot
    histPlot(PCIT_out_trt$adj_sig)
    densityPlot(mat1 = PCIT_out_trt$adj_raw,
                mat2 = PCIT_out_trt$adj_sig,
                threshold = 0.5)
    SmearPlot(object = out,
              diffMethod = 'Reverter',
              lfc = 1.5,
              conditions = c('untrt', 'trt'),
              type = "DE")
    netConditionsPlot(out)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cetf_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cetf_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cetf_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CETF:", paste0("    cetf: ", packageVersion("CeTF"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cetf_results.csv
    touch ${prefix}_cetf_output.rds
    echo "BIOC_CETF:" > versions.yml
    echo "    cetf: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CETF_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CETF(ch_input)

    emit:
    results  = BIOC_CETF.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CETF.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CETF.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CETF.out.versions  // channel: path(versions.yml)
}
