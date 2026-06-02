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

    # --- Creategraphminus1 [] ---
    # Key functions: chromPlot
    library("chromPlot")
    data(hg_gap)
    head(hg_gap)
    chromPlot(gaps=hg_gap)
    # --- Creategraph0 [] ---
    # Key functions: transcripts
    library("TxDb.Hsapiens.UCSC.hg19.knownGene")
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    library(GenomicFeatures)
    txgr <- transcripts(txdb)
    txgr
    # --- Creategraph0 Plot [] ---
    # Key functions: chromPlot
    chromPlot(gaps=hg_gap, annot1=txgr)
    # --- Creategraph1 [] ---
    # Key functions: data
    data(hg_cytoBandIdeo)
    head(hg_cytoBandIdeo)
    # --- Creategraph2 [] ---
    # Key functions: chromPlot
    chromPlot(bands=hg_cytoBandIdeo, gaps=hg_gap, chr=c("1", "2", "3", "4", "5",
    "6"), figCols=6)
    # --- Creategraph3 [] ---
    # Key functions: file
    data_file1       <- system.file("extdata", "hg19_refGeneChr19-21.txt",
    package = "chromPlot")
    refGeneHg        <- read.table(data_file1, sep="\t", header=TRUE,
    stringsAsFactors=FALSE)
    refGeneHg$Colors <- "red"
    # --- Creategraph4 [] ---
    # Key functions: chromPlot
    chromPlot(gaps=hg_gap, bands=refGeneHg, chr=c(19, 20, 21), figCols=3)
    # --- Creategraph5 [] ---
    # Key functions: ifelse
    data_file2 <- system.file("extdata", "Fst_CEU-YRI-W200Chr19-21.bed", package
    = "chromPlot")
    fst  <- read.table(data_file2, sep="\t", stringsAsFactors=FALSE, header=TRUE)
    head(fst)
    fst$Colors <-
    # --- Creategraph6 [] ---
    # Key functions: chromPlot
    chromPlot(gaps=hg_gap, chr=c(19, 20, 21), bands=fst, figCols=3)
    # --- Creategraph7 [] ---
    # Key functions: ifelse
    fst$Group <-
    # --- Creategraph8 [] ---
    # Key functions: chromPlot
    chromPlot(gaps=hg_gap, chr=c(19, 20, 21), bands=fst, figCols=3)
    # --- Creategraph9 [] ---
    # Key functions: file
    data_file3 <- system.file("extdata", "sinteny_Hg-mm10Chr19-21.txt", package =
    "chromPlot")
    sinteny    <- read.table(data_file3, sep="\t", stringsAsFactors=FALSE,
    header=TRUE)
    head(sinteny)
    # --- Creategraph10 [] ---
    # Key functions: chromPlot
    chromPlot(gaps=hg_gap, bands=sinteny, chr=c(19:21), figCols=3)
    # --- Creategraph12 [] ---
    # Key functions: chromPlot
    chromPlot(gaps=hg_gap, bands=hg_cytoBandIdeo, annot1=refGeneHg, chr=c(19:21),
    figCols=3)
    # --- Creategraph13 [] ---
    # Key functions: file
    data_file4 <-system.file("extdata", "mm10_refGeneChr2-11-17-19.txt", package= "chromPlot")
    ref_mm10   <-read.table(data_file4, sep="\t", stringsAsFactors=FALSE, header
    =TRUE)
    data_file5 <- system.file("extdata", "arrayChr17-19.txt", package = "chromPlot")
    array      <- read.table(data_file5, sep="\t", header=TRUE, stringsAsFactors=FALSE)

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
