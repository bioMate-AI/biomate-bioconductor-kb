#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNVrd2 — complex_locus_bayesian_clustering
// Measure copy number at complex/multiallelic loci across multiple populations using Bayesian clustering with population-specific priors, and identify tag SNPs.
// Input: ccl3l1data, chr17.34800000.34830000.vcf.gz
// Container: quay.io/biocontainers/bioconductor-cnvrd2:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CNVrd2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Obtain prior information from a single population with clear clusters using groupCNVs
//  * 2. [Core Analysis] Set prior parameters (means, SDs, proportions, distances)
//  * 3. [Core Analysis] Run Bayesian clustering across all populations using groupBayesianCNVs
//  * 4. [Core Analysis] Identify tag SNPs across multiple populations using calculateLDSNPandCNV

nextflow.enable.dsl = 2

process BIOC_CNVRD2_COMPLEX_LOCUS_BAYESIAN_CLUSTERING {
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
    library(CNVrd2)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read ccl3l1data
    if (file.exists("ccl3l1data")) {
      ccl3l1data <- tryCatch({
        readRDS("ccl3l1data")
      }, error = function(e) {
        tryCatch({
          read.csv("ccl3l1data", header = TRUE, stringsAsFactors = FALSE)
        }, error = function(e2) {
          read.table("ccl3l1data", header = TRUE, stringsAsFactors = FALSE)
        })
      })
    } else if (file.exists("ccl3l1data.csv")) {
      ccl3l1data <- read.csv("ccl3l1data.csv", header = TRUE, stringsAsFactors = FALSE)
    } else if (file.exists("ccl3l1data.rds")) {
      ccl3l1data <- readRDS("ccl3l1data.rds")
    } else {
      stop("Error: Required input file 'ccl3l1data' (or ccl3l1data.csv/rds) not found in the working directory.")
    }
    
    # Define VCF file path
    vcfFileCCL3L1 <- "chr17.34800000.34830000.vcf.gz"
    if (!file.exists(vcfFileCCL3L1)) {
      stop(paste("Error: Required VCF file", vcfFileCCL3L1, "not found in the working directory."))
    }
    
    # ==========================================
    # 2. Prepare Data for Prior Estimation
    # ==========================================
    
    # Extract European-ancestry samples to obtain prior information
    xyEuro <- ccl3l1data[grep("CEU|TSI|IBS|GBR|FIN", ccl3l1data[, 2]), ]
    yEuro <- xyEuro[, 3]
    names(yEuro) <- xyEuro[, 1]
    
    # Save a diagnostic plot of the input segmentation scores
    pdf("ccl3l1_segmentation_scores_histogram.pdf", width = 10, height = 5)
    par(mfrow = c(1, 2))
    hist(ccl3l1data\$SS, 100, main = "All Populations SS", xlab = "Segmentation Score")
    hist(yEuro, 100, main = "European Populations SS", xlab = "Segmentation Score")
    dev.off()
    
    # ==========================================
    # 3. Stage 1: Obtain Prior Information
    # ==========================================
    
    objectClusterEuroCCL3L1 <- new("clusteringCNVs", x = yEuro, k = 5)
    europeanCCL3L1Groups <- groupCNVs(Object = objectClusterEuroCCL3L1)
    
    # ==========================================
    # 4. Stage 2: Set Prior Parameters
    # ==========================================
    
    lambda0 <- as.numeric(europeanCCL3L1Groups\$m)
    sdEM <- as.numeric(europeanCCL3L1Groups\$sigma)
    pEM <- as.numeric(europeanCCL3L1Groups\$p)
    
    # Adjust standard deviation for the fifth group to avoid an overly wide mixture component
    sdEM[5] <- sdEM[4]
    
    # Prepare all segmentation scores
    ccl3l1X <- ccl3l1data\$SS
    names(ccl3l1X) <- as.character(ccl3l1data\$Name)
    ccl3l1X <- sort(ccl3l1X)
    xData <- ccl3l1X
    
    # Set prior parameters for Bayesian clustering
    nGroups <- 10
    sd <- c(1, 1, 5, 1, 1) 
    alpha0 <- c(3, 29, 44, 18, 7, 5, rep(2, nGroups - length(pEM) - 1))
    distanceBetweenGroups <- 0.485
    
    # ==========================================
    # 5. Stage 3: Run Bayesian Clustering
    # ==========================================
    
    set.seed(123)
    groupCCL3L1allPops <- groupBayesianCNVs(xData = xData, nGroups = nGroups,
                                            lambda0 = lambda0,
                                            sd0 = sdEM, alpha0 = alpha0,
                                            distanceBetweenGroups = distanceBetweenGroups,
                                            sdOftau = sd,
                                            rightLimit = 4)
    
    # Save clustering results
    saveRDS(europeanCCL3L1Groups, "europeanCCL3L1Groups.rds")
    saveRDS(groupCCL3L1allPops, "groupCCL3L1allPops.rds")
    
    # ==========================================
    # 6. Stage 4: Identify Tag SNPs
    # ==========================================
    
    rownames(ccl3l1data) <- ccl3l1data[, 1]
    allPops <- c("TSI", "CEU", "GBR", "FIN", "IBS")
    
    tagSNPandINDELofCCL3L1 <- calculateLDSNPandCNV(sampleCNV = ccl3l1data,
                                                vcfFile = vcfFileCCL3L1, cnvColumn = 4,
                                                population = allPops, popColumn = 2,
                                                nChunkForVcf = 5, chr = "17",
                                                st = 34800000, en = 34830000 )
    
    # Save tag SNP results for each population
    for (ii in 1:length(allPops)) {
      pop_name <- allPops[ii]
      output_file <- paste("TagSNPforPop_", pop_name, ".csv", sep = "")
      write.table(tagSNPandINDELofCCL3L1[[ii]], 
                  file = output_file, 
                  quote = FALSE, sep = ",", row.names = TRUE)
    }
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_CNVRD2_COMPLEX_LOCUS_BAYESIAN_CLUSTERING":',
        paste0('    CNVrd2: ', as.character(packageVersion('CNVrd2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_complex_locus_bayesian_clustering.csv versions.yml
    """
}

workflow BIOC_CNVRD2_COMPLEX_LOCUS_BAYESIAN_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ccl3l1data, chr17.34800000.34830000.vcf.gz ] ]

    main:
    BIOC_CNVRD2_COMPLEX_LOCUS_BAYESIAN_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_CNVRD2_COMPLEX_LOCUS_BAYESIAN_CLUSTERING.out.tables
    plots    = BIOC_CNVRD2_COMPLEX_LOCUS_BAYESIAN_CLUSTERING.out.plots
    objects  = BIOC_CNVRD2_COMPLEX_LOCUS_BAYESIAN_CLUSTERING.out.objects
    versions = BIOC_CNVRD2_COMPLEX_LOCUS_BAYESIAN_CLUSTERING.out.versions
}
