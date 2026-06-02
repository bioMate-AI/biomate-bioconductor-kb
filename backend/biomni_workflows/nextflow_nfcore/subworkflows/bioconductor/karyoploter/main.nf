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

    # --- Plotting Genomic Regions [] ---
    # Key functions: kpPlotRegions, kpDataBackground
    gains <- toGRanges(data.frame(
        chr=c("chr1", "chr5", "chr17", "chr22"),
        start=c(1, 1000000, 4000000, 1),
        end=c(5000000, 3200000, 80000000, 1200000)
    ))
    kp <- plotKaryotype(genome="hg19")
    kpDataBackground(kp, data.panel = 1)
    kpPlotRegions(kp, gains, col="#FFAACC")


    # --- Custom Data Tracks [] ---
    # Key functions: kpAxis, kpPoints, kpLines
    rand_data <- createRandomRegions(
        genome="hg19", nregions=100, length.mean=1,
        length.sd=0, mask=NA, non.overlapping=TRUE
    )
    rand_df <- toDataframe(sort(rand_data))
    rand_df$y <- runif(n=100, min=-1, max=1)
    kp <- plotKaryotype(genome="hg19", chromosomes="chr1")
    kpAxis(kp, ymin=-1, ymax=1, r0=0.05, r1=0.4)
    kpPoints(
        kp, chr=rand_df$chr, x=rand_df$start, y=rand_df$y,
        ymin=-1, ymax=1, r0=0.05, r1=0.4, col="black"
    )
    kpLines(
        kp, chr=rand_df$chr, x=rand_df$start, y=rand_df$y,
        ymin=-1, ymax=1, r0=0.5, r1=1, col="blue"
    )


    # --- Advanced Custom Tracks [] ---
    # Key functions: kpBars, kpSegments, kpAbline
    kp <- plotKaryotype(genome="hg19", chromosomes="chr1")
    kpAbline(kp, h=0, col="gray", ymin=-1, ymax=1, r0=0, r1=0.5)
    kpBars(
        kp, chr=rand_df$chr, x0=rand_df$start, x1=rand_df$end,
        y1=rand_df$y, col="#AADDAA", ymin=-1, ymax=1, r0=0, r1=0.5
    )
    kpSegments(
        kp, chr=rand_df$chr, x0=rand_df$start, x1=rand_df$end,
        y0=rand_df$y-0.2, y1=rand_df$y, col="red",
        ymin=-1, ymax=1, r0=0.5, r1=1
    )

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
