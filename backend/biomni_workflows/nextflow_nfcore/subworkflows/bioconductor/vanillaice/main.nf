#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: VanillaICE — cnv_calling_from_text_files
// Parse raw text files (e.g., Illumina FinalReports) and a marker annotation file to construct an ArrayViews object, convert to a SnpExperiment, fit a 6-state HMM
// Input: FinalReport*.txt, SNP_info.csv
// Container: quay.io/biocontainers/bioconductor-vanillaice:1.72.0--r45h01b2380_0
// R packages: BSgenome.Hsapiens.UCSC.hg18, GenomicRanges, ArrayTV, crlmm, data.table, dosnow, foreach, IRanges, lattice, VanillaICE
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg18, GenomicRanges, VanillaICE, data.table, lattice
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read and organize marker annotation into a SnpGRanges object
//  * 2. [Visualization & Output] Define an ArrayViews object pointing to the raw files and parsed output directory
//  * 3. [Input & Preparation] Define parsing parameters using CopyNumScanParams and parse the source files using parseSourceFile
//  * 4. [Input & Preparation] Load parsed data into a SnpArrayExperiment using SnpExperiment
//  * 5. [Input & Preparation] Define HMM emission parameters using EmissionParam and fit the HMM using hmm2
//  * 6. [Core Analysis] Filter CNV calls using FilterParam and cnvFilter
//  * 7. [Visualization & Output] Merge adjacent calls using reduce and visualize using xyplotList and xygrid

nextflow.enable.dsl = 2

process BIOC_VANILLAICE_CNV_CALLING_FROM_TEXT_FILES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg18", "GenomicRanges", "ArrayTV", "crlmm", "data.table", "dosnow", "foreach", "IRanges", "lattice", "VanillaICE")
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
    library(VanillaICE)
    library(data.table)
    library(GenomicRanges)
    library(BSgenome.Hsapiens.UCSC.hg18)
    library(lattice)
    library(grid)
    
    # 1. Read and organize marker annotation into a SnpGRanges object
    features <- suppressWarnings(fread("SNP_info.csv"))
    fgr <- GRanges(paste0("chr", features\$Chr), IRanges(features\$Position, width=1), isSnp=features[["Intensity Only"]]==0)
    fgr <- SnpGRanges(fgr)
    names(fgr) <- features[["Name"]]
    sl <- seqlevels(BSgenome.Hsapiens.UCSC.hg18)
    seqlevels(fgr) <- sl[sl %in% seqlevels(fgr)]
    seqinfo(fgr) <- seqinfo(BSgenome.Hsapiens.UCSC.hg18)[seqlevels(fgr),]
    fgr <- sort(fgr)
    
    # Find user input files
    files <- list.files(pattern="^FinalReport.*\\\\.txt\$", full.names=TRUE)
    if (length(files) == 0) {
      stop("No FinalReport*.txt files found in the working directory.")
    }
    
    # 2. Define an ArrayViews object pointing to the raw files and parsed output directory
    parsedDir <- tempdir()
    views <- ArrayViews(rowRanges=fgr, sourcePaths=files, parsedPath=parsedDir)
    lrrFile(views) <- file.path(parsedDir, basename(fileName(views, "lrr")))
    views@bafFiles <- file.path(parsedDir, basename(fileName(views, "baf")))
    views@gtFiles <- file.path(parsedDir, basename(fileName(views, "gt")))
    colnames(views) <- gsub(".csv", "", colnames(views))
    
    # 3. Define parsing parameters using CopyNumScanParams and parse the source files using parseSourceFile
    dat <- fread(files[1], skip="[Data]")
    select_columns <- match(c("SNP Name", "Allele1 - AB", "Allele2 - AB", "Log R Ratio", "B Allele Freq"), names(dat))
    index_genome <- match(names(fgr), dat[["SNP Name"]])
    scan_params <- CopyNumScanParams(index_genome=index_genome, select=select_columns, cnvar="Log R Ratio", bafvar="B Allele Freq", gtvar=c("Allele1 - AB", "Allele2 - AB"))
    
    # Parse all source files instead of just the first one
    for (i in seq_len(ncol(views))) {
      parseSourceFile(views[, i], scan_params)
    }
    
    # 4. Load parsed data into a SnpArrayExperiment using SnpExperiment
    snp_exp <- SnpExperiment(views)
    
    # 5. Define HMM emission parameters using EmissionParam and fit the HMM using hmm2
    param <- EmissionParam()
    param <- EmissionParam(temper=0.5)
    fit <- hmm2(snp_exp, param)
    
    # 6. Filter CNV calls using FilterParam and cnvFilter
    filter_param <- FilterParam()
    cnvFilter(fit, filter_param)
    select_cnv <- FilterParam(state=c("1", "2", "5", "6"), seqnames="chr22")
    cnvs <- cnvFilter(fit, select_cnv)
    
    # 7. Merge adjacent calls using reduce and visualize using xyplotList and xygrid
    trellis_param <- HmmTrellisParam()
    if (length(cnvs) > 0) {
      cnvList <- split(cnvs, cnvs\$id)
      figList <- xyplotList(cnvList, snp_exp, trellis_param)
    } else {
      cnvList <- GRangesList()
      figList <- list()
    }
    vps <- viewports()
    
    # Open PDF device to save plots
    pdf("cnv_visualization.pdf", width=10, height=8)
    
    required_ids <- colnames(views)
    
    if (length(required_ids) > 0 && required_ids[1] %in% names(figList)) {
      sample1_figs <- figList[[ required_ids[1] ]]
      if (length(sample1_figs) > 0) {
        fig1 <- sample1_figs[[1]]
        if (!is.null(fig1)) {
          xygrid(fig1, vps, cnvList[[ required_ids[1] ]][1])
        }
      }
    }
    
    if (length(required_ids) >= 2 && required_ids[2] %in% names(cnvList)) {
      cnvs_sample2 <- cnvList[[ required_ids[2] ]]
      if (length(cnvs_sample2) > 0) {
        cnvs_sample2r <- reduce(cnvs_sample2, min.gapwidth=500e3)
        fig2 <- xyplotList(cnvs_sample2r, snp_exp)
        if (!is.null(fig2) && length(fig2) > 0) {
          for (i in seq_along(fig2)) {
            print(fig2[[i]])
          }
        }
      }
    }
    dev.off()
    
    # Save meaningful results to files
    write.csv(as.data.frame(cnvs), "cnv_calls.csv", row.names=FALSE)
    saveRDS(fit, "hmm_fit.rds")
    saveRDS(snp_exp, "snp_experiment.rds")

    writeLines(c(
        '"BIOC_VANILLAICE_CNV_CALLING_FROM_TEXT_FILES":',
        paste0('    VanillaICE: ', as.character(packageVersion('VanillaICE')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnv_calling_from_text_files.csv versions.yml
    """
}

workflow BIOC_VANILLAICE_CNV_CALLING_FROM_TEXT_FILES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ FinalReport*.txt, SNP_info.csv ] ]

    main:
    BIOC_VANILLAICE_CNV_CALLING_FROM_TEXT_FILES(ch_input)

    emit:
    tables   = BIOC_VANILLAICE_CNV_CALLING_FROM_TEXT_FILES.out.tables
    plots    = BIOC_VANILLAICE_CNV_CALLING_FROM_TEXT_FILES.out.plots
    objects  = BIOC_VANILLAICE_CNV_CALLING_FROM_TEXT_FILES.out.objects
    versions = BIOC_VANILLAICE_CNV_CALLING_FROM_TEXT_FILES.out.versions
}
