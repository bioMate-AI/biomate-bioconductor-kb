#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: karyoploteR
// karyoploteR creates karyotype plots of arbitrary genomes and offers a complete set of functions to p
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/karyoploteR/inst/doc/karyoploteR.R
// Upstream  : knitr, magrittr, regioneR
// Downstream: CopyNumberPlots
//
// Install: BiocManager::install("karyoploteR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KARYOPLOTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-karyoploter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-karyoploter:1.32.0--r44_0' :
        'quay.io/biocontainers/bioconductor-karyoploter:1.32.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_karyoploter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_karyoploter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_karyoploter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(karyoploteR)
    library(jsonlite)

    # --- Add Data to Plot [] ---
    # Key functions: toGRanges, frame, plotKaryotype, kpPlotRegions
    ---------------------------------------------------------------------
      gains <- toGRanges(data.frame(chr=c("chr1", "chr5", "chr17", "chr22"), start=c(1, 1000000, 4000000, 1),
                          end=c(5000000, 3200000, 80000000, 1200000)))
      losses <- toGRanges(data.frame(chr=c("chr3", "chr9", "chr17"), start=c(80000000, 20000000, 1),
                           end=c(170000000, 30000000, 25000000)))
    # --- Create Karyotype Plot [] ---
    # Key functions: plotKaryotype
    ---------------------------------------------------------------------
      kp <- plotKaryotype(genome="mm10", plot.type=1, main="The mm10 genome")
    # --- Create Random Regions [] ---
    # Key functions: createRandomRegions, toDataframe, runif
    ---------------------------------------------------------------------
      rand.data <- createRandomRegions(genome="hg19", nregions=1000, length.mean=1, length.sd=0,
                          mask=NA, non.overlapping=TRUE)
      rand.data <- toDataframe(sort(rand.data))
      rand.data <- cbind(rand.data, y=runif(n=1000, min=-1, max=1))
    # --- Create Karyotype Plot [] ---
    # Key functions: plotKaryotype, kpDataBackground, kpAxis, kpPoints, kpText, kpAbline, kpLines
    ---------------------------------------------------------------------
      kp <- plotKaryotype(genome="hg19", plot.type=2, chromosomes=c("chr1", "chr2", "chr3"))
      kpDataBackground(kp, data.panel = 1, r0=0, r1=0.45)
      kpAxis(kp, ymin=-1, ymax=1, r0=0.05, r1=0.4, col="gray50", cex=0.5)
      kpPoints(kp, chr=rand.data$chr, x=rand.data$start, y=rand.data$y,
    # --- Create Karyotype Plot [] ---
    # Key functions: plotKaryotype
    ---------------------------------------------------------------------
      kp <- plotKaryotype()
    # --- Create Karyotype Plot [] ---
    # Key functions: plotKaryotype, kpDataBackground
    ---------------------------------------------------------------------
      kp <- plotKaryotype(chromosomes = c("chr1", "chr2"), plot.type = 1)
      kpDataBackground(kp, data.panel = 1)
    # --- Create Karyotype Plot [] ---
    # Key functions: plotKaryotype, kpDataBackground, kpAxis
    ---------------------------------------------------------------------
      kp <- plotKaryotype(chromosomes=c("chr1", "chr2"), plot.type=2)
      #data.panel=1
      kpDataBackground(kp)
      #Default axis
    # --- Change Plotting Parameters [] ---
    # Key functions: plotDefaultPlotParams
    ---------------------------------------------------------------------
    plotDefaultPlotParams(plot.type=2)
    # --- Getdefaultplotparams [] ---
    # Key functions: getDefaultPlotParams, plotDefaultPlotParams
    ---------------------------------------------------------------------
    plot.params <- getDefaultPlotParams(plot.type=2)
    plot.params$ideogramheight <- 5
    plot.params$data2height <- 50
    plot.params$leftmargin <- 0.05
    # --- Zoom Plot [] ---
    # Key functions: frame, rnorm, plotKaryotype, kpDataBackground, kpAddBaseNumbers, kpPoints, rainbow
    ---------------------------------------------------------------------
      data.points <- data.frame(chr="chr1", pos=(1:240)*1e6, value=rnorm(240, 0.5, 0.1))
      kp <- plotKaryotype(plot.type = 4, chromosomes = "chr1")
      kpDataBackground(kp, data.panel = 1)
      kpAddBaseNumbers(kp)
    # --- Add Data to Plot [] ---
    # Key functions: toGRanges, frame, rnorm, plotKaryotype, kpDataBackground, kpAddBaseNumbers, kpPoints, rainbow
    ---------------------------------------------------------------------
      detail.region <- toGRanges(data.frame("chr1", 180e6, 240e6))
      data.points <- data.frame(chr="chr1", pos=(1:240)*1e6, value=rnorm(240, 0.5, 0.1))
      kp <- plotKaryotype(plot.type = 4, zoom=detail.region)
      kpDataBackground(kp, data.panel = 1)
    # --- Create Karyotype Plot [] ---
    # Key functions: plotKaryotype, kpDataBackground, kpAddBaseNumbers, kpPoints, kpArrows
    ---------------------------------------------------------------------
      kp <- plotKaryotype(plot.type = 4, chromosomes = "chr1")
      kpDataBackground(kp, data.panel = 1)
      kpAddBaseNumbers(kp)
      kpPoints(kp, chr = "chr1", x=180e6, y=0.5, pch=16, cex=8, col="#FAC67A", clipping=TRUE)
    # --- Add Data to Plot [] ---
    # Key functions: toGRanges, frame, plotKaryotype, kpDataBackground, kpAddBaseNumbers, kpPoints, kpArrows
    ---------------------------------------------------------------------
      detail.region <- toGRanges(data.frame("chr1", 135e6, 180e6))
      kp <- plotKaryotype(plot.type = 4, zoom = detail.region)
      kpDataBackground(kp, data.panel = 1)
      kpAddBaseNumbers(kp)
    # --- Create Karyotype Plot [] ---
    # Key functions: plotKaryotype, kpDataBackground, kpAxis, kpPoints, kpRect
    ---------------------------------------------------------------------
      kp <- plotKaryotype(chromosomes=c("chr1"))
      kpDataBackground(kp)
      kpAxis(kp)
      kpPoints(kp, chr="chr1", x=30000000, y=0.2)
    # --- Add Data to Plot [] ---
    # Key functions: toGRanges, frame, plotKaryotype, kpDataBackground, kpAxis, kpPoints, kpRect
    ---------------------------------------------------------------------
      dd <- toGRanges(data.frame(chr="chr1", start=30000000, end=30000000, y=0.2))
      dd2 <- toGRanges(data.frame(chr="chr1", start=100000000, end=120000000, y0=0.2, y1=0.4))
      kp <- plotKaryotype(chromosomes=c("chr1"))
      kpDataBackground(kp)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_karyoploter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_karyoploter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_karyoploter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KARYOPLOTER:", paste0("    karyoploter: ", packageVersion("karyoploteR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_karyoploter_results.csv
    touch ${prefix}_karyoploter_output.rds
    echo "BIOC_KARYOPLOTER:" > versions.yml
    echo "    karyoploter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KARYOPLOTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KARYOPLOTER(ch_input)

    emit:
    results  = BIOC_KARYOPLOTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KARYOPLOTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KARYOPLOTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KARYOPLOTER.out.versions  // channel: path(versions.yml)
}
