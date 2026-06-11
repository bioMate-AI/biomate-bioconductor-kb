#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CODEX — case_control_wes_cnv_calling
// Call copy number variations (CNVs) from whole exome sequencing (WES) data under a case-control design, estimating latent factors from control samples.
// Input: *.bam, *.bed, sampname
// Container: quay.io/biocontainers/bioconductor-codex:1.42.0--r45hdfd78af_0
// R packages: CODEX
// Bioconductor: 3.20 | R: 4.4
// Requires: CODEX
// Visualizations: image plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load BAM and BED files using getbambed
//  * 2. [Input & Preparation] Compute raw read depth coverage using getcoverage
//  * 3. [Core Analysis] Retrieve GC content and mappability using getgc and getmapp
//  * 4. [Core Analysis] Perform quality control filtering on exons and samples using qc
//  * 5. [Core Analysis] Fit Poisson latent factor model using control samples for normalization via normalize2
//  * 6. [Core Analysis] Determine the optimal number of latent factors (K) using choiceofK
//  * 7. [Core Analysis] Run Poisson log-likelihood ratio-based segmentation to call CNVs using segment

nextflow.enable.dsl = 2

process BIOC_CODEX_CASE_CONTROL_WES_CNV_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("CODEX")
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
    
    library(CODEX)
    
    # 1. Locate and read user input files from the working directory
    bamFiles <- list.files(pattern = "\\\\.bam\$")
    if (length(bamFiles) == 0) {
      stop("Error: No .bam files found in the working directory.")
    }
    bamdir <- normalizePath(bamFiles)
    
    bedFiles <- list.files(pattern = "\\\\.bed\$")
    if (length(bedFiles) == 0) {
      stop("Error: No .bed file found in the working directory.")
    }
    bedFile <- normalizePath(bedFiles[1])
    
    if (!file.exists("sampname")) {
      stop("Error: 'sampname' file not found in the working directory.")
    }
    sampname <- as.matrix(read.table("sampname", header = FALSE, stringsAsFactors = FALSE))
    
    # Determine chromosome dynamically from the BED file
    bed_preview <- read.table(bedFile, nrows = 1, header = FALSE, stringsAsFactors = FALSE)
    chr_raw <- as.character(bed_preview[1, 1])
    chr_clean <- gsub("chr", "", chr_raw)
    if (!is.na(as.numeric(chr_clean))) {
      chr <- as.numeric(chr_clean)
    } else {
      chr <- chr_raw
    }
    
    # 2. Load BAM and BED files using getbambed
    bambedObj <- getbambed(bamdir = bamdir, bedFile = bedFile, 
                           sampname = sampname, projectname = "CODEX_case_control", chr = chr)
    bamdir <- bambedObj\$bamdir
    sampname <- bambedObj\$sampname
    ref <- bambedObj\$ref
    projectname <- bambedObj\$projectname
    chr <- bambedObj\$chr
    
    # 3. Compute raw read depth coverage using getcoverage
    coverageObj <- getcoverage(bambedObj, mapqthres = 20)
    Y <- coverageObj\$Y
    readlength <- coverageObj\$readlength
    
    # 4. Retrieve GC content and mappability using getgc and getmapp
    gc <- getgc(chr, ref)
    mapp <- getmapp(chr, ref)
    
    # 5. Perform quality control filtering on exons and samples using qc
    qcObj <- qc(Y, sampname, chr, ref, mapp, gc, cov_thresh = c(20, 4000), 
                length_thresh = c(20, 2000), mapp_thresh = 0.9, gc_thresh = c(20, 80))
    Y_qc <- qcObj\$Y_qc
    sampname_qc <- qcObj\$sampname_qc
    gc_qc <- qcObj\$gc_qc
    mapp_qc <- qcObj\$mapp_qc
    ref_qc <- qcObj\$ref_qc
    qcmat <- qcObj\$qcmat
    
    write.table(qcmat, file = paste(projectname, '_', chr, '_qcmat', '.txt', sep=''),
                sep='\t', quote=FALSE, row.names=FALSE)
    
    # 6. Identify control/normal samples for case-control normalization
    # Search for common control keywords in the QC-passed sample names; default to first half if none found
    sampnames_vector <- as.vector(sampname_qc)
    normal_index <- grep("control|normal|ref|ctrl|N", sampnames_vector, ignore.case = TRUE)
    if (length(normal_index) == 0) {
      normal_index <- seq(1, max(1, floor(length(sampnames_vector) / 2)))
    }
    
    # Ensure K is within a valid range based on the number of control samples
    max_K <- min(9, length(normal_index) - 1)
    if (max_K < 1) {
      max_K <- 1
    }
    K_set <- 1:max_K
    
    # Fit Poisson latent factor model using control samples for normalization via normalize2
    normObj <- normalize2(Y_qc, gc_qc, K = K_set, normal_index = normal_index)
    Yhat <- normObj\$Yhat
    AIC <- normObj\$AIC
    BIC <- normObj\$BIC
    RSS <- normObj\$RSS
    K <- normObj\$K
    
    # 7. Determine the optimal number of latent factors (K) using choiceofK
    choiceofK(AIC, BIC, RSS, K, filename = paste(projectname, "_", chr, "_choiceofK", ".pdf", sep = ""))
    
    optK <- K[which.max(BIC)]
    if (length(optK) == 0 || is.na(optK)) {
      optK <- K[1]
    }
    
    # 8. Run Poisson log-likelihood ratio-based segmentation to call CNVs using segment
    finalcall <- segment(Y_qc, Yhat, optK = optK, K = K, sampname_qc = sampname_qc,
                         ref_qc = ref_qc, chr = chr, lmax = 200, mode = "integer")
    
    # Write final outputs
    write.table(finalcall, file = paste(projectname, '_', chr, '_', optK, '_CODEX_frac.txt', sep=''), 
                sep='\t', quote=FALSE, row.names=FALSE)
    
    save.image(file = paste(projectname, '_', chr, '_image', '.rda', sep=''), compress='xz')

    writeLines(c(
        '"BIOC_CODEX_CASE_CONTROL_WES_CNV_CALLING":',
        paste0('    CODEX: ', as.character(packageVersion('CODEX')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_case_control_wes_cnv_calling.csv versions.yml
    """
}

workflow BIOC_CODEX_CASE_CONTROL_WES_CNV_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ *.bam, *.bed, sampname ] ]

    main:
    BIOC_CODEX_CASE_CONTROL_WES_CNV_CALLING(ch_input)

    emit:
    tables   = BIOC_CODEX_CASE_CONTROL_WES_CNV_CALLING.out.tables
    plots    = BIOC_CODEX_CASE_CONTROL_WES_CNV_CALLING.out.plots
    objects  = BIOC_CODEX_CASE_CONTROL_WES_CNV_CALLING.out.objects
    versions = BIOC_CODEX_CASE_CONTROL_WES_CNV_CALLING.out.versions
}
