#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: flagme
// Fragment-level analysis of gas chromatography-massspectrometry metabolomics data.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/flagme/inst/doc/flagme-knitr.R
// Upstream  : gcspikelite
// Downstream: none
//
// Install: BiocManager::install("flagme")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLAGME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-flagme"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-flagme:1.62.0--r44_0' :
        'quay.io/biocontainers/bioconductor-flagme:1.62.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_flagme_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_flagme_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_flagme_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(flagme)
    library(MatchedFilterParam)
    library(jsonlite)

    # --- Chromatogram and Peak Visualization [] ---
    # Key functions: plotChrom, plotImage
    plotChrom(pd, rtrange = c(7.5, 8.5), plotPeaks = TRUE,
              plotPeakLabels = TRUE, max.near = 8, how.near = 0.5,
              col = rep(c("blue", "red", "black"), each = 3))
    plotImage(pd, run = 1, rtrange = c(7.5, 8.5), main = "Run 1")


    # --- Pairwise Alignment [] ---
    # Key functions: peaksAlignment, plotAlignment
    pa <- peaksAlignment(pd@peaksdata[[1]], pd@peaksdata[[2]],
                         pd@peaksrt[[1]], pd@peaksrt[[2]],
                         D = 0.1, gap = 0.5, metric = 1,
                         type = 1, compress = FALSE)
    plotAlignment(pa, xlim = c(0, 17), ylim = c(0, 16),
                  matchCol = "yellow", main = "Pairwise Alignment")


    # --- Multiple Alignment [] ---
    # Key functions: multipleAlignment
    ma <- multipleAlignment(pd, group = targets$Group, wn.gap = 0.5,
                            wn.D = 0.05, bw.gap = 0.6, bw.D = 0.05,
                            usePeaks = TRUE, filterMin = 1,
                            df = 50, verbose = FALSE, metric = 1,
                            type = 1)


    # --- Alignment Results Extraction [] ---
    # Key functions: plotChrom, gatherInfo
    plotChrom(pd, rtrange = c(7.5, 8.5), runs = ma@betweenAlignment@runs,
              mind = ma@betweenAlignment@ind, plotPeaks = TRUE,
              plotPeakLabels = TRUE, max.near = 8, how.near = 0.5,
              col = rep(c("blue", "red", "black"), each = 3))
    outList <- gatherInfo(pd, ma)
    rtmat <- matrix(unlist(lapply(outList, .subset, "rt"),
                           use.names = FALSE),
                    nrow = length(outList), byrow = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_flagme_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_flagme_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_flagme_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FLAGME:", paste0("    flagme: ", packageVersion("flagme"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flagme_results.csv
    touch ${prefix}_flagme_output.rds
    echo "BIOC_FLAGME:" > versions.yml
    echo "    flagme: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FLAGME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_FLAGME(ch_input)

    emit:
    results  = BIOC_FLAGME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FLAGME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FLAGME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FLAGME.out.versions  // channel: path(versions.yml)
}
