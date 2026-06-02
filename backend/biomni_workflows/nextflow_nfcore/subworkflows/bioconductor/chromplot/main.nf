#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: chromPlot
// Package designed to visualize genomic data along the chromosomes, where the vertical chromosomes are
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/chromPlot/inst/doc/chromPlot.R
// Upstream  : GenomicFeatures, qtl
// Downstream: none
//
// Install: BiocManager::install("chromPlot")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHROMPLOT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chromplot"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chromplot:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chromplot:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chromplot_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chromplot_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chromplot_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(chromPlot)
    library(jsonlite)

    # --- Genomic Annotation Mapping [] ---
    # Key functions: chromPlot
    data(hg_gap)
    data_file1 <- system.file(
        "extdata", "hg19_refGeneChr19-21.txt",
        package = "chromPlot"
    )
    refGeneHg <- read.table(
        data_file1, sep = "\t", header = TRUE,
        stringsAsFactors = FALSE
    )
    refGeneHg$Colors <- "red"
    chromPlot(
        gaps = hg_gap,
        bands = refGeneHg,
        chr = c(19, 20, 21),
        figCols = 3
    )


    # --- Multi-Track Genomic Feature Visualization [] ---
    # Key functions: chromPlot
    data(mm10_gap)
    data(mm10_cytoBandIdeo)
    data_file4 <- system.file(
        "extdata", "mm10_refGeneChr2-11-17-19.txt",
        package = "chromPlot"
    )
    ref_mm10 <- read.table(
        data_file4, sep = "\t", stringsAsFactors = FALSE,
        header = TRUE
    )
    data_file5 <- system.file(
        "extdata", "arrayChr17-19.txt",
        package = "chromPlot"
    )
    array <- read.table(
        data_file5, sep = "\t", header = TRUE,
        stringsAsFactors = FALSE
    )
    chromPlot(
        gaps = mm10_gap,
        bands = mm10_cytoBandIdeo,
        annot1 = ref_mm10,
        annot2 = array,
        chr = c("17", "18", "19"),
        figCols = 3
    )


    # --- Statistical Data Plotting [] ---
    # Key functions: chromPlot
    data(hg_gap)
    data(hg_cytoBandIdeo)
    data_file2 <- system.file(
        "extdata", "Fst_CEU-YRI-W200Chr19-21.bed",
        package = "chromPlot"
    )
    fst <- read.table(
        data_file2, sep = "\t", stringsAsFactors = FALSE,
        header = TRUE
    )
    chromPlot(
        bands = hg_cytoBandIdeo,
        gaps = hg_gap,
        stat = fst,
        statCol = "win.FST",
        statName = "win.FST",
        statTyp = "p",
        chr = c(19:21),
        figCols = 3,
        statSumm = "mean"
    )


    # --- QTL Mapping Integration [] ---
    # Key functions: chromPlot
    data(mm10_gap)
    data(mm10_cytoBandIdeo)
    data_file4 <- system.file(
        "extdata", "mm10_refGeneChr2-11-17-19.txt",
        package = "chromPlot"
    )
    ref_mm10 <- read.table(
        data_file4, sep = "\t", stringsAsFactors = FALSE,
        header = TRUE
    )
    QTLs <- data.frame(
        Chrom = c(2, 17, 18),
        Start = c(1000000, 2000000, 3000000),
        End = c(1500000, 2500000, 3500000),
        LOD = c(3.5, 4.2, 2.1)
    )
    chromPlot(
        gaps = mm10_gap,
        bands = mm10_cytoBandIdeo,
        annot1 = ref_mm10,
        stat = QTLs,
        statCol = "LOD",
        statTyp = "l",
        chr = c(2, 17, 18),
        figCols = 3
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chromplot_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chromplot_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chromplot_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHROMPLOT:", paste0("    chromplot: ", packageVersion("chromPlot"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromplot_results.csv
    touch ${prefix}_chromplot_output.rds
    echo "BIOC_CHROMPLOT:" > versions.yml
    echo "    chromplot: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHROMPLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHROMPLOT(ch_input)

    emit:
    results  = BIOC_CHROMPLOT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHROMPLOT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHROMPLOT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHROMPLOT.out.versions  // channel: path(versions.yml)
}
