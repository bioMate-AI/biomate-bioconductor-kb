#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DMRcaller — bisulfite_seq_dmr_analysis
// Identify differentially methylated regions (DMRs) from Bismark CX report files.
// Input: cond1.CX_report, cond2.CX_report, genes.gff
// Container: quay.io/biocontainers/bioconductor-dmrcaller:1.42.0--r45ha27e39d_0
// R packages: GenomicRanges, betareg, DMRcaller, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: DMRcaller, GenomicRanges, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read Bismark CX report files using readBismark
//  * 2. [Core Analysis] Pool replicates if necessary using poolMethylationDatasets or poolTwoMethylationDatasets
//  * 3. [Core Analysis] Compute DMRs using computeDMRs
//  * 4. [Core Analysis] Filter DMRs in predefined regions (e.g., genes) using filterDMRs
//  * 5. [Core Analysis] Merge adjacent DMRs iteratively using mergeDMRsIteratively
//  * 6. [Core Analysis] Analyze reads inside regions for other contexts using analyseReadsInsideRegionsForCondition

nextflow.enable.dsl = 2

process BIOC_DMRCALLER_BISULFITE_SEQ_DMR_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "betareg", "DMRcaller", "rtracklayer")
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
    library(DMRcaller)
    library(GenomicRanges)
    library(rtracklayer)
    
    # 1. Read Bismark CX report files using readBismark
    methylationDataWT <- readBismark("cond1.CX_report")
    methylationDataMet13 <- readBismark("cond2.CX_report")
    methylationDataList <- GRangesList("WT" = methylationDataWT,
                                       "met1-3" = methylationDataMet13)
    
    # 2. Pooling
    methylationDataAll <- poolMethylationDatasets(methylationDataList)
    saveRDS(methylationDataAll, "methylationDataAll.rds")
    
    # Define chr_local dynamically from the input data to cover the entire range
    chr_local <- range(methylationDataWT)
    strand(chr_local) <- "*"
    chr_local <- reduce(chr_local)
    
    # Read gene annotation from GFF
    genes_all <- import("genes.gff")
    genes <- genes_all[genes_all\$type == "gene"]
    if (length(genes) == 0) {
      genes <- genes_all
    }
    
    # 3. Compute DMRs
    DMRsNoiseFilterCG <- computeDMRs(methylationDataList[["WT"]],
                          methylationDataList[["met1-3"]],
                          regions = chr_local,
                          context = "CG",
                          method = "noise_filter",
                          windowSize = 100,
                          kernelFunction = "triangular",
                          test = "score",
                          pValueThreshold = 0.01,
                          minCytosinesCount = 4,
                          minProportionDifference = 0.4,
                          minGap = 0,
                          minSize = 50,
                          minReadsPerCytosine = 4,
                          cores = 1)
    
    # 4. Filter DMRs
    overlapping_genes <- genes[overlapsAny(genes, chr_local)]
    if (length(overlapping_genes) == 0) {
      overlapping_genes <- genes
    }
    
    DMRsGenesCG <- filterDMRs(methylationDataList[["WT"]],
                              methylationDataList[["met1-3"]],
                              potentialDMRs = overlapping_genes,
                              context = "CG",
                              test = "score",
                              pValueThreshold = 0.01,
                              minCytosinesCount = 4,
                              minProportionDifference = 0.4,
                              minReadsPerCytosine = 3,
                              cores = 1)
    
    # 5. Merge DMRs
    DMRsNoiseFilterCGMerged <- mergeDMRsIteratively(DMRsNoiseFilterCG,
                                                    minGap = 200,
                                                    respectSigns = TRUE,
                                                    methylationDataList[["WT"]],
                                                    methylationDataList[["met1-3"]],
                                                    context = "CG",
                                                    minProportionDifference = 0.4,
                                                    minReadsPerCytosine = 4,
                                                    pValueThreshold = 0.01,
                                                    test="score")
    
    # 6. Extract reads inside regions
    DMRsNoiseFilterCGreadsCHH <- analyseReadsInsideRegionsForCondition(
                                  DMRsNoiseFilterCGMerged,
                                  methylationDataList[["WT"]], context = "CHH",
                                  label = "WT")
    
    # Save outputs to files
    write.csv(as.data.frame(DMRsNoiseFilterCG), "DMRs_NoiseFilter_CG.csv", row.names = FALSE)
    saveRDS(DMRsNoiseFilterCG, "DMRs_NoiseFilter_CG.rds")
    
    write.csv(as.data.frame(DMRsGenesCG), "DMRs_Genes_CG.csv", row.names = FALSE)
    saveRDS(DMRsGenesCG, "DMRs_Genes_CG.rds")
    
    write.csv(as.data.frame(DMRsNoiseFilterCGMerged), "DMRs_NoiseFilter_CG_Merged.csv", row.names = FALSE)
    saveRDS(DMRsNoiseFilterCGMerged, "DMRs_NoiseFilter_CG_Merged.rds")
    
    write.csv(as.data.frame(DMRsNoiseFilterCGreadsCHH), "DMRs_NoiseFilter_CG_reads_CHH.csv", row.names = FALSE)
    saveRDS(DMRsNoiseFilterCGreadsCHH, "DMRs_NoiseFilter_CG_reads_CHH.rds")

    writeLines(c(
        '"BIOC_DMRCALLER_BISULFITE_SEQ_DMR_ANALYSIS":',
        paste0('    DMRcaller: ', as.character(packageVersion('DMRcaller')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bisulfite_seq_dmr_analysis.csv versions.yml
    """
}

workflow BIOC_DMRCALLER_BISULFITE_SEQ_DMR_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cond1.CX_report, cond2.CX_report, genes.gff ] ]

    main:
    BIOC_DMRCALLER_BISULFITE_SEQ_DMR_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DMRCALLER_BISULFITE_SEQ_DMR_ANALYSIS.out.tables
    plots    = BIOC_DMRCALLER_BISULFITE_SEQ_DMR_ANALYSIS.out.plots
    objects  = BIOC_DMRCALLER_BISULFITE_SEQ_DMR_ANALYSIS.out.objects
    versions = BIOC_DMRCALLER_BISULFITE_SEQ_DMR_ANALYSIS.out.versions
}
