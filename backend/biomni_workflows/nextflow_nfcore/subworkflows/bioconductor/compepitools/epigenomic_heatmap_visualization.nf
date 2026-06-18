#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: compEpiTools — epigenomic_heatmap_visualization
// Prepare and plot multi-track heatmaps of epigenomic data across genomic regions of interest, optionally scaling colors by statistical significance.
// Input: user_regions.RData, pvalues.txt
// Container: quay.io/biocontainers/bioconductor-compepitools:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, TxDb.Mmusculus.UCSC.mm9.knownGene, compEpiTools
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define reference genomic regions
//  * 2. [Visualization & Output] Prepare heatmap matrix data using heatmapData
//  * 3. [Visualization & Output] Plot standard heatmap using heatmapPlot
//  * 4. [Visualization & Output] Plot significance-dimmed heatmap using heatmapPlot with sigMat

nextflow.enable.dsl = 2

process BIOC_COMPEPITOOLS_EPIGENOMIC_HEATMAP_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("compEpiTools", "TxDb.Mmusculus.UCSC.mm9.knownGene", "GenomicRanges")
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
    
    # Load required libraries
    library(compEpiTools)
    library(TxDb.Mmusculus.UCSC.mm9.knownGene)
    library(GenomicRanges)
    
    # Set up annotation database
    txdb <- TxDb.Mmusculus.UCSC.mm9.knownGene
    
    # 1. Load User Inputs
    # Load GRanges object from user_regions.RData
    env <- new.env()
    load("user_regions.RData", envir = env)
    gr_name <- names(env)[sapply(env, function(x) is(x, "GRanges"))][1]
    if (is.na(gr_name)) {
      stop("No GRanges object found in user_regions.RData")
    }
    gr <- env[[gr_name]]
    
    # Load significance values from pvalues.txt
    pvals_input <- read.table("pvalues.txt", header = FALSE)
    pvalues_vec <- as.numeric(pvals_input[[1]])
    
    if (length(pvalues_vec) != length(gr)) {
      stop("The number of p-values in pvalues.txt must match the number of regions in user_regions.RData")
    }
    
    # 2. Define reference genomic regions
    extgr <- GRanges(seqnames(gr), ranges=IRanges(start(gr) - 1000, end(gr) + 1000))
    
    # 3. Prepare heatmap matrix data using heatmapData
    data <- heatmapData(grl=list(ChIPseq=gr), refgr=extgr, type='gr', nbins=20, txdb=txdb)
    
    # Format the significance matrix to match the tracks (ChIPseq + 2 annotation tracks)
    pvalues <- cbind(pvalues_vec, rep(0, length(gr)), rep(0, length(gr)))
    rownames(data[[1]][[1]]) <- paste(1:length(gr), signif(pvalues[,1],1), sep=' # ')
    
    # Save prepared heatmap data object
    saveRDS(data, "heatmap_data.rds")
    
    # 4. Plot standard heatmap using heatmapPlot
    pdf("heatmap_standard.pdf", width=8, height=10)
    heatmapPlot(matList=data[[1]], clusterInds=1:3)
    dev.off()
    
    # 5. Plot significance-dimmed heatmap using heatmapPlot with sigMat
    pdf("heatmap_significance.pdf", width=8, height=10)
    heatmapPlot(matList=data[[1]], sigMat=pvalues, clusterInds=1:3)
    dev.off()

    writeLines(c(
        '"BIOC_COMPEPITOOLS_EPIGENOMIC_HEATMAP_VISUALIZATION":',
        paste0('    compEpiTools: ', as.character(packageVersion('compEpiTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epigenomic_heatmap_visualization.csv versions.yml
    """
}

workflow BIOC_COMPEPITOOLS_EPIGENOMIC_HEATMAP_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ user_regions.RData, pvalues.txt ] ]

    main:
    BIOC_COMPEPITOOLS_EPIGENOMIC_HEATMAP_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_COMPEPITOOLS_EPIGENOMIC_HEATMAP_VISUALIZATION.out.tables
    plots    = BIOC_COMPEPITOOLS_EPIGENOMIC_HEATMAP_VISUALIZATION.out.plots
    objects  = BIOC_COMPEPITOOLS_EPIGENOMIC_HEATMAP_VISUALIZATION.out.objects
    versions = BIOC_COMPEPITOOLS_EPIGENOMIC_HEATMAP_VISUALIZATION.out.versions
}
