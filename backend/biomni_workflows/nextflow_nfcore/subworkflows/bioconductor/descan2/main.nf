#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: descan2 — differential_enrichment_workflow
// Identify differentially enriched genomic regions from raw BAM/BED alignment files across multiple replicates and conditions.
// Input: bam.files, peaksGRL_all_files.rds
// Container: quay.io/biocontainers/bioconductor-descan2:1.30.0--r45ha27e39d_0
// R packages: EDASeq, GenomicRanges, SummarizedExperiment, BiocParallel, DEScan2, edgeR, limma, RColorBrewer, RUVSeq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: PCA plot, RLE plot
// QC: dispersion/size-factor estimation, diagnostic MA/PCA QC, low-count filtering

nextflow.enable.dsl = 2

process BIOC_DESCAN2_DIFFERENTIAL_ENRICHMENT_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-descan2:1.30.0--r45ha27e39d_0"

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
    .bm_deps <- c("EDASeq", "GenomicRanges", "SummarizedExperiment", "BiocParallel", "DEScan2", "edgeR", "limma", "RColorBrewer", "RUVSeq")
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
    
    library("DEScan2")
    library("RUVSeq")
    library("edgeR")
    library("RColorBrewer")
    library("GenomicRanges")
    library("SummarizedExperiment")
    library("EDASeq")
    library("limma")
    
    BiocParallel::register(BiocParallel::SerialParam())
    
    # --- Call peaks for each sample using findPeaks or load ---
    if (file.exists("peaksGRL_all_files.rds")) {
        message("Loading pre-computed peaksGRL_all_files.rds...")
        peaksGRL <- readRDS("peaksGRL_all_files.rds")
    } else {
        message("Calling peaks for each BAM file in the working directory...")
        bam.files <- list.files(path = ".", pattern = "\\\\.bam\$", full.names = TRUE)
        if (length(bam.files) == 0) {
            stop("No BAM files found in the working directory, and peaksGRL_all_files.rds is missing.")
        }
        
        peaks_list <- list()
        for (bf in bam.files) {
            sample_name <- tools::file_path_sans_ext(basename(bf))
            message("Processing sample: ", sample_name)
            peaks_list[[sample_name]] <- DEScan2::findPeaks(
                files=bf, filetype="bam", genomeName="mm9",
                binSize=50, minWin=50, maxWin=1000, zthresh=10, minCount=0.1, sigwin=10,
                minCompWinWidth=5000, maxCompWinWidth=10000, save=FALSE,
                outputFolder="peaks", force=TRUE, onlyStdChrs=TRUE, chr=NULL, verbose=FALSE
            )
        }
        peaksGRL <- GenomicRanges::GRangesList(peaks_list)
        saveRDS(peaksGRL, "peaksGRL_all_files.rds")
    }
    
    # --- Align overlapping peaks across replicates to produce ---
    regionsGR <- DEScan2::finalRegions(peakSamplesGRangesList=peaksGRL, zThreshold=10,
                    minCarriers=3, saveFlag=FALSE, outputFolder=NULL, verbose=FALSE)
    
    saveRDS(regionsGR, "regionsGR.rds")
    
    # --- Count reads in the final consensus regions ---
    bam.path <- "."
    finalRegions <- DEScan2::countFinalRegions(regionsGRanges=regionsGR, 
                        readsFilePath=bam.path, fileType="bam", minCarriers=1,
                        genomeName="mm9", onlyStdChrs=TRUE, saveFlag=FALSE,
                        verbose=FALSE)
    
    counts <- SummarizedExperiment::assay(finalRegions)
    regions <- SummarizedExperiment::rowRanges(finalRegions)
    
    # --- Filter and format the count matrix ---
    counts <- counts[regions\$`k-carriers` >= 4, ]
    counts <- counts[rowSums(counts) > 0, ]
    
    # Set up experimental design dynamically based on sample count
    if (ncol(counts) == 8) {
        colnames(counts) <- c("FC1", "FC4", "HC1", "HC4", "FC6", "FC9", "HC6", "HC9")
        counts <- counts[, order(colnames(counts))]
        trt <- factor(c(rep("FC", 4), rep("HC", 4)))
        groups <- matrix(c(1:8), nrow=2, byrow=TRUE)
    } else {
        colnames(counts) <- gsub("\\\\.bam\$", "", basename(colnames(counts)))
        counts <- counts[, order(colnames(counts))]
        n_samples <- ncol(counts)
        if (n_samples %% 2 == 0) {
            trt <- factor(c(rep("FC", n_samples/2), rep("HC", n_samples/2)))
            groups <- matrix(1:n_samples, nrow=2, byrow=TRUE)
        } else {
            trt <- factor(rep("Group1", n_samples))
            groups <- matrix(1:n_samples, nrow=1, byrow=TRUE)
        }
    }
    
    write.csv(counts, "counts_matrix.csv", row.names=TRUE)
    
    # --- Perform between-sample normalization using EDASeq and ---
    colors <- brewer.pal(3, "Set2")
    set <- EDASeq::betweenLaneNormalization(counts, which = "upper")
    
    pdf("normalization_plots.pdf", width=10, height=10)
    par(mfrow=c(2,2))
    
    EDASeq::plotRLE(set, outline=FALSE, ylim=c(-4, 4),
            col=colors[trt], main="No Normalization RLE")
    EDASeq::plotPCA(set, col=colors[trt], main="No Normalization PCA", 
                    labels=FALSE, pch=19)
    
    k <- 4
    if (ncol(counts) <= 4) {
        k <- max(1, ncol(counts) - 1)
    }
    
    s <- RUVSeq::RUVs(set, cIdx=rownames(set), scIdx=groups, k=k)
    
    EDASeq::plotRLE(s\$normalizedCounts, outline=FALSE, ylim=c(-4, 4), 
            col=colors[trt], main="Normalized RLE")
    EDASeq::plotPCA(s\$normalizedCounts, col=colors[trt], main="Normalized PCA",
            labels=FALSE, pch=19)
    
    dev.off()
    
    # --- Test for differential enrichment using edgeR negative ---
    design <- model.matrix(~0 + trt + s\$W)
    colnames(design) <- c(levels(trt), paste0("W", 1:k))
    
    y <- edgeR::DGEList(counts=counts, group=trt)
    y <- edgeR::estimateDisp(y, design)
    
    fit <- edgeR::glmQLFit(y, design, robust=TRUE)
    
    # Create contrast dynamically based on the levels of trt
    if (length(levels(trt)) >= 2) {
        contrast_str <- paste0(levels(trt)[1], " - ", levels(trt)[2])
        con <- limma::makeContrasts(contrasts=contrast_str, levels=design)
        
        qlf <- edgeR::glmQLFTest(fit, contrast=con)
        res <- edgeR::topTags(qlf, n=Inf, p.value=0.05)
        
        write.csv(as.data.frame(res\$table), "differential_enrichment_results.csv", row.names=TRUE)
        
        de_regions <- regions[rownames(res\$table)]
        saveRDS(de_regions, "differentially_enriched_regions.rds")
    } else {
        message("Skipping differential testing: less than 2 treatment groups defined.")
    }

    writeLines(c(
        '"BIOC_DESCAN2_DIFFERENTIAL_ENRICHMENT_WORKFLOW":',
        paste0('        descan2: ', as.character(packageVersion("descan2")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_enrichment_workflow.csv versions.yml
    """
}

workflow BIOC_DESCAN2_DIFFERENTIAL_ENRICHMENT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam.files, peaksGRL_all_files.rds ] ]

    main:
    BIOC_DESCAN2_DIFFERENTIAL_ENRICHMENT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_DESCAN2_DIFFERENTIAL_ENRICHMENT_WORKFLOW.out.tables
    plots    = BIOC_DESCAN2_DIFFERENTIAL_ENRICHMENT_WORKFLOW.out.plots
    objects  = BIOC_DESCAN2_DIFFERENTIAL_ENRICHMENT_WORKFLOW.out.objects
    versions = BIOC_DESCAN2_DIFFERENTIAL_ENRICHMENT_WORKFLOW.out.versions
}
