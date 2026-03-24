#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SLqPCR
// Functions for analysis of real-time quantitative PCR data at SIRS-Lab GmbH
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SLqPCR/inst/doc/SLqPCR.R
// Upstream  : RColorBrewer
// Downstream: none
//
// Install: BiocManager::install("SLqPCR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SLQPCR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-slqpcr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-slqpcr:1.72.0--r44_0' :
        'quay.io/biocontainers/bioconductor-slqpcr:1.72.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_slqpcr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_slqpcr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_slqpcr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SLqPCRdata)
    library(jsonlite)

    # --- Slqpcr [] ---
    # Key functions: data
    library(SLqPCR)
    data(vandesompele)
    str(vandesompele)
    # --- Fig2 [] ---
    # Key functions: factor, selectHKgenes
    tissue <- as.factor(c(rep("BM", 9), rep("POOL", 9), rep("FIB", 20), rep("LEU", 13), rep("NB", 34)))
    res.BM <- selectHKgenes(vandesompele[tissue == "BM",], method = "Vandesompele", geneSymbol = names(vandesompele), minNrHK = 2, trace = TRUE, na.rm = TRUE)
    res.POOL <- selectHKgenes(vandesompele[tissue == "POOL",], method = "Vandesompele", geneSymbol = names(vandesompele), minNrHK = 2, trace = FALSE, na.rm = TRUE)
    res.FIB <- selectHKgenes(vandesompele[tissue == "FIB",], method = "Vandesompele", geneSymbol = names(vandesompele), minNrHK = 2, trace = FALSE, na.rm = TRUE)
    res.LEU <- selectHKgenes(vandesompele[tissue == "LEU",], method = "Vandesompele", geneSymbol = names(vandesompele), minNrHK = 2, trace = FALSE, na.rm = TRUE)
    # --- Table3 [] ---
    # Key functions: frame
    ranks <- data.frame(c(1, 1:9), res.BM$ranking, res.POOL$ranking, res.FIB$ranking, res.LEU$ranking, res.NB$ranking)
    names(ranks) <- c("rank", "BM", "POOL", "FIB", "LEU", "NB")
    ranks
    # --- Fig2 [] ---
    # Key functions: pal, matplot
    library(RColorBrewer)
    mypalette <- brewer.pal(5, "Set1")
    matplot(cbind(res.BM$meanM, res.POOL$meanM, res.FIB$meanM, res.LEU$meanM, res.NB$meanM), type = "b", ylab = "Average expression stability M", xlab = "Number of remaining control genes", axes = FALSE, pch = 19, col = mypalette, ylim = c(0.2, 1.22), lty = 1, lwd = 2, main = "Gene stability measure")
    axis(1, at = 1:9, labels = as.character(10:2))
    axis(2, at = seq(0.2, 1.2, by = 0.2), labels = as.character(seq(0.2, 1.2, by = 0.2)))
    # --- pal [] ---
    # Key functions: pal
    mypalette <- brewer.pal(8, "YlGnBu")
    barplot(cbind(res.BM$variation, res.POOL$variation, res.FIB$variation, res.LEU$variation, res.NB$variation), beside = TRUE, col = mypalette, space = c(0, 2), names.arg = c("BM", "POOL", "FIB", "LEU", "NB"))
    legend("topright", legend = c("V9/10", "V8/9", "V7/8", "V6/7", "V5/6", "V4/5", "V3/4", "V2/3"), fill = mypalette, ncol = 2)
    abline(h = seq(0.05, 0.25, by = 0.05), lty = 2, col = "grey")
    abline(h = 0.15, lty = 1, col = "black")
    # --- Norm [] ---
    # Key functions: SLqPCRdata, geneStabM, normPCR
    data(SLqPCRdata)
    SLqPCRdata
    (relData <- apply(SLqPCRdata, 2, relQuantPCR, E = 2))
    geneStabM(relData[,c(3,4)])
    (exprData <- normPCR(SLqPCRdata, c(3,4)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_slqpcr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_slqpcr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_slqpcr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SLQPCR:", paste0("    slqpcr: ", packageVersion("SLqPCR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_slqpcr_results.csv
    touch ${prefix}_slqpcr_output.rds
    echo "BIOC_SLQPCR:" > versions.yml
    echo "    slqpcr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SLQPCR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SLQPCR(ch_input)

    emit:
    results  = BIOC_SLQPCR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SLQPCR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SLQPCR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SLQPCR.out.versions  // channel: path(versions.yml)
}
