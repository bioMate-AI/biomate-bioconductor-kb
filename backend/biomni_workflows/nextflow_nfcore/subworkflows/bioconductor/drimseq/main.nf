#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DRIMSeq
// The package provides two frameworks. One for the differential transcript usage analysis between diff
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DRIMSeq/inst/doc/DRIMSeq.R
// Upstream  : GeuvadisTranscriptExpr, PasillaTranscriptExpr, ggplot2, knitr, stageR
// Downstream: rnaseqDTU
//
// Install: BiocManager::install("DRIMSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DRIMSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-drimseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-drimseq:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-drimseq:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_drimseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_drimseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_drimseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DRIMSeq)
    library(jsonlite)

    # --- Extract differential expression results [] ---
    # Key functions: results, plotProportions, stageRTx, stageWiseAdjustment, getSignificantGenes
    res2 <- results(d2)
    res2 <- res2[order(res2$pvalue, decreasing = FALSE), ]
    ggp <- plotProportions(d2, gene_id = top_gene_id2, group_variable = "group")
    # --- News analysis [] ---
    # Key functions: news, dmDSdata, dmFilter, dmPrecision, common_precision, plotPrecision, dmFit, dmTest
    pasilla_samples2 <- data.frame(sample_id = pasilla_metadata$SampleName,
    d2 <- dmDSdata(counts = pasilla_counts, samples = pasilla_samples2)
    d2 <- d2[names(d2) %in% gene_id_subset, ]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_drimseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_drimseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_drimseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DRIMSEQ:", paste0("    drimseq: ", packageVersion("DRIMSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_drimseq_results.csv
    touch ${prefix}_drimseq_output.rds
    echo "BIOC_DRIMSEQ:" > versions.yml
    echo "    drimseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DRIMSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_DRIMSEQ(ch_input)

    emit:
    results  = BIOC_DRIMSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DRIMSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DRIMSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DRIMSEQ.out.versions  // channel: path(versions.yml)
}
