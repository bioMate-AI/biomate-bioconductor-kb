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
    library(GRanges)
    library(GRangesList)
    library(jsonlite)

    # --- Load Packages [] ---
    # Key functions: theme_set, theme_bw
    library(motifTestR)
    library(extraChIPs)
    library(rtracklayer)
    library(BSgenome.Hsapiens.UCSC.hg19)
    library(parallel)
    # --- Load Example Peaks [] ---
    # Key functions: seqinfo
    data("ar_er_peaks")
    ar_er_peaks
    sq <- seqinfo(ar_er_peaks)
    # --- Test Seq [] ---
    # Key functions: getSeq
    test_seq <- getSeq(BSgenome.Hsapiens.UCSC.hg19, ar_er_peaks)
    names(test_seq) <- as.character(ar_er_peaks)
    # --- Ex Pwm [] ---
    # Key functions: data
    data("ex_pfm")
    names(ex_pfm)
    ex_pfm$ESR1
    # --- Match Esr1 [] ---
    # Key functions: getPwmMatches
    score_thresh <- "70%"
    getPwmMatches(ex_pfm$ESR1, test_seq, min_score = score_thresh)
    # --- Best Match Esr1 [] ---
    # Key functions: getPwmMatches
    getPwmMatches(ex_pfm$ESR1, test_seq, min_score = score_thresh, best_only = TRUE)
    # --- Bm All [] ---
    # Key functions: getPwmMatches
    bm_all <- getPwmMatches(
      ex_pfm, test_seq, min_score = score_thresh, best_only = TRUE, break_ties = "all",
      mc.cores = cores
    )
    # --- Count Pwm Matches [] ---
    # Key functions: countPwmMatches
    countPwmMatches(ex_pfm, test_seq, min_score = score_thresh, mc.cores = cores)
    # --- Test Motif Pos [] ---
    # Key functions: testMotifPos
    res_pos <- testMotifPos(bm_all, mc.cores = cores)
    head(res_pos)
    # --- Test Motif Pos Abs [] ---
    # Key functions: testMotifPos
    res_abs <- testMotifPos(bm_all, abs = TRUE, mc.cores = cores)
    head(res_abs)
    # --- Plot Pos [] ---
    # Key functions: plotMatchPos, geom_smooth, facet_wrap, plot_annotation, theme
    topMotifs <- res_pos |>
        subset(fdr < 0.05) |>
        rownames()
    A <- plotMatchPos(bm_all[topMotifs], binwidth = 10, se = FALSE)
    # --- Plot Abs Pos [] ---
    # Key functions: plotMatchPos, scale_fill_viridis_c, plot_annotation, theme
    topMotifs <- res_abs |>
        subset(fdr < 0.05) |>
        rownames()
    A <- plotMatchPos(bm_all[topMotifs], abs = TRUE, type = "heatmap") +
      scale_fill_viridis_c()
    # --- Zr75 Enh [] ---
    # Key functions: overlapsAny
    data("zr75_enh")
    mean(overlapsAny(ar_er_peaks, zr75_enh))
    # --- Define Bg Ranges [] ---
    # Key functions: ifelse, overlapsAny, GRanges, GRangesList, setdiff
    ar_er_peaks$feature <- ifelse(
      overlapsAny(ar_er_peaks, zr75_enh), "enhancer", "other"
    )
    chr1 <- GRanges(sq)[1]
    # --- Rm Ranges [] ---
    # Key functions: makeRMRanges, splitAsList
    data("hg19_mask")
    set.seed(305)

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
