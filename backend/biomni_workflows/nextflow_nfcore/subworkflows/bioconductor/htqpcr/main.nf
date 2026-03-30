#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HTqPCR
// Analysis of Ct values from high throughput quantitative real-time PCR (qPCR) assays across multiple 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HTqPCR/inst/doc/HTqPCR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HTqPCR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HTQPCR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-htqpcr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor_docker:RELEASE_3_20' :
        'bioconductor/bioconductor_docker:RELEASE_3_20'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_htqpcr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_htqpcr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_htqpcr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Stangle)
    library(jsonlite)

    # --- Data import and loading [] ---
    # Key functions: data
    data(qPCRraw)
    data(qPCRpros)
    class(qPCRraw)
    # --- Quality control and filtering [] ---
    # Key functions: slotNames, phenoData, pData, frame, featureData, exprs, sample, plotCtVariation
    col <- rep(brewer.pal(6, "Spectral"), each=384)
    col2 <- brewer.pal(5, "Dark2")
    par(mfrow=c(3,2), mar=c(2,2,2,2))
    # All methods individually
    plot(exprs(raw), exprs(q.norm), pch=20, main="Quantile normalisation", col=col)
    # --- Seed analysis [] ---
    # Key functions: seed, Stangle, delim, path, readCtData, featureNames, plotCtOverview, plotCtCard
    q.norm <- normalizeCtData(raw.cat, norm="quantile")
    sr.norm <- normalizeCtData(raw.cat, norm="scale.rank")
    nr.norm <- normalizeCtData(raw.cat, norm="norm.rank")
    d.norm <- normalizeCtData(raw.cat, norm="deltaCt", deltaCt.genes=c("Gene1", "Gene60"))
    g.norm <- normalizeCtData(raw.cat, norm="geometric.mean")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_htqpcr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_htqpcr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_htqpcr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HTQPCR:", paste0("    htqpcr: ", packageVersion("HTqPCR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_htqpcr_results.csv
    touch ${prefix}_htqpcr_output.rds
    echo "BIOC_HTQPCR:" > versions.yml
    echo "    htqpcr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HTQPCR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HTQPCR(ch_input)

    emit:
    results  = BIOC_HTQPCR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HTQPCR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HTQPCR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HTQPCR.out.versions  // channel: path(versions.yml)
}
