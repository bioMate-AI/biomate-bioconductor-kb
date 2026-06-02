#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: groHMM
// A pipeline for the analysis of GRO-seq data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/groHMM/inst/doc/groHMM.R
// Upstream  : GenomicFeatures, edgeR
// Downstream: none
//
// Install: BiocManager::install("groHMM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GROHMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-grohmm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-grohmm:1.40.3--r44_0' :
        'quay.io/biocontainers/bioconductor-grohmm:1.40.3--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_grohmm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_grohmm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_grohmm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(groHMM)
    library(GRanges)
    library(IRanges)
    library(NROW)
    library(Position)
    library(jsonlite)

    # --- Read Alignment and Window Analysis [Quality Control] ---
    # Key functions: readBAM, windowAnalysis
    alignments <- readBAM(file = "groseq_alignments.bam")
    window_size <- 50
    windows <- windowAnalysis(
        reads = alignments,
        windowSize = window_size,
        stepSize = window_size
    )

    # --- HMM Training and Transcript Detection [De Novo Assembly] ---
    # Key functions: runHMM
    hmm_results <- runHMM(
        reads = alignments,
        LtProbB = -200,
        UTS = 5,
        size = 50
    )
    predicted_transcripts <- hmm_results$transcripts

    # --- Transcript Evaluation [Validation] ---
    # Key functions: evaluateHMM, getTxDensity
    evaluation <- evaluateHMM(
        txHMM = predicted_transcripts,
        annotation = reference_annotation
    )
    tx_density <- getTxDensity(
        txHMM = predicted_transcripts,
        conExpressed = reference_annotation,
        mc.cores = 1
    )

    # --- Transcription Limit Detection [Characterisation] ---
    # Key functions: limitDetect
    transcription_limits <- limitDetect(
        map = alignments,
        features = predicted_transcripts,
        limit = 0.5,
        mc.cores = 1
    )

    # --- Consensus Annotation Creation [Annotation] ---
    # Key functions: makeConsensusAnnotations
    annotations_list <- GRangesList(rep1 = tx_rep1, rep2 = tx_rep2)
    consensus_annotations <- makeConsensusAnnotations(
        exons = annotations_list,
        minOverlap = 100
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_grohmm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_grohmm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_grohmm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GROHMM:", paste0("    grohmm: ", packageVersion("groHMM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_grohmm_results.csv
    touch ${prefix}_grohmm_output.rds
    echo "BIOC_GROHMM:" > versions.yml
    echo "    grohmm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GROHMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GROHMM(ch_input)

    emit:
    results  = BIOC_GROHMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GROHMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GROHMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GROHMM.out.versions  // channel: path(versions.yml)
}
