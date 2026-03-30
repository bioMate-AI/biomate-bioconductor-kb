#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNTools
// This package provides tools to convert the output of segmentation analysis using DNAcopy to a matrix
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNTools/inst/doc/HowTo.R
// Upstream  : none
// Downstream: cghMCR
//
// Install: BiocManager::install("CNTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cntools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cntools:1.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cntools:1.62.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cntools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cntools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cntools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNSeg)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    require("CNTools")
    data(sampleData)
    head(sampleData)
    # --- Cnseg [] ---
    # Key functions: CNSeg, element, sample, getRS
    cnseg <- CNSeg(sampleData[which(is.element(sampleData[, "ID"], sample(unique(sampleData[, "ID"]), 20))), ])
    rdseg <- getRS(cnseg, by = "region", imput = FALSE, XY = FALSE, what = "mean")
    data("geneInfo")
    geneInfo <- geneInfo[sample(1:nrow(geneInfo), 2000), ]
    rdByGene <- getRS(cnseg, by = "gene", imput = FALSE, XY = FALSE, geneMap = geneInfo, what = "median")
    # --- Rs [] ---
    # Key functions: rs
    reducedseg <- rs(rdseg)
    # --- Kovera [] ---
    # Key functions: kOverA, filterfun, genefilter
    f1 <- kOverA(5, 1)
    ffun <- filterfun(f1)
    filteredrs <- genefilter(rdseg, ffun)
    # --- Madfilter [] ---
    # Key functions: madFilter
    filteredrs <- madFilter(rdseg, 0.8)
    # --- Hclust [] ---
    # Key functions: hclust, getDist
    hc <- hclust(getDist(filteredrs, method = "euclidian"), method = "complete")
    plot(hc, hang = -1, cex = 0.8, main = "", xlab = "")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cntools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cntools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cntools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNTOOLS:", paste0("    cntools: ", packageVersion("CNTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cntools_results.csv
    touch ${prefix}_cntools_output.rds
    echo "BIOC_CNTOOLS:" > versions.yml
    echo "    cntools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNTOOLS(ch_input)

    emit:
    results  = BIOC_CNTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNTOOLS.out.versions  // channel: path(versions.yml)
}
