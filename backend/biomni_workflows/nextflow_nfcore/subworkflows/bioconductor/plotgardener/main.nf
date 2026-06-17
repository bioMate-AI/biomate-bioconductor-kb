#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: plotgardener — quick_genomic_data_inspection
// Quickly visualize genomic data (Hi-C, signal tracks, genes, or GWAS) without page layout or placement arguments for rapid inspection.
// Input: IMR90_HiC_10kb, IMR90_ChIP_H3K27ac_signal, hg19_insulin_GWAS
// Container: quay.io/biocontainers/bioconductor-plotgardener:1.16.0--r45ha27e39d_0
// R packages: TxDb.Hsapiens.UCSC.hg19.knownGene, org.Hs.eg.db, plotgardener, plotgardenerdata
// Bioconductor: 3.20 | R: 4.4
// Requires: TxDb.Hsapiens.UCSC.hg19.knownGene, org.Hs.eg.db, plotgardener
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the required libraries and data
//  * 2. [Visualization & Output] Quick plot Hi-C data using plotHicSquare()
//  * 3. [Visualization & Output] Quick plot signal data using plotSignal()
//  * 4. [Visualization & Output] Quick plot gene annotations using plotGenes()
//  * 5. [Visualization & Output] Quick plot GWAS Manhattan data using plotManhattan()

nextflow.enable.dsl = 2

process BIOC_PLOTGARDENER_QUICK_GENOMIC_DATA_INSPECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("TxDb.Hsapiens.UCSC.hg19.knownGene", "org.Hs.eg.db", "plotgardener", "plotgardenerdata")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # 1. Load the required libraries and data
    library(plotgardener)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(org.Hs.eg.db)
    
    # Helper function to load user input files from the working directory
    load_input <- function(filename) {
        if (file.exists(filename)) {
            return(readRDS(filename))
        } else if (file.exists(paste0(filename, ".rds"))) {
            return(readRDS(paste0(filename, ".rds")))
        } else {
            stop(paste("Required input file not found:", filename))
        }
    }
    
    # Read the declared user input files
    IMR90_HiC_10kb <- load_input("IMR90_HiC_10kb")
    IMR90_ChIP_H3K27ac_signal <- load_input("IMR90_ChIP_H3K27ac_signal")
    hg19_insulin_GWAS <- load_input("hg19_insulin_GWAS")
    
    # 2. Quick plot Hi-C data using plotHicSquare()
    pdf("hic_quickplot.pdf", width = 6, height = 6)
    plotHicSquare(
        data = IMR90_HiC_10kb,
        chrom = "chr21", chromstart = 28000000, chromend = 30300000,
        assembly = "hg19"
    )
    dev.off()
    
    # 3. Quick plot signal data using plotSignal()
    pdf("signal_quickplot.pdf", width = 6, height = 3)
    plotSignal(
        data = IMR90_ChIP_H3K27ac_signal,
        chrom = "chr21", chromstart = 28000000, chromend = 30300000,
        assembly = "hg19"
    )
    dev.off()
    
    # 4. Quick plot gene annotations using plotGenes()
    pdf("genes_quickplot.pdf", width = 6, height = 3)
    plotGenes(
        assembly = "hg19",
        chrom = "chr21", chromstart = 28000000, chromend = 30300000
    )
    dev.off()
    
    # 5. Quick plot GWAS Manhattan data using plotManhattan()
    pdf("gwas_quickplot.pdf", width = 6, height = 4)
    plotManhattan(
        data = hg19_insulin_GWAS, 
        assembly = "hg19",
        fill = c("steel blue", "grey"),
        ymax = 1.1, cex = 0.20
    )
    dev.off()

    writeLines(c(
        '"BIOC_PLOTGARDENER_QUICK_GENOMIC_DATA_INSPECTION":',
        paste0('    plotgardener: ', as.character(packageVersion('plotgardener')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quick_genomic_data_inspection.csv versions.yml
    """
}

workflow BIOC_PLOTGARDENER_QUICK_GENOMIC_DATA_INSPECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ IMR90_HiC_10kb, IMR90_ChIP_H3K27ac_signal, hg19_insulin_GWAS ] ]

    main:
    BIOC_PLOTGARDENER_QUICK_GENOMIC_DATA_INSPECTION(ch_input)

    emit:
    tables   = BIOC_PLOTGARDENER_QUICK_GENOMIC_DATA_INSPECTION.out.tables
    plots    = BIOC_PLOTGARDENER_QUICK_GENOMIC_DATA_INSPECTION.out.plots
    objects  = BIOC_PLOTGARDENER_QUICK_GENOMIC_DATA_INSPECTION.out.objects
    versions = BIOC_PLOTGARDENER_QUICK_GENOMIC_DATA_INSPECTION.out.versions
}
