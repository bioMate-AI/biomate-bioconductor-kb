#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNVRanger — cnv_expression_eqtl_tcga
// Perform integrated CNV-expression association analysis using TCGA data stored in a MultiAssayExperiment.
// Input: MultiAssayExperiment
// Container: quay.io/biocontainers/bioconductor-cnvranger:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CNVRanger, GenomeInfoDb, GenomicRanges, MultiAssayExperiment, TCGAutils
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the user-provided MultiAssayExperiment from the
//  * 2. [Visualization & Output] Harmonize genomic coordinates and filter assays to
//  * 3. [Visualization & Output] Convert segmented log2 copy number ratios to integer copy
//  * 4. [Visualization & Output] Run cnvEQTL on the MultiAssayExperiment
//  * 5. [Visualization & Output] Save results to disk
//  * 6. [Visualization & Output] Plot eQTL results if sufficient regions are found

nextflow.enable.dsl = 2

process BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_TCGA {
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
    .bm_deps <- c("CNVRanger", "MultiAssayExperiment", "TCGAutils", "GenomeInfoDb", "GenomicRanges", "SummarizedExperiment")
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
    library(CNVRanger)
    library(SummarizedExperiment)
    library(MultiAssayExperiment)
    library(TCGAutils)
    library(GenomeInfoDb)
    library(GenomicRanges)
    
    # --- Read the user-provided MultiAssayExperiment from the ---
    mae_file <- "MultiAssayExperiment.rds"
    if (!file.exists(mae_file)) {
        stop("Error: Required input file 'MultiAssayExperiment.rds' not found in the working directory.")
    }
    
    gbm <- readRDS(mae_file)
    
    # Ensure assay names match the expected TCGA GBM names for the documented code to run seamlessly
    expected_names <- c("GBM_GISTIC_Peaks-20160128", "GBM_CNVSNP-20160128", "GBM_RNASeq2GeneNorm-20160128")
    if (!all(expected_names %in% names(gbm))) {
        gistic_idx <- grep("GISTIC", names(gbm), ignore.case = TRUE)
        cnv_idx <- grep("CNV", names(gbm), ignore.case = TRUE)
        rna_idx <- grep("RNASeq", names(gbm), ignore.case = TRUE)
        if (length(gistic_idx) == 1 && length(cnv_idx) == 1 && length(rna_idx) == 1) {
            names(gbm)[gistic_idx] <- "GBM_GISTIC_Peaks-20160128"
            names(gbm)[cnv_idx] <- "GBM_CNVSNP-20160128"
            names(gbm)[rna_idx] <- "GBM_RNASeq2GeneNorm-20160128"
        }
    }
    
    # --- Harmonize genomic coordinates and filter assays to ---
    gbm <- TCGAutils::symbolsToRanges(gbm, unmapped=FALSE)
    
    for(i in 1:3) 
    {
        rr <- rowRanges(gbm[[i]])
        GenomeInfoDb::genome(rr) <- "NCBI37"
        GenomeInfoDb::seqlevelsStyle(rr) <- "UCSC"
        ind <- as.character(seqnames(rr)) %in% c("chr1", "chr2")
        rowRanges(gbm[[i]]) <- rr
        gbm[[i]] <- gbm[[i]][ind,]
    }
    
    gbm <- MultiAssayExperiment::intersectColumns(gbm)
    gbm <- TCGAutils::TCGAsplitAssays(gbm, sampleCodes="01")
    
    # --- Convert segmented log2 copy number ratios to integer copy ---
    ind <- grep("CNVSNP", names(gbm))
    smean <- mcols(gbm[[ind]])\$Segment_Mean
    state <- round(2^smean * 2)
    state[state > 4] <- 4
    mcols(gbm[[ind]])\$state <- state
    gbm[[ind]] <- gbm[[ind]][state != 2,]
    mcols(gbm[[ind]]) <- mcols(gbm[[ind]])[,3:1]
    
    # --- Run cnvEQTL on the MultiAssayExperiment ---
    res <- cnvEQTL(cnvrs="01_GBM_GISTIC_Peaks-20160128", calls="01_GBM_CNVSNP-20160128", rcounts="01_GBM_RNASeq2GeneNorm-20160128_ranged", data=gbm, window="1Mbp", verbose=TRUE)
    
    # --- Save results to disk ---
    saveRDS(res, "cnv_eqtl_results.rds")
    res_df <- as.data.frame(res)
    write.csv(res_df, "cnv_eqtl_results.csv", row.names=FALSE)
    
    # --- Plot eQTL results if sufficient regions are found ---
    if (length(res) >= 2) {
        pdf("cnv_eqtl_plot.pdf", width=10, height=8)
        r <- GRanges(names(res)[2])
        plotEQTL(cnvr=r, genes=res[[2]], genome="hg19", cn="CN1")
        dev.off()
    } else {
        message("Skipping plotEQTL: fewer than 2 regions in results.")
    }

    writeLines(c(
        '"BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_TCGA":',
        paste0('    CNVRanger: ', as.character(packageVersion('CNVRanger')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnv_expression_eqtl_tcga.csv versions.yml
    """
}

workflow BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_TCGA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MultiAssayExperiment ] ]

    main:
    BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_TCGA(ch_input)

    emit:
    tables   = BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_TCGA.out.tables
    plots    = BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_TCGA.out.plots
    objects  = BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_TCGA.out.objects
    versions = BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_TCGA.out.versions
}
