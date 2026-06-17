#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iCNV — integrated_multi_platform_cnv_detection
// Integrate NGS (WES/WGS) and SNP array data to detect CNVs.
// Input: bamFile, chr22_400_to_500.bed, bam_vcf.list, csv.arrayicnv
// Container: quay.io/biocontainers/bioconductor-icnv:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iCNV
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Normalize BAM files using CODEX to get PLR (Poisson Likelihood Ratio)
//  * 2. [Core Analysis] Call sequence variant BAFs from VCF using bambaf_from_vcf
//  * 3. [Core Analysis] Convert SNP array intensity data using get_array_input and optionally denoise with SVD
//  * 4. [Core Analysis] Run integrative CNV detection using iCNV_detection
//  * 5. [Visualization & Output] Format output using output_list and convert to Genome Browser format using icnv_output_to_gb
//  * 6. [Visualization & Output] Plot results using plotHMMscore and plotindi

nextflow.enable.dsl = 2

process BIOC_ICNV_INTEGRATED_MULTI_PLATFORM_CNV_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("CODEX", "iCNV")
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
    library(iCNV)
    
    # -----------------------------------------------------------------------------
    # Stage 1: Normalize BAM files using CODEX to get PLR (Poisson Likelihood Ratio)
    # -----------------------------------------------------------------------------
    
    # Locate BAM files in the current working directory
    bamFile <- list.files(".", pattern = '\\\\.bam\$')
    if (length(bamFile) == 0) {
      stop("No BAM files found in the working directory.")
    }
    bamdir <- bamFile
    
    # Determine sample names from BAM files or a sampname file if available
    if (file.exists("sampname")) {
      sampname <- as.matrix(read.table("sampname"))
    } else {
      sampname <- as.matrix(gsub("\\\\.bam\$", "", bamFile))
    }
    
    bedFile <- "chr22_400_to_500.bed"
    if (!file.exists(bedFile)) {
      stop(paste("Required BED file not found:", bedFile))
    }
    
    chr <- 22
    projectname <- "icnv.demo."
    
    # Get BAM and BED object
    bambedObj <- getbambed(bamdir = bamdir, bedFile = bedFile, 
                           sampname = sampname, projectname = projectname, chr)
    bamdir <- bambedObj\$bamdir
    sampname <- bambedObj\$sampname
    ref <- bambedObj\$ref
    projectname <- bambedObj\$projectname
    chr <- bambedObj\$chr
    
    # Get coverage
    coverageObj <- getcoverage(bambedObj, mapqthres = 20)
    Y <- coverageObj\$Y
    readlength <- coverageObj\$readlength
    
    # Get GC content and mappability
    gc <- getgc(chr, ref)
    mapp <- getmapp(chr, ref)
    
    # Quality control
    qcObj <- qc(Y, sampname, chr, ref, mapp, gc, cov_thresh = c(20, 4000), 
                length_thresh = c(20, 2000), mapp_thresh = 0.9, gc_thresh = c(20, 80))
    Y_qc <- qcObj\$Y_qc
    sampname_qc <- qcObj\$sampname_qc
    gc_qc <- qcObj\$gc_qc
    mapp_qc <- qcObj\$mapp_qc
    ref_qc <- qcObj\$ref_qc
    qcmat <- qcObj\$qcmat
    
    # Normalize
    normObj <- normalize(Y_qc, gc_qc, K = 1:9)
    Yhat <- normObj\$Yhat
    AIC <- normObj\$AIC
    BIC <- normObj\$BIC
    RSS <- normObj\$RSS
    K <- normObj\$K
    
    # Plot choice of K and save RDA
    choiceofK(AIC, BIC, RSS, K, filename = paste0(projectname, chr, "_choiceofK.pdf"))
    save(qcObj, normObj, sampname, file = paste0(projectname, 'plrObj_', chr, ".rda"))
    
    # Load and extract optimal K
    load(paste0(projectname, 'plrObj_', chr, ".rda"))
    optK <- K[which.max(BIC)]
    
    Y_qc <- qcObj\$Y_qc
    sampname_qc <- qcObj\$sampname_qc
    gc_qc <- qcObj\$gc_qc
    mapp_qc <- qcObj\$mapp_qc
    ref_qc <- qcObj\$ref_qc
    qcmat <- qcObj\$qcmat
    Yhat <- normObj\$Yhat
    AIC <- normObj\$AIC
    BIC <- normObj\$BIC
    RSS <- normObj\$RSS
    K <- normObj\$K
    ref_qc <- qcObj\$ref_qc
    sampname_qc <- qcObj\$sampname_qc
    
    # Calculate PLR
    Y_norm <- normObj\$Yhat[[optK]]
    plr <- log(pmax(Y_qc, 0.0001) / pmax(Y_norm, 0.0001))
    ngs_plr <- lapply(seq_len(ncol(plr)), function(i) plr[, i])
    ngs_plr.pos <- lapply(seq_len(ncol(plr)), function(x) { return(cbind(start(ref_qc), end(ref_qc))) })
    save(sampname_qc, ngs_plr, ngs_plr.pos, file = paste0(projectname, 'plrObj_', chr, '_', optK, '.rda'))
    
    # -----------------------------------------------------------------------------
    # Stage 2: Call sequence variant BAFs from VCF using bambaf_from_vcf
    # -----------------------------------------------------------------------------
    
    projectname <- "icnv.demo."
    dir <- "."
    if (!file.exists("bam_vcf.list")) {
      stop("Required VCF list file 'bam_vcf.list' not found.")
    }
    
    bambaf_from_vcf(dir, 'bam_vcf.list', chr = 22, projectname) 
    load(paste0(projectname, 'bambaf_22.rda'))
    
    # -----------------------------------------------------------------------------
    # Stage 3: Convert SNP array intensity data using get_array_input and SVD
    # -----------------------------------------------------------------------------
    
    dir <- "."
    chr <- 22
    projectname <- "icnv.demo."
    pattern <- paste0('*.csv.arrayicnv\$')
    
    get_array_input(dir, pattern, chr, projectname)
    load(paste0(projectname, 'array_lrrbaf_', chr, '.rda'))
    
    # Standardize LRR
    lrr.sd <- mapply(function(x) {
      x = pmax(pmin(x, 100), -100)
      (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE)
    }, snp_lrr, SIMPLIFY = TRUE)
    
    lrr.sd.dena <- apply(lrr.sd, 2, function(x) { x[is.na(x)] = mean(x, na.rm = TRUE); return(x) })
    lrr.svd <- svd(t(lrr.sd.dena))
    save(lrr.svd, file = paste0(projectname, 'array_lrrbaf_svd_', chr, '.rda'))
    
    # Plot SVD variance explained
    pdf(paste0(projectname, 'array_lrrbaf_svd_variance_explained_', chr, '.pdf'))
    plot(x = seq_len(10), y = (lrr.svd\$d[1:10])^2 / sum(lrr.svd\$d^2),
         xlab = 'rank', ylab = 'D square', main = 'Variance explained', type = 'l')
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 4: Run integrative CNV detection using iCNV_detection
    # -----------------------------------------------------------------------------
    
    projectname <- 'icnv.demo.'
    
    pdf(paste0(projectname, "iCNV_detection_plots.pdf"))
    icnv_res0 <- iCNV_detection(ngs_plr, snp_lrr,
                                ngs_baf, snp_baf,
                                ngs_plr.pos, snp_lrr.pos,
                                ngs_baf.pos, snp_baf.pos,
                                projname = projectname, CN = 1, mu = c(-3, 0, 2), cap = TRUE, visual = 1)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # Stage 5: Format output using output_list and convert to Genome Browser format
    # -----------------------------------------------------------------------------
    
    icnv.output <- output_list(icnv_res0, sampname_qc, CN = 1)
    write.csv(icnv.output, file = paste0(projectname, "icnv_output_CN1.csv"), row.names = FALSE)
    
    # -----------------------------------------------------------------------------
    # Stage 6: Plot results using plotHMMscore and plotindi
    # -----------------------------------------------------------------------------
    
    pdf(paste0(projectname, "plotHMMscore.pdf"))
    plotHMMscore(icnv_res0, title = projectname)
    dev.off()
    
    icnv.output <- output_list(icnv_res = icnv_res0, sampleid = sampname_qc, CN = 0, min_size = 10000)
    write.csv(icnv.output, file = paste0(projectname, "icnv_output_CN0_min10000.csv"), row.names = FALSE)
    
    gb_input <- icnv_output_to_gb(22, icnv.output)
    write.table(gb_input, file = paste0(projectname, 'icnv_res_gb_chr', chr, '.tab'),
                quote = FALSE, col.names = FALSE, row.names = FALSE)
    
    # Plot individual results (defaulting to 24th individual or maximum available)
    I <- min(24, length(ngs_plr))
    pdf(paste0(projectname, "plotindi_individual_", I, ".pdf"))
    plotindi(ngs_plr, snp_lrr,
             ngs_baf, snp_baf,
             ngs_plr.pos, snp_lrr.pos,
             ngs_baf.pos, snp_baf.pos,
             icnv_res0, I)
    dev.off()

    writeLines(c(
        '"BIOC_ICNV_INTEGRATED_MULTI_PLATFORM_CNV_DETECTION":',
        paste0('    iCNV: ', as.character(packageVersion('iCNV')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_integrated_multi_platform_cnv_detection.csv versions.yml
    """
}

workflow BIOC_ICNV_INTEGRATED_MULTI_PLATFORM_CNV_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamFile, chr22_400_to_500.bed, bam_vcf.list, csv.arrayicnv ] ]

    main:
    BIOC_ICNV_INTEGRATED_MULTI_PLATFORM_CNV_DETECTION(ch_input)

    emit:
    tables   = BIOC_ICNV_INTEGRATED_MULTI_PLATFORM_CNV_DETECTION.out.tables
    plots    = BIOC_ICNV_INTEGRATED_MULTI_PLATFORM_CNV_DETECTION.out.plots
    objects  = BIOC_ICNV_INTEGRATED_MULTI_PLATFORM_CNV_DETECTION.out.objects
    versions = BIOC_ICNV_INTEGRATED_MULTI_PLATFORM_CNV_DETECTION.out.versions
}
