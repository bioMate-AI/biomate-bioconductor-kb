#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: INSPEcT
// INSPEcT (INference of Synthesis, Processing and dEgradation rates from Transcriptomic data) RNA-seq 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/INSPEcT/inst/doc/INSPEcT.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("INSPEcT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INSPECT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-inspect"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-inspect:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-inspect:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(deseqresults)

    output:
    tuple val(meta), path("${meta.id}_inspect_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_inspect_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_inspect_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(INSPEcT)
    library(jsonlite)

    # --- MA plot of DE results [] ---
    # Key functions: plotMA
    plotMA(diffrates, rate='synthesis', padj=1e-3)
    # --- QuantifyExpressionsFromBAMs analysis [] ---
    # Key functions: quantifyExpressionsFromBAMs, rep, newINSPEcT, inHeatmap, ratesFirstGuess, modelRates, plotGene, chisqmodel
    totalAnnTabPCR <- system.file(package = 'INSPEcT', 'totalAnnTabPCR.csv')
    nascentAnnTabPCR <- system.file(package = 'INSPEcT', 'nascentAnnTabPCR.csv')
    inspectFromPCR(totalAnnTabPCR, nascentAnnTabPCR, labeling_time=1/6,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_inspect_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_inspect_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_inspect_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INSPECT:", paste0("    inspect: ", packageVersion("INSPEcT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inspect_results.csv
    touch ${prefix}_inspect_output.rds
    echo "BIOC_INSPECT:" > versions.yml
    echo "    inspect: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INSPECT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqresults) ]

    main:
    BIOC_INSPECT(ch_input)

    emit:
    results  = BIOC_INSPECT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INSPECT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INSPECT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INSPECT.out.versions  // channel: path(versions.yml)
}
