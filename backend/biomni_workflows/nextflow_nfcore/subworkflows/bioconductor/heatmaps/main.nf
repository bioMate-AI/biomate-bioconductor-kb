#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: heatmaps
// This package provides functions for plotting heatmaps of genome-wide data across genomic intervals, 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/heatmaps/inst/doc/heatmaps.R
// Upstream  : rtracklayer, GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("heatmaps")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HEATMAPS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-heatmaps"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-heatmaps:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-heatmaps:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_heatmaps_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_heatmaps_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_heatmaps_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(heatmaps)
    library(jsonlite)


    # --- Data 1 [] ---
    # Key functions: function, import, heatmaps_file, seqinfo, readRDS, extdata, heatmaps, H3K4me3_30p_pos.rds
    library(rtracklayer)
    library(GenomicRanges)
    library(BSgenome.Drerio.UCSC.danRer7)

    heatmaps_file = function(fn) system.file("extdata", fn, package="heatmaps")

    zf_30p_promoters = import(heatmaps_file("30pEpi_proms.bed"), genome=seqinfo(Drerio))

    h3k4me3_30p_pos = readRDS(heatmaps_file("H3K4me3_30p_pos.rds"))
    h3k4me3_30p_neg = readRDS(heatmaps_file("H3K4me3_30p_neg.rds"))
    coords=c(-500, 500)

    windows_30p = promoters(zf_30p_promoters, -coords[1], coords[2])
    windows_30p = windows_30p[width(trim(windows_30p)) == 1000]
    h3k4me3_30p_heatmap = CoverageHeatmap(
        windows_30p,
        h3k4me3_30p,
        coords=coords,
        label="H3K4me3 30p")
    plotHeatmapList(h3k4me3_30p_heatmap, cex.label=1, color="Greens")

    # --- Plot Meta [] ---
    # Key functions: plotHeatmapMeta, CoverageHeatmap, scale, plotHeatmapList, red, white, blue, kmeans
    plotHeatmapMeta(h3k4me3_30p_heatmap)
    h3k4me3_30p_subtracted = h3k4me3_30p_pos - h3k4me3_30p_neg

    h3k4me3_30p_subtracted_hm = CoverageHeatmap(
        windows_30p,
        h3k4me3_30p_subtracted,
        coords=coords,
        label="Phase")

    scale(h3k4me3_30p_subtracted_hm) = c(-150, 150)

    raw_matrix = image(h3k4me3_30p_subtracted_hm)
    clusters = kmeans(raw_matrix, 2)$cluster

    mat = raw_matrix[order(clusters),]

    # --- Get Seq [] ---
    # Key functions: getSeq, PatternHeatmap, plotHeatmapList, smoothHeatmap, kernel
    seq_30p = getSeq(Drerio, windows_30p)
    ta_30p = PatternHeatmap(seq_30p, "TA", coords=coords)
    plotHeatmapList(ta_30p)
    ta_30p_smoothed = smoothHeatmap(ta_30p, output.size=c(250, 500), algorithm="kernel")
    plotHeatmapList(ta_30p_smoothed)

    # --- Pwm Pattern Hm [] ---
    # Key functions: PatternHeatmap, plotHeatmapList, smoothHeatmap, tata_pwm, PWMScanHeatmap, scale, blur
    example_data = new.env()
    data(HeatmapExamples, envir=example_data)
    tata_pwm = get("tata_pwm", example_data)

    tata_pwm_30p = PatternHeatmap(seq_30p, tata_pwm, coords=coords, label="TATA", min.score="60%")
    plotHeatmapList(smoothHeatmap(tata_pwm_30p, output.size=c(250, 500)))
    tata_pwm_scan_30p = PWMScanHeatmap(seq_30p, tata_pwm, coords=coords, label="TATA")
    tata_pwm_scan_30p_smoothed = smoothHeatmap(tata_pwm_scan_30p, algorithm="blur", output.size=c(250, 500))
    scale(tata_pwm_scan_30p_smoothed) = c(40, 60)
    plotHeatmapList(tata_pwm_scan_30p_smoothed, color="Spectral", legend=TRUE, legend.width=0.3)
    cg_30p = PatternHeatmap(seq_30p, "CG", coords=coords)
    cg_30p_smoothed = smoothHeatmap(cg_30p, output.size=c(250, 500))

    hm_list = list(
        ta_30p_smoothed,
        cg_30p_smoothed,
        tata_pwm_scan_30p_smoothed,
        smoothHeatmap(h3k4me3_30p_heatmap, output.size=c(250, 500))
    )

    # --- Complex Data [] ---
    # Key functions: import, heatmaps_file, seqinfo, promoters, width, trim, getSeq, function
    zf_24h_promoters = import(heatmaps_file("24h_proms.bed"), genome=seqinfo(Drerio))
    windows_24h = promoters(zf_24h_promoters, 500, 500)
    windows_24h = windows_24h[width(trim(windows_24h)) == 1000]
    seq_24h = getSeq(Drerio, windows_24h)
    seq_30p = rev(seq_30p)
    seq_24h = rev(seq_24h)
    SmoothPatternHM = function(seq, pattern, ...) {
        hm = PatternHeatmap(seq, pattern, ...)
        smoothHeatmap(hm, output.size=c(200, 200))
    }

    # --- Complex Opts [] ---
    # Key functions: heatmapOptions, white, layout, par, plot_legend, plotHeatmap, mtext, CTSS
    upperOpts = heatmapOptions(
        label.col="white",
        x.ticks=FALSE
    )

    lowerOpts = heatmapOptions(
        cex.axis=1.5
    )
    margins = list(
        topleft = c(0.1, 0.3, 1, 0.2),
        topright = c(0.1, 0.2, 1, 0.3),
        bottomleft = c(1, 0.3, 0.1, 0.2),
        bottomright = c(1, 0.2, 0.1, 0.3)
    )
    layout(matrix(c(1:3, 1, 4, 5), nrow=2, byrow=TRUE), width=c(0.25, 1, 1))

    par(mai=c(3, 0.7, 3, 0.05))
    plot_legend(scale, options=upperOpts)

    par(mai=margins$topleft)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_heatmaps_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_heatmaps_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_heatmaps_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HEATMAPS:", paste0("    heatmaps: ", packageVersion("heatmaps"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_heatmaps_results.csv
    touch ${prefix}_heatmaps_output.rds
    echo "BIOC_HEATMAPS:" > versions.yml
    echo "    heatmaps: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HEATMAPS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HEATMAPS(ch_input)

    emit:
    results  = BIOC_HEATMAPS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HEATMAPS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HEATMAPS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HEATMAPS.out.versions  // channel: path(versions.yml)
}
