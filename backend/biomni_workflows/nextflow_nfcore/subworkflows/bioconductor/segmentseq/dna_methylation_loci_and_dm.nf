#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: segmentSeq — dna_methylation_loci_and_dm
// Identify DNA methylation loci from bisulphite sequencing data and perform differential methylation analysis across replicate groups.
// Input: short_18B_C24_C24_trim.fastq_CG_methCalls.gz, short_Sample_17A_trimmed.fastq_CG_methCalls.gz, short_13_C24_col_trim.fastq_CG_methCalls.gz, short_Sample_28_trimmed.fastq_CG_methCalls.gz
// Container: quay.io/biocontainers/bioconductor-segmentseq:2.44.0--r45hdfd78af_0
// R packages: segmentSeq
// Bioconductor: 3.20 | R: 4.4
// Requires: segmentSeq
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load methylation call data using readMeths
//  * 2. [Visualization & Output] Plot methylation distributions using plotMethDistribution
//  * 3. [Core Analysis] Process alignment data into candidate segments using processAD
//  * 4. [Core Analysis] Perform heuristic segmentation based on methylation proportion using heuristicSeg
//  * 5. [Core Analysis] Merge split methylation segments using mergeMethSegs
//  * 6. [Core Analysis] Estimate posterior likelihoods on the defined loci using lociLikelihoods
//  * 7. [Input & Preparation] Define differential methylation models on the loci
//  * 8. [Core Analysis] Pre-calculate data structures to speed up estimation using methObservables
//  * 9. [Core Analysis] Set the beta-binomial non-conversion density function using densityFunction
//  * 10. [Core Analysis] Estimate prior distributions using getPriors
//  * 11. [Core Analysis] Calculate posterior likelihoods of differential methylation using getLikelihoods
//  * 12. [Core Analysis] Retrieve top differentially methylated regions using topCounts

nextflow.enable.dsl = 2

process BIOC_SEGMENTSEQ_DNA_METHYLATION_LOCI_AND_DM {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("segmentSeq")
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
    library(segmentSeq)
    library(parallel)
    
    # Define the input files in the working directory
    files <- c(
      "short_18B_C24_C24_trim.fastq_CG_methCalls.gz",
      "short_Sample_17A_trimmed.fastq_CG_methCalls.gz",
      "short_13_C24_col_trim.fastq_CG_methCalls.gz",
      "short_Sample_28_trimmed.fastq_CG_methCalls.gz"
    )
    
    # Verify that all input files exist in the working directory
    for (f in files) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing in working directory:", f))
      }
    }
    
    # Set up cluster for parallel processing (using NULL for sequential execution to ensure stability)
    cl <- NULL
    
    # 1. Load methylation call data using readMeths
    mD <- readMeths(
      files = files, 
      dir = ".", 
      libnames = c("A1", "A2", "B1", "B2"), 
      replicates = c("A", "A", "B", "B"),
      nonconversion = c(0.004777, 0.005903, 0.016514, 0.006134)
    )
    
    # 2. Plot methylation distributions using plotMethDistribution
    pdf("methylation_distributions.pdf", width = 10, height = 8)
    par(mfrow = c(2, 1))
    dists <- plotMethDistribution(mD, main = "Distributions of methylation", chr = "Chr1")
    plotMethDistribution(
      mD,
      subtract = rowMeans(sapply(dists, function(x) x[, 2])),
      main = "Differences between distributions", 
      chr = "Chr1"
    )
    dev.off()
    
    # 3. Process alignment data into candidate segments using processAD
    sD <- processAD(mD, cl = cl)
    
    # 4. Perform heuristic segmentation based on methylation proportion using heuristicSeg
    thresh <- 0.2
    hS <- heuristicSeg(sD = sD, aD = mD, prop = thresh, cl = cl, gap = 100, getLikes = FALSE)
    
    # 5. Merge split methylation segments using mergeMethSegs
    hS <- mergeMethSegs(hS, mD, gap = 5000, cl = cl)
    
    # 6. Estimate posterior likelihoods on the defined loci using lociLikelihoods
    hSL <- lociLikelihoods(hS, mD, cl = cl)
    
    # 7. Define differential methylation models on the loci
    groups(hSL) <- list(NDE = c(1, 1, 1, 1), DE = c("A", "A", "B", "B"))
    
    # 8. Pre-calculate data structures to speed up estimation using methObservables
    hSL <- methObservables(hSL)
    
    # 9. Set the beta-binomial non-conversion density function using densityFunction
    densityFunction(hSL) <- bbNCDist
    
    # 10. Estimate prior distributions using getPriors
    hSL <- getPriors(hSL, cl = cl)
    
    # 11. Calculate posterior likelihoods of differential methylation using getLikelihoods
    hSL <- getLikelihoods(hSL, cl = cl)
    
    # 12. Retrieve top differentially methylated regions using topCounts
    de_results <- topCounts(hSL, "DE", number = Inf)
    
    # Write outputs to files
    write.csv(de_results, "differentially_methylated_regions.csv", row.names = TRUE)
    saveRDS(hSL, "hSL_final_results.rds")
    
    # Plot identified loci for visualization
    pdf("methylation_loci_visualization.pdf", width = 10, height = 8)
    plotMeth(mD, hSL, chr = "Chr1", limits = c(1, 50000), cap = 10)
    dev.off()
    
    # Clean up cluster if it was initialized
    if (!is.null(cl)) {
      stopCluster(cl)
    }

    writeLines(c(
        '"BIOC_SEGMENTSEQ_DNA_METHYLATION_LOCI_AND_DM":',
        paste0('    segmentSeq: ', as.character(packageVersion('segmentSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dna_methylation_loci_and_dm.csv versions.yml
    """
}

workflow BIOC_SEGMENTSEQ_DNA_METHYLATION_LOCI_AND_DM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ short_18B_C24_C24_trim.fastq_CG_methCalls.gz, short_Sample_17A_trimmed.fastq_CG_methCalls.gz, short_13_C24_col_trim.fastq_CG_methCalls.gz, short_Sample_28_trimmed.fastq_CG_methCalls.gz ] ]

    main:
    BIOC_SEGMENTSEQ_DNA_METHYLATION_LOCI_AND_DM(ch_input)

    emit:
    tables   = BIOC_SEGMENTSEQ_DNA_METHYLATION_LOCI_AND_DM.out.tables
    plots    = BIOC_SEGMENTSEQ_DNA_METHYLATION_LOCI_AND_DM.out.plots
    objects  = BIOC_SEGMENTSEQ_DNA_METHYLATION_LOCI_AND_DM.out.objects
    versions = BIOC_SEGMENTSEQ_DNA_METHYLATION_LOCI_AND_DM.out.versions
}
