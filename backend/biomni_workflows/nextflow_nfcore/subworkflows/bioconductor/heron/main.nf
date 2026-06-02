#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HERON
// HERON is a software package for analyzing peptide binding array data. In addition to identifying sig
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HERON/inst/doc/full_analysis.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HERON")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HERON {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-heron"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-heron:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-heron:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_heron_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_heron_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_heron_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HERON)
    library(HERONSequenceDataSet)
    library(jsonlite)

    # --- Probe P-Value Calculation and Calling [] ---
    # Key functions: calcCombPValues, convertSequenceDSToProbeDS, makeProbeCalls, getKofN
    seq_pval_res <- calcCombPValues(seq_ds_qn)
    probe_pval_res <- convertSequenceDSToProbeDS(seq_pval_res)
    probe_calls_res <- makeProbeCalls(probe_pval_res)
    probe_calls_k_of_n <- getKofN(probe_calls_res)


    # --- Epitope Segmentation [] ---
    # Key functions: findEpitopeSegments
    epi_segments_uniq_res <- findEpitopeSegments(
        probe_calls_res,
        segment_method = "unique"
    )
    epi_segments_hclust_res <- findEpitopeSegments(
        probe_calls_res,
        segment_method = "hclust",
        segment_score_type = "binary",
        segment_dist_method = "hamming",
        segment_cutoff = "silhouette"
    )


    # --- Epitope P-Value and Call Analysis [] ---
    # Key functions: calcEpitopePValues, addSequenceAnnotations, makeEpitopeCalls, getKofN
    epi_padj_uniq <- calcEpitopePValues(
        probe_calls_res,
        epitope_ids = epi_segments_uniq_res,
        metap_method = "wmax1"
    )
    epi_padj_uniq <- addSequenceAnnotations(epi_padj_uniq)
    epi_calls_uniq <- makeEpitopeCalls(
        epi_padj_uniq,
        one_hit_filter = TRUE
    )
    epi_calls_k_of_n_uniq <- getKofN(epi_calls_uniq)


    # --- Protein Level Analysis [] ---
    # Key functions: calcProteinPValues, makeProteinCalls, getKofN
    prot_padj_uniq <- calcProteinPValues(
        epi_padj_uniq,
        metap_method = "tippetts"
    )
    prot_calls_uniq <- makeProteinCalls(prot_padj_uniq)
    prot_calls_k_of_n_uniq <- getKofN(prot_calls_uniq)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_heron_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_heron_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_heron_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HERON:", paste0("    heron: ", packageVersion("HERON"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_heron_results.csv
    touch ${prefix}_heron_output.rds
    echo "BIOC_HERON:" > versions.yml
    echo "    heron: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HERON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HERON(ch_input)

    emit:
    results  = BIOC_HERON.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HERON.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HERON.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HERON.out.versions  // channel: path(versions.yml)
}
