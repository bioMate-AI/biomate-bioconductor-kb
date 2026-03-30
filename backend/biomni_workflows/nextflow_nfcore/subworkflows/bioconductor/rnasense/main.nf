#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RNAsense
// RNA-sense tool compares RNA-seq time curves in two experimental conditions, i.e. wild-type and mutan
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RNAsense/inst/doc/example.R
// Upstream  : SummarizedExperiment, ggplot2
// Downstream: none
//
// Install: BiocManager::install("RNAsense")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNASENSE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnasense"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnasense:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnasense:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rnasense_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnasense_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnasense_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RNAsense)
    library(jsonlite)

    # --- get F C [] ---
    # Key functions: getFC
    resultFC <- getFC(dataset = mydata,
    head(resultFC)
    # --- Custom ggplot2 visualization [] ---
    # Key functions: ggplot, aes, xlab
    library(ggplot2)
    ggplot(subset(resultFC, FCdetect!="none"),
    aes(x=logFoldChange, y=-log10(pValue), color=FCdetect)) +
    # --- get Switch [] ---
    # Key functions: getSwitch
    resultSwitch <- getSwitch(dataset = mydata,
    head(resultSwitch)
    # --- combine Results [] ---
    # Key functions: combineResults
    resultCombined <- combineResults(resultSwitch, resultFC)
    head(resultCombined)
    # --- plot S S G S [] ---
    # Key functions: plotSSGS
    plotSSGS(resultCombined, times[-length(times)])
    # --- output Gene Tables [] ---
    # Key functions: outputGeneTables
    outputGeneTables(resultCombined)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnasense_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnasense_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnasense_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNASENSE:", paste0("    rnasense: ", packageVersion("RNAsense"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnasense_results.csv
    touch ${prefix}_rnasense_output.rds
    echo "BIOC_RNASENSE:" > versions.yml
    echo "    rnasense: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNASENSE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RNASENSE(ch_input)

    emit:
    results  = BIOC_RNASENSE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNASENSE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNASENSE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNASENSE.out.versions  // channel: path(versions.yml)
}
