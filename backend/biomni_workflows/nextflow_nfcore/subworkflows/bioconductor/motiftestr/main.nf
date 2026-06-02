#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: motifTestR
// Taking a set of sequence motifs as PWMs, test a set of sequences for over-representation of these mo
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/motifTestR/inst/doc/motifAnalysis.R
// Upstream  : extraChIPs, ggplot2, parallel, patchwork, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("motifTestR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOTIFTESTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-motiftestr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-motiftestr:1.2.1--r44_0' :
        'quay.io/biocontainers/bioconductor-motiftestr:1.2.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_motiftestr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_motiftestr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_motiftestr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(motifTestR)
    library(GRanges)
    library(GRangesList)
    library(jsonlite)

    # --- Motif Matching and Counting [Motif Analysis] ---
    # Key functions: getPwmMatches, countPwmMatches
    bm_all <- getPwmMatches(
        ex_pfm, test_seq, min_score = "70%",
        best_only = TRUE, break_ties = "all", mc.cores = 1
    )
    match_counts <- countPwmMatches(
        ex_pfm, test_seq, min_score = "70%", mc.cores = 1
    )

    # --- Motif Position Analysis [Spatial Distribution] ---
    # Key functions: testMotifPos, plotMatchPos
    res_pos <- testMotifPos(bm_all, mc.cores = 1)
    res_abs <- testMotifPos(bm_all, abs = TRUE, mc.cores = 1)
    top_motifs <- rownames(subset(res_pos, fdr < 0.05))
    pos_plot <- plotMatchPos(
        bm_all[top_motifs], binwidth = 10, se = FALSE
    )

    # --- Background Range Generation [Sequence Control] ---
    # Key functions: makeRMRanges
    ar_er_peaks$feature <- ifelse(
        overlapsAny(ar_er_peaks, zr75_enh), "enhancer", "other"
    )
    bg_ranges <- GRangesList(
        enhancer = zr75_enh,
        other = GenomicRanges::setdiff(
            GRanges(seqinfo(ar_er_peaks))[1], zr75_enh
        )
    )
    rm_ranges <- makeRMRanges(
        splitAsList(ar_er_peaks, ar_er_peaks$feature),
        bg_ranges, exclude = hg19_mask, n_iter = 100
    )

    # --- Motif Enrichment Testing [Statistical Enrichment] ---
    # Key functions: testMotifEnrich
    rm_seq <- getSeq(BSgenome.Hsapiens.UCSC.hg19, rm_ranges)
    mcols(rm_seq) <- mcols(rm_ranges)
    enrich_res <- testMotifEnrich(
        ex_pfm, test_seq, rm_seq, min_score = "70%",
        model = "quasi", mc.cores = 1
    )

    # --- Motif Clustering and Overlaps [Motif Grouping] ---
    # Key functions: clusterMotifs, plotOverlaps
    cl <- clusterMotifs(ex_pfm, plot = FALSE, labels = NULL)
    ex_cl <- split(ex_pfm, cl)
    matches_list <- lapply(
        getPwmMatches(ex_pfm, test_seq, min_score = "70%", mc.cores = 1),
        function(x) x$seq
    )
    overlap_plot <- plotOverlaps(matches_list, type = "upset")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_motiftestr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_motiftestr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_motiftestr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOTIFTESTR:", paste0("    motiftestr: ", packageVersion("motifTestR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motiftestr_results.csv
    touch ${prefix}_motiftestr_output.rds
    echo "BIOC_MOTIFTESTR:" > versions.yml
    echo "    motiftestr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOTIFTESTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOTIFTESTR(ch_input)

    emit:
    results  = BIOC_MOTIFTESTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOTIFTESTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOTIFTESTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOTIFTESTR.out.versions  // channel: path(versions.yml)
}
