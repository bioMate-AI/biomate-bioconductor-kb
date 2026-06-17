#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqvartools — variant_qc_and_association_testing
// Convert VCF to GDS, perform variant quality control checks (TiTv, heterozygosity, PCA, HWE, Mendelian errors), and run single-variant association tests.
// Input: file.vcf, pedigree_data.RData
// Container: quay.io/biocontainers/bioconductor-seqvartools:1.48.0--r45hdfd78af_0
// R packages: Biobase, GenomicRanges, SeqVarTools
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQVARTOOLS_VARIANT_QC_AND_ASSOCIATION_TESTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-seqvartools:1.48.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biobase", "GenomicRanges", "SeqVarTools")
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
    library(SeqVarTools)
    library(GenomicRanges)
    library(Biobase)
    
    # Define input files
    vcffile <- "file.vcf"
    gdsfile <- "tmp.gds"
    pedigree_file <- "pedigree_data.RData"
    
    # --- Convert VCF to GDS format and open it ---
    seqVCF2GDS(vcffile, gdsfile, verbose=FALSE)
    gds <- seqOpen(gdsfile)
    gds
    
    # --- Extract basic variant info ---
    head(refChar(gds))
    head(altChar(gds))
    table(nAlleles(gds))
    
    multi.allelic <- which(nAlleles(gds) > 2)
    if (length(multi.allelic) > 0) {
      altChar(gds)[multi.allelic]
      altChar(gds, n=1)[multi.allelic]
      altChar(gds, n=2)[multi.allelic]
    }
    
    table(isSNV(gds))
    if (length(multi.allelic) > 0) {
      isSNV(gds)[multi.allelic]
    }
    
    head(seqGetData(gds, "chromosome"))
    head(seqGetData(gds, "position"))
    granges(gds)
    head(seqGetData(gds, "sample.id"))
    head(seqGetData(gds, "variant.id"))
    
    rsID <- seqGetData(gds, "annotation/id")
    head(rsID)
    length(unique(rsID)) == length(rsID)
    
    # Ensure rsID is unique and non-empty before setting variant IDs
    if (any(is.na(rsID)) || any(rsID == "") || length(unique(rsID)) != length(rsID)) {
      rsID[is.na(rsID) | rsID == ""] <- paste0("var", seq_along(rsID))[is.na(rsID) | rsID == ""]
      rsID <- make.unique(rsID)
    }
    
    seqClose(gds)
    setVariantID(gdsfile, rsID)
    gds <- seqOpen(gdsfile)
    head(seqGetData(gds, "variant.id"))
    
    # Genotype extraction
    geno <- getGenotype(gds)
    dim(geno)
    geno[1:min(10, nrow(geno)), 1:min(5, ncol(geno))]
    
    geno <- getGenotypeAlleles(gds)
    geno[1:min(10, nrow(geno)), 1:min(5, ncol(geno))]
    
    samp.id <- seqGetData(gds, "sample.id")[1:min(10, length(seqGetData(gds, "sample.id")))]
    var.id <- seqGetData(gds, "variant.id")[1:min(5, length(seqGetData(gds, "variant.id")))]
    applyMethod(gds, getGenotype, variant=var.id, sample=samp.id)
    
    # Genomic Ranges query (using the first chromosome dynamically)
    first_chrom <- as.character(seqGetData(gds, "chromosome")[1])
    gr <- GRanges(seqnames=first_chrom, IRanges(start=1, end=250000000))
    geno <- applyMethod(gds, getGenotype, variant=gr)
    dim(geno)
    
    # Open PDF for all QC and association plots
    pdf("qc_and_association_plots.pdf", width=10, height=8)
    
    # --- Calculate QC metrics ---
    titv(gds)
    head(titv(gds, by.sample=TRUE))
    
    binVar <- function(var, names, breaks) {
      names(var) <- names
      var <- sort(var)
      mids <- breaks[1:length(breaks)-1] + 
        (breaks[2:length(breaks)] - breaks[1:length(breaks)-1])/2
      bins <- cut(var, breaks, labels=mids, right=FALSE)
      split(names(var), bins)
    }
    
    variant.id <- seqGetData(gds, "variant.id")
    afreq <- alleleFrequency(gds)
    maf <- pmin(afreq, 1-afreq)
    maf.bins <- binVar(maf, variant.id, seq(0,0.5,0.02))
    nbins <- length(maf.bins)
    titv.maf <- rep(NA, nbins)
    for (i in 1:nbins) {
      capture.output(titv.maf[i] <- applyMethod(gds, titv, variant=maf.bins[[i]]))
    }
    plot(as.numeric(names(maf.bins)), titv.maf, xlab="MAF", ylab="TiTv")
    
    miss <- missingGenotypeRate(gds)
    miss.bins <- binVar(miss, variant.id, c(seq(0,0.5,0.05),1))
    nbins <- length(miss.bins)
    titv.miss <- rep(NA, nbins)
    for (i in 1:nbins) {
      capture.output(titv.miss[i] <- applyMethod(gds, titv, variant=miss.bins[[i]]))
    }
    plot(as.numeric(names(miss.bins)), titv.miss, xlab="missing rate", ylab="TiTv")
    
    # Optional depth calculation (wrapped in tryCatch in case DP is not in VCF)
    tryCatch({
      depth <- seqApply(gds, "annotation/format/DP", mean, margin="by.variant", 
                        as.is="double", na.rm=TRUE)
      depth.bins <- binVar(depth, variant.id, seq(0,200,20))
      nbins <- length(depth.bins)
      titv.depth <- rep(NA, nbins)
      for (i in 1:nbins) {
        capture.output(titv.depth[i] <- applyMethod(gds, titv, variant=depth.bins[[i]]))
      }
      plot(as.numeric(names(depth.bins)), titv.depth, xlab="mean depth", ylab="TiTv")
    }, error = function(e) {
      message("DP format field not found or error in depth calculation: ", e\$message)
    })
    
    miss.var <- missingGenotypeRate(gds, margin="by.variant")
    het.var <- heterozygosity(gds, margin="by.variant")
    filt <- seqGetData(gds, "variant.id")[miss.var <= 0.1 & het.var <= 0.6]
    
    # Ensure we have variants left after filtering
    if (length(filt) == 0) {
      filt <- seqGetData(gds, "variant.id")
    }
    
    seqSetFilter(gds, variant.id=filt)
    hethom <- hethom(gds)
    hist(hethom, main="", xlab="Het/Hom Non-Ref")
    seqSetFilter(gds)
    
    # --- Population structure and Hardy-Weinberg Equilibrium ---
    pc <- pca(gds)
    saveRDS(pc, "pca_results.rds")
    names(pc)
    plot(pc\$eigenvect[,1], pc\$eigenvect[,2])
    
    hw <- hwe(gds)
    write.csv(hw, "hwe_results.csv", row.names=FALSE)
    pval <- -log10(sort(hw\$p))
    hw.perm <- hwe(gds, permute=TRUE)
    x <- -log10(sort(hw.perm\$p))
    plot(x, pval, xlab="-log10(expected P)", ylab="-log10(observed P)")	
    abline(0,1,col="red")
    hist(hw\$f)
    
    ic <- inbreedCoeff(gds, margin="by.sample")
    range(ic)
    
    # --- Check for Mendelian errors using pedigree data ---
    loaded_objs <- load(pedigree_file)
    # Ensure the loaded pedigree object is correctly named 'pedigree'
    if (!"pedigree" %in% loaded_objs) {
      for (obj in loaded_objs) {
        if (is.data.frame(get(obj))) {
          pedigree <- get(obj)
          break
        }
      }
    }
    
    err <- mendelErr(gds, pedigree, verbose=FALSE)
    saveRDS(err, "mendelian_errors.rds")
    table(err\$by.variant)
    err\$by.trio
    
    # --- Combine GDS and sample annotation into a SeqVarData ---
    sample.id <- seqGetData(gds, "sample.id")
    pedigree <- pedigree[match(sample.id, pedigree\$sample.id),]
    sample.data <- AnnotatedDataFrame(pedigree)
    seqData <- SeqVarData(gds, sample.data)
    
    # Continuous phenotype association (Linear regression)
    assoc <- regression(seqData, outcome="phenotype", covar="sex",
                        model.type="linear")
    write.csv(assoc, "association_results_linear.csv", row.names=FALSE)
    head(assoc)
    pval <- -log10(sort(assoc\$Wald.Pval))
    n <- length(pval)
    x <- -log10((1:n)/n)
    plot(x, pval, xlab="-log10(expected P)", ylab="-log10(observed P)")
    abline(0, 1, col = "red")
    
    # Binary phenotype association (Firth regression)
    assoc <- regression(seqData, outcome="case.status", covar="sex",
                        model.type="firth")
    write.csv(assoc, "association_results_firth.csv", row.names=FALSE)
    head(assoc)
    pval <- -log10(sort(assoc\$PPL.Pval))
    n <- length(pval)
    x <- -log10((1:n)/n)
    plot(x, pval, xlab="-log10(expected P)", ylab="-log10(observed P)")
    abline(0, 1, col = "red")
    
    # Close PDF device
    dev.off()
    
    # Clean up and close GDS
    seqClose(gds)
    unlink(gdsfile)

    writeLines(c(
        '"BIOC_SEQVARTOOLS_VARIANT_QC_AND_ASSOCIATION_TESTING":',
        paste0('        seqvartools: ', as.character(packageVersion("seqvartools")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variant_qc_and_association_testing.csv versions.yml
    """
}

workflow BIOC_SEQVARTOOLS_VARIANT_QC_AND_ASSOCIATION_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.vcf, pedigree_data.RData ] ]

    main:
    BIOC_SEQVARTOOLS_VARIANT_QC_AND_ASSOCIATION_TESTING(ch_input)

    emit:
    tables   = BIOC_SEQVARTOOLS_VARIANT_QC_AND_ASSOCIATION_TESTING.out.tables
    plots    = BIOC_SEQVARTOOLS_VARIANT_QC_AND_ASSOCIATION_TESTING.out.plots
    objects  = BIOC_SEQVARTOOLS_VARIANT_QC_AND_ASSOCIATION_TESTING.out.objects
    versions = BIOC_SEQVARTOOLS_VARIANT_QC_AND_ASSOCIATION_TESTING.out.versions
}
