#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EnhancedVolcano
// Volcano plots represent a useful way to visualise the results of differential expression analyses. H
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EnhancedVolcano/inst/doc/EnhancedVolcano.R
// Upstream  : DESeq2, airway, grid, gridExtra, magrittr
// Downstream: none
//
// Install: BiocManager::install("EnhancedVolcano")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ENHANCEDVOLCANO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-enhancedvolcano"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-enhancedvolcano:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-enhancedvolcano:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_enhancedvolcano_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_enhancedvolcano_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_enhancedvolcano_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSet)
    library(DESeqDataSetFromMatrix)
    library(EnhancedVolcano)
    library(jsonlite)

    # --- Customized Volcano Plot with Connectors [] ---
    # Key functions: EnhancedVolcano
    EnhancedVolcano(
        res,
        lab = rownames(res),
        x = "log2FoldChange",
        y = "pvalue",
        selectLab = c("VCAM1", "KCTD12", "ADAM12", "CXCL12"),
        xlab = bquote(~Log[2]~ "fold change"),
        pCutoff = 10e-14,
        FCcutoff = 2.0,
        pointSize = 4.0,
        labSize = 6.0,
        boxedLabels = TRUE,
        drawConnectors = TRUE,
        widthConnectors = 1.0,
        colConnectors = "black"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_enhancedvolcano_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_enhancedvolcano_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_enhancedvolcano_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ENHANCEDVOLCANO:", paste0("    enhancedvolcano: ", packageVersion("EnhancedVolcano"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enhancedvolcano_results.csv
    touch ${prefix}_enhancedvolcano_output.rds
    echo "BIOC_ENHANCEDVOLCANO:" > versions.yml
    echo "    enhancedvolcano: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ENHANCEDVOLCANO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_ENHANCEDVOLCANO(ch_input)

    emit:
    results  = BIOC_ENHANCEDVOLCANO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ENHANCEDVOLCANO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ENHANCEDVOLCANO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ENHANCEDVOLCANO.out.versions  // channel: path(versions.yml)
}
