#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GUIDEseq
// The package implements GUIDE-seq and PEtag-seq analysis workflow including functions for filtering U
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GUIDEseq/inst/doc/GUIDEseq.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("GUIDEseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GUIDESEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-guideseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-guideseq:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-guideseq:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_guideseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_guideseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_guideseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GUIDEseq)
    library(jsonlite)

    # --- Getuniquecleavageevents [] ---
    # Key functions: getUniqueCleavageEvents
    uniqueCleavageEvents <- getUniqueCleavageEvents(bamfile, umifile, n.cores.max =1)
    #uniqueCleavageEventsOld <- getUniqueCleavageEvents(bedfile, umifile)
    uniqueCleavageEvents$cleavage.gr
    # --- Getpeaks [] ---
    # Key functions: getPeaks
    peaks <- getPeaks(uniqueCleavageEvents$cleavage.gr, min.reads = 80)
    peaks.gr <- peaks$peaks
    peaks.gr
    # --- Mergeplusminuspeaks [] ---
    # Key functions: mergePlusMinusPeaks
    mergedPeaks <- mergePlusMinusPeaks(peaks.gr = peaks.gr,
        output.bedfile = "mergedPeaks.bed")
    mergedPeaks$mergedPeaks.gr
    head(mergedPeaks$mergedPeaks.bed)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_guideseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_guideseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_guideseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GUIDESEQ:", paste0("    guideseq: ", packageVersion("GUIDEseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_guideseq_results.csv
    touch ${prefix}_guideseq_output.rds
    echo "BIOC_GUIDESEQ:" > versions.yml
    echo "    guideseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GUIDESEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GUIDESEQ(ch_input)

    emit:
    results  = BIOC_GUIDESEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GUIDESEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GUIDESEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GUIDESEQ.out.versions  // channel: path(versions.yml)
}
