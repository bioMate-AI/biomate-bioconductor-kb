#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: transcriptR
// The differences in the RNA types being sequenced have an impact on the resulting sequencing profiles
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/transcriptR/inst/doc/transcriptR.R
// Upstream  : GenomicFeatures
// Downstream: none
//
// Install: BiocManager::install("transcriptR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRANSCRIPTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-transcriptr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-transcriptr:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-transcriptr:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_transcriptr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_transcriptr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_transcriptr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(transcriptR)
    library(jsonlite)

    # --- Estimatebackground [] ---
    # Key functions: estimateBackground
    ---------------------------------------------------------------------
    estimateBackground(tds, fdr.cutoff = 0.01)
    # view estimated cutoff value
    tds
    # --- Seq [] ---
    # Key functions: estimateGapDistance
    ---------------------------------------------------------------------
    # create a range of gap distances to test
    # from 0 bp to 10000 bp with the step of 100 bp
    gd <- seq(from = 0, to = 10000, by = 100)
    # --- Detecttranscripts [] ---
    # Key functions: detectTranscripts
    ---------------------------------------------------------------------
    detectTranscripts(tds, estimate.params = TRUE)
    # --- Annotatetranscripts [] ---
    # Key functions: annotateTranscripts
    ---------------------------------------------------------------------
    annotateTranscripts(object = tds, annot = knownGene.genes, min.overlap = 0.5)
    # --- Gettranscripts [] ---
    # Key functions: getTranscripts
    ---------------------------------------------------------------------
    trx <- getTranscripts(tds, min.length = 250, min.fpkm = 0.5)
    head(trx, 5)
    # --- Getpeaks [] ---
    # Key functions: getPeaks
    ---------------------------------------------------------------------
    peaks <- getPeaks(cds)
    head(peaks, 3)
    # --- Breaktranscriptsbypeaks [] ---
    # Key functions: breakTranscriptsByPeaks, annotateTranscripts, getTranscripts
    ---------------------------------------------------------------------
    # set `estimate.params = TRUE` to re-calculate FPKM and coverage density
    breakTranscriptsByPeaks(tdsObj = tds, cdsObj = cds, estimate.params = TRUE)
    # re-annotate identified transcripts
    annotateTranscripts(object = tds, annot = knownGene.genes, min.overlap = 0.5)
    # --- Findoverlaps [] ---
    # Key functions: findOverlaps, queryHits
    ---------------------------------------------------------------------
    hits <- findOverlaps(query = trx, subject = trx.final)
    trx.broken <- trx[unique(queryHits(hits)[duplicated(queryHits(hits))])]
    head(trx.broken, 5)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_transcriptr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_transcriptr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_transcriptr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRANSCRIPTR:", paste0("    transcriptr: ", packageVersion("transcriptR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_transcriptr_results.csv
    touch ${prefix}_transcriptr_output.rds
    echo "BIOC_TRANSCRIPTR:" > versions.yml
    echo "    transcriptr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRANSCRIPTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRANSCRIPTR(ch_input)

    emit:
    results  = BIOC_TRANSCRIPTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRANSCRIPTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRANSCRIPTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRANSCRIPTR.out.versions  // channel: path(versions.yml)
}
