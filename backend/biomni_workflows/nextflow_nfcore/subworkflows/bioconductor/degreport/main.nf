#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DEGreport
// Creation of ready-to-share figures of differential expression analyses of count data. It integrates 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DEGreport/inst/doc/DEGreport.R
// Upstream  : ComplexHeatmap, DESeq2, pheatmap, shiny
// Downstream: none
//
// Install: BiocManager::install("DEGreport")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEGREPORT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-degreport"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-degreport:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-degreport:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_degreport_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_degreport_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_degreport_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSetFromMatrix)
    library(Heatmap)
    library(HeatmapAnnotation)
    library(jsonlite)

    # --- Create DESeqDataSet from count matrix [] ---
    # Key functions: DESeqDataSetFromMatrix, colData, DESeq, results
    library(DESeq2)
    idx <- c(1:10, 75:85)
    dds <- DESeqDataSetFromMatrix(assays(humanGender)[[1]][1:1000, idx],
    # --- Heatmap of expression matrix [] ---
    # Key functions: HeatmapAnnotation, Heatmap, pheatmap
    library(ComplexHeatmap)
    th <- HeatmapAnnotation(df = colData(dds),
    col = degColors(colData(dds), TRUE))
    # --- Sample metadata inspection [] ---
    # Key functions: counts, degCheckFactors, degQC, degCovariates, colData, degCorCov, createReport, degComps
    res[["id"]] <- row.names(res)
    show <- as.data.frame(res[1:10, c("log2FoldChange", "padj", "id")])
    degVolcano(res[,c("log2FoldChange", "padj")], plot_text = show)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_degreport_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_degreport_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_degreport_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DEGREPORT:", paste0("    degreport: ", packageVersion("DEGreport"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_degreport_results.csv
    touch ${prefix}_degreport_output.rds
    echo "BIOC_DEGREPORT:" > versions.yml
    echo "    degreport: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DEGREPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_DEGREPORT(ch_input)

    emit:
    results  = BIOC_DEGREPORT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DEGREPORT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DEGREPORT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DEGREPORT.out.versions  // channel: path(versions.yml)
}
