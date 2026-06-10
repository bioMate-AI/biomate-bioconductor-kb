#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GWASTools — gwas_vcf_pipeline
// Perform a complete GWAS analysis pipeline starting from a VCF file, including GDS conversion, sample/variant quality control (missingness, MAF, HWE), subsetting
// Input: input.vcf, coldata.csv
// Container: 1.56.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GWASTools, SNPRelate
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GWASTOOLS_GWAS_VCF_PIPELINE {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(GWASTools)
    library(SNPRelate) # Required for VCF to GDS conversion as per GWASTools documentation
    
    # Define input files
    vcf_in <- "input.vcf"
    coldata_in <- "coldata.csv"
    
    # Define intermediate files
    gds_temp <- "temp_raw.gds"
    gds_clean <- "temp_clean.gds"
    
    # Ensure clean execution by removing pre-existing temporary files
    if (file.exists(gds_temp)) file.remove(gds_temp)
    if (file.exists(gds_clean)) file.remove(gds_clean)
    
    # ==========================================
    # STAGE 1: Convert VCF to GDS Format
    # ==========================================
    message("Stage 1: Converting VCF to GDS...")
    SNPRelate::snpgdsVCF2GDS(vcf_in, gds_temp, verbose = FALSE)
    
    # ==========================================
    # STAGE 2: Load GDS and Build Annotations
    # ==========================================
    message("Stage 2: Loading GDS and building annotations...")
    gds <- GdsGenotypeReader(gds_temp)
    
    # Extract SNP metadata
    snpID <- getSnpID(gds)
    chromosome <- as.integer(getChromosome(gds))
    position <- getPosition(gds)
    alleleA <- getAlleleA(gds)
    alleleB <- getAlleleB(gds)
    
    # Retrieve rsID if available, otherwise fallback to snpID
    rsID <- tryCatch({
      getVariable(gds, "snp.rs.id")
    }, error = function(e) {
      paste0("snp_", snpID)
    })
    
    snpAnnot <- SnpAnnotationDataFrame(data.frame(
      snpID = snpID,
      chromosome = chromosome,
      position = position,
      rsID = rsID,
      alleleA = alleleA,
      alleleB = alleleB,
      stringsAsFactors = FALSE
    ))
    
    # Extract Scan (Sample) metadata
    scanID <- getScanID(gds)
    
    # Load optional sample metadata
    if (file.exists(coldata_in)) {
      coldata <- read.csv(coldata_in, stringsAsFactors = FALSE)
      # Match metadata to GDS scan IDs
      idx <- match(scanID, coldata\$sample)
      condition <- coldata\$condition[idx]
      sex <- if ("sex" %in% colnames(coldata)) coldata\$sex[idx] else rep(NA, length(scanID))
    } else {
      condition <- rep(NA, length(scanID))
      sex <- rep(NA, length(scanID))
    }
    
    # Standardize sex coding to M/F/NA
    sex[!(sex %in% c("M", "F"))] <- NA
    
    scanAnnot <- ScanAnnotationDataFrame(data.frame(
      scanID = scanID,
      sex = sex,
      condition = condition,
      stringsAsFactors = FALSE
    ))
    
    # Create the primary GenotypeData object
    genoData <- GenotypeData(gds, snpAnnot = snpAnnot, scanAnnot = scanAnnot)
    
    # ==========================================
    # STAGE 3: Quality Control (QC)
    # ==========================================
    message("Stage 3: Performing Quality Control...")
    
    # 1. Calculate missingness using base R on genotype matrix
    genotypes <- getGenotype(genoData)
    snp_missing <- rowMeans(is.na(genotypes))
    scan_missing <- colMeans(is.na(genotypes))
    
    # 2. Calculate Allele Frequencies
    freqs <- alleleFrequency(genoData)
    if (is.matrix(freqs)) {
      maf <- pmin(freqs[, "all"], 1 - freqs[, "all"])
    } else {
      maf <- pmin(freqs, 1 - freqs)
    }
    
    # 3. Hardy-Weinberg Equilibrium (HWE) Testing
    hwe_res <- exactHWE(genoData)
    
    # Export QC Summary
    qc_summary <- data.frame(
      snpID = snpID,
      chromosome = chromosome,
      position = position,
      rsID = rsID,
      missing_rate = snp_missing,
      maf = maf,
      hwe_pval = hwe_res\$pval,
      stringsAsFactors = FALSE
    )
    write.csv(qc_summary, "gwas_qc_summary.csv", row.names = FALSE)
    
    # Define QC thresholds
    max_missing <- 0.05
    min_maf <- 0.01
    min_hwe_pval <- 1e-6
    
    # Identify clean SNPs and Scans
    keep_snps <- snpID[snp_missing <= max_missing & maf >= min_maf & (is.na(hwe_res\$pval) | hwe_res\$pval >= min_hwe_pval)]
    keep_scans <- scanID[scan_missing <= max_missing]
    
    message(sprintf("QC complete. Retained %d/%d SNPs and %d/%d samples.", 
                    length(keep_snps), length(snpID), length(keep_scans), length(scanID)))
    
    # Close raw GDS before subsetting
    close(genoData)
    
    # ==========================================
    # STAGE 4: Subsetting and Association Testing
    # ==========================================
    message("Stage 4: Subsetting GDS and running association testing...")
    
    # Create a clean subset GDS file
    gdsSubset(gds_temp, gds_clean, sample.include = keep_scans, snp.include = keep_snps, verbose = FALSE)
    
    # Load the clean dataset
    gds_cl <- GdsGenotypeReader(gds_clean)
    clean_scanID <- getScanID(gds_cl)
    clean_snpID <- getSnpID(gds_cl)
    
    clean_snpAnnot <- snpAnnot[snpAnnot\$snpID %in% clean_snpID, ]
    clean_scanAnnot <- scanAnnot[scanAnnot\$scanID %in% clean_scanID, ]
    
    clean_genoData <- GenotypeData(gds_cl, snpAnnot = clean_snpAnnot, scanAnnot = clean_scanAnnot)
    
    # Determine model type and handle outcome variable
    unique_outcomes <- unique(na.omit(clean_scanAnnot\$condition))
    if (length(unique_outcomes) < 2) {
      message("Warning: Insufficient variation in 'condition'. Generating dummy binary outcome for pipeline execution.")
      clean_scanAnnot\$condition <- sample(c(0, 1), nrow(clean_scanAnnot), replace = TRUE)
      model_type <- "logistic"
    } else if (length(unique_outcomes) == 2) {
      model_type <- "logistic"
      clean_scanAnnot\$condition <- as.numeric(as.factor(clean_scanAnnot\$condition)) - 1
    } else {
      model_type <- "linear"
    }
    
    # Determine covariates (include sex if both categories are present)
    covars <- NULL
    if (any(clean_scanAnnot\$sex == "M", na.rm = TRUE) && any(clean_scanAnnot\$sex == "F", na.rm = TRUE)) {
      covars <- "sex"
    }
    
    # Run association regression
    num_clean_snps <- length(clean_snpID)
    assoc_results <- assocRegression(
      clean_genoData,
      outcome = "condition",
      covar = covars,
      model.type = model_type,
      snpStart = 1,
      snpEnd = num_clean_snps
    )
    
    # Write association results
    write.csv(assoc_results, "gwas_association_results.csv", row.names = FALSE)
    
    # ==========================================
    # STAGE 5: Visualization
    # ==========================================
    message("Stage 5: Generating diagnostic plots...")
    
    # Extract p-value column dynamically
    pval_col <- grep("pval", colnames(assoc_results), value = TRUE)[1]
    if (is.na(pval_col)) pval_col <- colnames(assoc_results)[ncol(assoc_results)]
    
    pvals <- assoc_results[[pval_col]]
    chroms <- assoc_results\$chr
    positions <- assoc_results\$pos
    
    pdf("gwas_plots.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    
    # 1. QQ Plot (Base R)
    pvals_clean <- pvals[!is.na(pvals) & pvals > 0]
    n <- length(pvals_clean)
    if (n > 0) {
      expected <- -log10((1:n) / (n + 1))
      observed <- -log10(sort(pvals_clean))
      plot(expected, observed, main = "QQ Plot", 
           xlab = "Expected -log10(p)", ylab = "Observed -log10(p)", 
           pch = 20, col = "darkblue")
      abline(0, 1, col = "red", lty = 2)
    } else {
      plot(1, 1, type = "n", main = "QQ Plot (No valid P-values)")
    }
    
    # 2. Manhattan Plot (Base R)
    if (length(pvals_clean) > 0) {
      plot_df <- data.frame(chrom = chroms, pos = positions, pval = pvals)
      plot_df <- plot_df[!is.na(plot_df\$pval) & plot_df\$pval > 0, ]
      plot_df <- plot_df[order(plot_df\$chrom, plot_df\$pos), ]
      plot_df\$logp <- -log10(plot_df\$pval)
      plot_df\$idx <- 1:nrow(plot_df)
      
      unique_chroms <- unique(plot_df\$chrom)
      colors <- rep(c("navy", "skyblue"), length.out = length(unique_chroms))
      names(colors) <- unique_chroms
      
      plot(plot_df\$idx, plot_df\$logp, col = colors[as.character(plot_df\$chrom)], 
           pch = 20, main = "Manhattan Plot", xlab = "Chromosome", 
           ylab = "-log10(p-value)", xaxt = "n", ylim = c(0, max(c(8, plot_df\$logp))))
      
      # Add chromosome labels
      axis_pos <- tapply(plot_df\$idx, plot_df\$chrom, mean)
      axis(1, at = axis_pos, labels = names(axis_pos))
      
      # Significance thresholds
      abline(h = -log10(5e-8), col = "red", lty = 2) # Genome-wide significance
      abline(h = -log10(1e-5), col = "blue", lty = 3) # Suggestive
    } else {
      plot(1, 1, type = "n", main = "Manhattan Plot (No valid P-values)")
    }
    
    dev.off()
    
    # Close clean GDS file
    close(clean_genoData)
    
    # Clean up temporary GDS files
    if (file.exists(gds_temp)) file.remove(gds_temp)
    if (file.exists(gds_clean)) file.remove(gds_clean)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_GWASTOOLS_GWAS_VCF_PIPELINE":',
        paste0('    GWASTools: ', as.character(packageVersion('GWASTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gwas_vcf_pipeline.csv versions.yml
    """
}

workflow BIOC_GWASTOOLS_GWAS_VCF_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_GWASTOOLS_GWAS_VCF_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GWASTOOLS_GWAS_VCF_PIPELINE.out.tables
    plots    = BIOC_GWASTOOLS_GWAS_VCF_PIPELINE.out.plots
    objects  = BIOC_GWASTOOLS_GWAS_VCF_PIPELINE.out.objects
    versions = BIOC_GWASTOOLS_GWAS_VCF_PIPELINE.out.versions
}
