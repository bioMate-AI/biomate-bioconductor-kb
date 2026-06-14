#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: InTAD — tad_based_correlation
// Correlate gene expression and epigenetic signals within topologically associating domains (TADs).
// Input: enhSel, enhSelGR, rpkmCountsSel, txsSel, mbAnnData, tadGR
// Container: quay.io/biocontainers/bioconductor-intad:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, InTAD
// Visualizations: correlation plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the InTADSig object
//  * 2. [Core Analysis] Filter low-expressed genes
//  * 3. [Core Analysis] Combine signals and genes within TADs
//  * 4. [Core Analysis] Perform correlation analysis
//  * 5. [Visualization & Output] Visualize correlation for a specific pair or across a genomic region

nextflow.enable.dsl = 2

process BIOC_INTAD_TAD_BASED_CORRELATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("InTAD", "GenomicRanges")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
        library(InTAD)
        library(GenomicRanges)
        
        # Read user input files from the working directory
        enhSel <- readRDS("enhSel.rds")
        enhSelGR <- readRDS("enhSelGR.rds")
        rpkmCountsSel <- readRDS("rpkmCountsSel.rds")
        txsSel <- readRDS("txsSel.rds")
        mbAnnData <- readRDS("mbAnnData.rds")
        tadGR <- readRDS("tadGR.rds")
        
        # 1. Initialize the InTADSig object
        inTadSig <- newSigInTAD(enhSel, enhSelGR, rpkmCountsSel, txsSel, mbAnnData)
        
        # 2. Filter low-expressed genes
        inTadSig <- filterGeneExpr(inTadSig, checkExprDistr = TRUE)
        
        # 3. Combine signals and genes within TADs
        inTadSig <- combineInTAD(inTadSig, tadGR)
        
        # Save the combined InTADSig object
        saveRDS(inTadSig, "inTadSig_combined.rds")
        
        # Open PDF device to capture all generated plots
        pdf("InTAD_analysis_plots.pdf", width = 12, height = 8)
        
        # 4. Perform correlation analysis
        par(mfrow=c(1,2))
        corData <- findCorrelation(inTadSig, plot.proportions = TRUE)
        
        # Save correlation results
        write.csv(corData, "corData_results.csv", row.names = FALSE)
        
        # Filter correlation data for specific region and gene
        best_idx <- which.min(corData\$pvalue)
        cID <- corData\$peakid[best_idx]
        gName <- corData\$name[best_idx]
        
        selCorData <- corData[corData\$peakid == cID, ]
        top_cor <- selCorData[selCorData\$name == gName, ]
        write.csv(top_cor, "top_correlation_results.csv", row.names = FALSE)
        
        # 5. Visualize correlation for a specific pair or across a genomic region
        pheno_col <- colnames(mbAnnData)[1]
        
        plotCorrelation(inTadSig, cID, gName,
                        xLabel = "RPKM gene expr log2",
                        yLabel = "H3K27ac enrichment log2", 
                        colByPhenotype = pheno_col)
        
        target_region <- GRanges(corData\$tad[best_idx])
        
        plotCorAcrossRef(inTadSig, corData,
                         targetRegion = target_region, 
                         tads = tadGR)
        
        plotCorAcrossRef(inTadSig, corData,
                         targetRegion = target_region, 
                         showCorVals = TRUE, tads = tadGR)
        
        plotCorAcrossRef(inTadSig, corData,
                         targetRegion = target_region, 
                         showCorVals = TRUE, symmetric = TRUE, tads = tadGR)
        
        # Close the PDF device
        dev.off()

    writeLines(c(
        '"BIOC_INTAD_TAD_BASED_CORRELATION":',
        paste0('    InTAD: ', as.character(packageVersion('InTAD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tad_based_correlation.csv versions.yml
    """
}

workflow BIOC_INTAD_TAD_BASED_CORRELATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ enhSel, enhSelGR, rpkmCountsSel, txsSel, mbAnnData, tadGR ] ]

    main:
    BIOC_INTAD_TAD_BASED_CORRELATION(ch_input)

    emit:
    tables   = BIOC_INTAD_TAD_BASED_CORRELATION.out.tables
    plots    = BIOC_INTAD_TAD_BASED_CORRELATION.out.plots
    objects  = BIOC_INTAD_TAD_BASED_CORRELATION.out.objects
    versions = BIOC_INTAD_TAD_BASED_CORRELATION.out.versions
}
