#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: saser — aberrant_splicing_analysis
// Detect aberrant splicing (at bin or junction level) from BAM files and GTF annotation.
// Input: BAMFiles, gtfFileName
// Container: quay.io/biocontainers/bioconductor-saser:1.6.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SASER_ABERRANT_SPLICING_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-saser:1.6.0--r45hdfd78af_0"

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
    .bm_deps <- c("ASpli", "BiocParallel", "DESeq2", "GenomicFeatures", "PRROC", "data.table", "dplyr", "edgeR", "igraph", "limma", "saseR", "txdbmaker")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(saseR)
    suppressWarnings(library(ASpli))
    library(edgeR)
    library(DESeq2)
    library(limma)
    library(GenomicFeatures)
    library(dplyr)
    library(PRROC)
    library(BiocParallel)
    library(data.table)
    library(igraph)
    library(txdbmaker)
    
    # -----------------------------------------------------------------------------
    # 1. Locate User Input Files in the Working Directory
    # -----------------------------------------------------------------------------
    gtf_files <- list.files(pattern = "\\.(gtf|gff)\$", ignore.case = TRUE)
    if (length(gtf_files) == 0) {
      stop("Error: No GTF or GFF file found in the working directory.")
    }
    gtfFileName <- gtf_files[1]
    
    BAMFiles <- list.files(pattern = "\\.bam\$", ignore.case = TRUE)
    if (length(BAMFiles) == 0) {
      stop("Error: No BAM files found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Prepare Targets and Genome Features
    # -----------------------------------------------------------------------------
    targets <- data.frame( 
      row.names = paste0('Sample', seq_along(BAMFiles)),
      bam = BAMFiles,
      f1 = rep("A", length(BAMFiles)),
      stringsAsFactors = FALSE)
    
    genomeTxDb <- txdbmaker::makeTxDbFromGFF(gtfFileName)
    features <- binGenome(genomeTxDb, logTo = NULL)
    
    # -----------------------------------------------------------------------------
    # 3. Count Reads from BAM Files
    # -----------------------------------------------------------------------------
    ASpliSE <- BamtoAspliCounts(
                        features = features,
                        targets = targets,
                        minReadLength = 100,
                        libType = "SE",
                        BPPARAM = MulticoreParam(1L)
                        )
    
    # -----------------------------------------------------------------------------
    # 4. Extract Bin and Junction Counts
    # -----------------------------------------------------------------------------
    SEbins <- convertASpli(ASpliSE, type = "bin")
    SEjunctions <- convertASpli(ASpliSE, type = "junction")
    
    # -----------------------------------------------------------------------------
    # 5. Define Design Formula
    # -----------------------------------------------------------------------------
    metadata(SEbins)\$design <- ~1
    metadata(SEjunctions)\$design <- ~1
    
    # -----------------------------------------------------------------------------
    # 6. Calculate Splicing Offsets (Before Filtering)
    # -----------------------------------------------------------------------------
    SEbins <- calculateOffsets(SEbins, 
                                method = "AS", 
                                aggregation = "locus")
    
    SEjunctions <- calculateOffsets(SEjunctions, 
                                method = "AS", 
                                aggregation = "symbol",
                                mergeGeneASpli = TRUE)
    
    # -----------------------------------------------------------------------------
    # 7. Filter Low-Count Features
    # -----------------------------------------------------------------------------
    filterbins <- filterByExpr(SEbins)
    SEbins <- SEbins[filterbins,]
    
    filterjunctions <- filterByExpr(SEjunctions)
    SEjunctions <- SEjunctions[filterjunctions,]
    
    # -----------------------------------------------------------------------------
    # 8. Estimate Latent Confounders
    # -----------------------------------------------------------------------------
    SEbins <- saseRfindEncodingDim(SEbins, method = "GD")
    SEjunctions <- saseRfindEncodingDim(SEjunctions, method = "GD")
    
    # -----------------------------------------------------------------------------
    # 9. Fit Regression Model and Calculate P-values
    # -----------------------------------------------------------------------------
    SEbins <- saseRfit(SEbins,
                        analysis = "AS",
                        padjust = "BH",
                        fit = "fast")
    
    SEjunctions <- saseRfit(SEjunctions,
                        analysis = "AS",
                        padjust = "BH",
                        fit = "fast")
    
    # -----------------------------------------------------------------------------
    # 10. Save Meaningful Outputs
    # -----------------------------------------------------------------------------
    # Save full SummarizedExperiment objects
    saveRDS(SEbins, "SEbins_results.rds")
    saveRDS(SEjunctions, "SEjunctions_results.rds")
    
    # Export p-values and adjusted p-values to CSV
    if ("pValue" %in% names(assays(SEbins))) {
      write.csv(as.data.frame(assays(SEbins)\$pValue), "SEbins_pValues.csv", row.names = TRUE)
    }
    if ("pValueAdjust" %in% names(assays(SEbins))) {
      write.csv(as.data.frame(assays(SEbins)\$pValueAdjust), "SEbins_pValueAdjust.csv", row.names = TRUE)
    }
    
    if ("pValue" %in% names(assays(SEjunctions))) {
      write.csv(as.data.frame(assays(SEjunctions)\$pValue), "SEjunctions_pValues.csv", row.names = TRUE)
    }
    if ("pValueAdjust" %in% names(assays(SEjunctions))) {
      write.csv(as.data.frame(assays(SEjunctions)\$pValueAdjust), "SEjunctions_pValueAdjust.csv", row.names = TRUE)
    }
    
    # Generate diagnostic plots
    pdf("aberrant_splicing_pvalues_histogram.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    if ("pValue" %in% names(assays(SEbins))) {
      hist(assays(SEbins)\$pValue, main = "Bin-level p-values", xlab = "p-value", col = "skyblue", border = "white")
    }
    if ("pValue" %in% names(assays(SEjunctions))) {
      hist(assays(SEjunctions)\$pValue, main = "Junction-level p-values", xlab = "p-value", col = "salmon", border = "white")
    }
    dev.off()
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SASER_ABERRANT_SPLICING_ANALYSIS":
        saser: \$(Rscript -e 'cat(as.character(packageVersion("saser")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aberrant_splicing_analysis.csv versions.yml
    """
}

workflow BIOC_SASER_ABERRANT_SPLICING_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BAMFiles, gtfFileName ] ]

    main:
    BIOC_SASER_ABERRANT_SPLICING_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SASER_ABERRANT_SPLICING_ANALYSIS.out.tables
    plots    = BIOC_SASER_ABERRANT_SPLICING_ANALYSIS.out.plots
    objects  = BIOC_SASER_ABERRANT_SPLICING_ANALYSIS.out.objects
    versions = BIOC_SASER_ABERRANT_SPLICING_ANALYSIS.out.versions
}
