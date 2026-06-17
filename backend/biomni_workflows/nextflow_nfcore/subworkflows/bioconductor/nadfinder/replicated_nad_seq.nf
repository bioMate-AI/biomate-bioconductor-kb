#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: NADfinder — replicated_nad_seq
// Identify nucleolar-associated domains (NADs) from multiple biological replicates of nucleolus-associated DNA and genomic DNA sequencing samples.
// Input: bamFiles, Mmusculus, ideo.mm10.rds
// Container: quay.io/biocontainers/bioconductor-nadfinder:1.34.0--r45hdfd78af_0
// R packages: BSgenome.Mmusculus.UCSC.mm10, NADfinder
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Mmusculus.UCSC.mm10, NADfinder, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Calculate read counts in sliding windows across the genome using tileCount
//  * 2. [Core Analysis] Compute log2 ratios of nucleolus vs. genomic DNA across replicates using log2se
//  * 3. [Core Analysis] Perform chromosome-specific background correction and smoothing using smoothRatiosByChromosome
//  * 4. [Core Analysis] Assess sample quality using cumulativePercentage
//  * 5. [Core Analysis] Call peaks using callPeaks, which utilizes limma for statistical significance across replicates
//  * 6. [Visualization & Output] Visualize the called peaks along the chromosome ideogram using plotSig

nextflow.enable.dsl = 2

process BIOC_NADFINDER_REPLICATED_NAD_SEQ {
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
    .bm_deps <- c("BSgenome.Mmusculus.UCSC.mm10", "NADfinder")
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
        library(NADfinder)
        library(BSgenome.Mmusculus.UCSC.mm10)
        
        # 1. Calculate read counts in sliding windows across the genome using tileCount
        # Read BAM files from the working directory
        bamFiles <- list.files(path = ".", pattern = "\\\\.bam\$", full.names = FALSE)
        if (length(bamFiles) == 0) {
          stop("Error: No BAM files found in the working directory.")
        }
        
        ws <- 50000
        step <- 5000
        
        # Run tileCount using the user-provided BAM files and BSgenome object
        se <- tileCount(reads = bamFiles, genome = Mmusculus, windowSize = ws, step = step)
        
        # 2. Compute log2 ratios of nucleolus vs. genomic DNA across replicates using log2se
        # Identify nucleolus and genomic columns from the BAM filenames
        nucleolusCols <- grep("nucleolus|(^|[^a-zA-Z])N([^a-zA-Z]|\$)", bamFiles, ignore.case = TRUE, value = TRUE)
        genomeCols <- grep("genomic|input|control|(^|[^a-zA-Z])G([^a-zA-Z]|\$)", bamFiles, ignore.case = TRUE, value = TRUE)
        
        # Fallback if naming convention is different
        if (length(nucleolusCols) == 0 || length(genomeCols) == 0) {
          half <- length(bamFiles) %/% 2
          nucleolusCols <- bamFiles[1:half]
          genomeCols <- bamFiles[(half + 1):length(bamFiles)]
        }
        
        se <- log2se(se, 
                     nucleolusCols = nucleolusCols, 
                     genomeCols = genomeCols, 
                     transformation = "log2CPMRatio")
        
        # 3. Perform chromosome-specific background correction and smoothing using smoothRatiosByChromosome
        # Determine target chromosome (default to chr18 as in documented workflow, fallback to first available)
        available_chrs <- seqlevels(se)
        target_chr <- if ("chr18" %in% available_chrs) "chr18" else available_chrs[1]
        
        seList <- smoothRatiosByChromosome(se, chr = target_chr)
        
        # 4. Assess sample quality using cumulativePercentage
        pdf("cumulative_percentage_plot.pdf", width = 6, height = 6)
        cumulativePercentage(seList[[target_chr]])
        dev.off()
        
        # 5. Call peaks using callPeaks
        peaks <- lapply(seList, callPeaks, cutoffAdjPvalue = 0.05, countFilter = 1)
        peaks <- unlist(GRangesList(peaks))
        
        # Save called peaks to output files
        write.csv(as.data.frame(unname(peaks)), "peaklist.csv", row.names = FALSE)
        saveRDS(peaks, "peaks.rds")
        
        # 6. Visualize the called peaks along the chromosome ideogram using plotSig
        ideo <- readRDS("ideo.mm10.rds")
        
        pdf("peaks_ideogram_plot.pdf", width = 10, height = 4)
        plotSig(ideo = ideo, 
                grList = GRangesList(peaks), 
                mcolName = "AveSig", 
                layout = list(target_chr), 
                parameterList = list(types = "heatmap"))
        dev.off()

    writeLines(c(
        '"BIOC_NADFINDER_REPLICATED_NAD_SEQ":',
        paste0('    NADfinder: ', as.character(packageVersion('NADfinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_replicated_nad_seq.csv versions.yml
    """
}

workflow BIOC_NADFINDER_REPLICATED_NAD_SEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamFiles, Mmusculus, ideo.mm10.rds ] ]

    main:
    BIOC_NADFINDER_REPLICATED_NAD_SEQ(ch_input)

    emit:
    tables   = BIOC_NADFINDER_REPLICATED_NAD_SEQ.out.tables
    plots    = BIOC_NADFINDER_REPLICATED_NAD_SEQ.out.plots
    objects  = BIOC_NADFINDER_REPLICATED_NAD_SEQ.out.objects
    versions = BIOC_NADFINDER_REPLICATED_NAD_SEQ.out.versions
}
