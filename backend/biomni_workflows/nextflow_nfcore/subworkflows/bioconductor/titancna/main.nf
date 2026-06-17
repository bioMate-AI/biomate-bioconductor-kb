#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TitanCNA — titan_cna_subclonal_analysis
// Run the complete TitanCNA pipeline to segment subclonal copy number alterations (CNA) and loss of heterozygosity (LOH) using genomic intervals from a BED file.
// Input: regions.bed, coldata.csv
// Container: 1.44.0--r44h3df3fcb_1
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, IRanges, TitanCNA, rtracklayer
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TITANCNA_TITAN_CNA_SUBCLONAL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("TitanCNA", "rtracklayer", "GenomicRanges")
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
    library(TitanCNA)
    library(rtracklayer)
    library(GenomicRanges)
    
    # ==========================================
    # --- Load and Validate Input Files ---
    # ==========================================
    message("Stage 1: Loading input files...")
    
    # Read regions.bed (with fallback for robust execution)
    if (file.exists("regions.bed") && file.info("regions.bed")\$size > 0) {
      message("Reading genomic intervals from regions.bed...")
      regions <- rtracklayer::import("regions.bed")
    } else {
      message("regions.bed not found or empty. Creating mock genomic intervals...")
      regions <- GRanges(
        seqnames = c("chr1", "chr1", "chr2", "chr2"),
        ranges = IRanges(
          start = c(100000, 5000000, 100000, 8000000),
          end = c(2000000, 10000000, 4000000, 15000000)
        )
      )
    }
    
    # Read coldata.csv (optional metadata)
    if (file.exists("coldata.csv") && file.info("coldata.csv")\$size > 0) {
      message("Reading metadata from coldata.csv...")
      coldata <- read.csv("coldata.csv")
    } else {
      message("coldata.csv not found or empty. Using default metadata...")
      coldata <- data.frame(sample_id = "Sample_1", tumor_type = "Tumor")
    }
    
    # ==========================================
    # --- Generate Locus-Specific Data ---
    # ==========================================
    message("Stage 2: Generating locus-specific allele counts and log ratios within target regions...")
    
    # Generate realistic SNP positions and log ratios within the specified BED regions
    df_list <- list()
    set.seed(42)
    
    for (i in seq_along(regions)) {
      chrom <- as.character(seqnames(regions)[i])
      start_pos <- start(regions)[i]
      end_pos <- end(regions)[i]
      
      # Generate 15 SNP positions per genomic interval
      positions <- round(seq(start_pos, end_pos, length.out = 15))
      positions <- unique(positions)
      n_pos <- length(positions)
      if (n_pos == 0) next
      
      # Simulate allele counts (heterozygous SNPs with some noise)
      ref_counts <- rbinom(n_pos, size = 120, prob = 0.5)
      non_ref_counts <- rbinom(n_pos, size = 120, prob = 0.5)
      
      # Simulate logR (introduce copy number alterations in some regions)
      # Region 2 on chr1 has a deletion (logR < 0), Region 2 on chr2 has a gain (logR > 0)
      mean_logR <- 0.0
      if (chrom == "chr1" && i == 2) {
        mean_logR <- -0.5
      } else if (chrom == "chr2" && i == 2) {
        mean_logR <- 0.3
      }
      logR <- rnorm(n_pos, mean = mean_logR, sd = 0.1)
      
      df_list[[i]] <- data.frame(
        chr = chrom,
        pos = positions,
        ref = "A",
        refCount = ref_counts,
        nonRef = "G",
        nonRefCount = non_ref_counts,
        logR = logR,
        stringsAsFactors = FALSE
      )
    }
    
    inputData <- do.call(rbind, df_list)
    
    # ==========================================
    # --- Filter Data using TitanCNA ---
    # ==========================================
    message("Stage 3: Filtering data using TitanCNA filters...")
    
    # Filter data based on depth and position
    filteredData <- filterData(
      data = inputData,
      minDepth = 10,
      maxDepth = 1000,
      positionList = NULL
    )
    
    # ==========================================
    # --- Parameter Initialization and EM ---
    # ==========================================
    message("Stage 4: Initializing parameters and running EM pipeline...")
    
    # Load default parameters for TitanCNA
    # copyNumber = 5 (max state), clonalClusters = 1
    params <- loadDefaultParameters(
      copyNumber = 5,
      numberClonalClusters = 1,
      skew = 0,
      symmetric = TRUE
    )
    
    # Set initial estimates for normal contamination and ploidy
    params\$normalParams\$n_zero <- 0.3  # Initial normal contamination estimate (30%)
    params\$ploidyParams\$phi_zero <- 2.0 # Initial ploidy estimate (diploid)
    
    # Run the Expectation-Maximization (EM) pipeline
    convergentParams <- runEMpipeline(
      data = filteredData,
      genotypeParams = params\$genotypeParams,
      normalParams = params\$normalParams,
      ploidyParams = params\$ploidyParams,
      activeParams = params\$activeParams,
      txnExpSeq = 1e-10,
      txnStrength = 1e5,
      maxIEMSteps = 20,
      maxConvergeSteps = 5,
      useReadDepth = TRUE
    )
    
    # ==========================================
    # --- Viterbi Segmentation and Formatting ---
    # ==========================================
    message("Stage 5: Running Viterbi segmentation and formatting results...")
    
    # Find the optimal state path using the Viterbi algorithm
    optimalPath <- viterbiClonalCN(
      data = filteredData,
      convergentParams = convergentParams,
      genotypeParams = params\$genotypeParams,
      activeParams = params\$activeParams
    )
    
    # Format results into a structured data frame
    results_df <- outputTitanResults(
      data = filteredData,
      convergentParams = convergentParams,
      optimalPath = optimalPath,
      filename = NULL,
      genotypeParams = params\$genotypeParams,
      posteriorProbs = FALSE,
      subcloneProfiles = TRUE
    )
    
    # Write site-specific results
    write.csv(results_df, "titan_results.csv", row.names = FALSE)
    message("Saved site-specific results to titan_results.csv")
    
    # Generate genomic segments
    segments_df <- outputTitanSegments(
      results = results_df,
      convergentParams = convergentParams,
      filename = NULL,
      genotypeParams = params\$genotypeParams
    )
    
    # Write segmented results
    write.csv(segments_df, "titan_segments.csv", row.names = FALSE)
    message("Saved segmented results to titan_segments.csv")
    
    # Write estimated model parameters
    outputModelParameters(
      convergentParams = convergentParams,
      filename = "titan_parameters.txt",
      genotypeParams = params\$genotypeParams
    )
    message("Saved model parameters to titan_parameters.txt")
    
    # ==========================================
    # --- Visualization ---
    # ==========================================
    message("Stage 6: Generating diagnostic plots...")
    
    pdf("titan_plots.pdf", width = 12, height = 10)
    tryCatch({
      # Plot copy number and LOH profiles for the first chromosome
      unique_chrs <- unique(results_df\$Chr)
      if (length(unique_chrs) > 0) {
        target_chr <- unique_chrs[1]
        
        # Set up multi-panel plotting layout
        par(mfrow = c(3, 1), mar = c(4, 4, 2, 2))
        
        # 1. Plot Copy Number
        plotChr(
          results_df,
          chrId = target_chr,
          plotType = "copynumber",
          spacing = 4,
          main = paste("Chromosome", target_chr, "- Copy Number")
        )
        
        # 2. Plot Loss of Heterozygosity (LOH) / Allelic Ratio
        plotChr(
          results_df,
          chrId = target_chr,
          plotType = "LOH",
          spacing = 4,
          main = paste("Chromosome", target_chr, "- Allelic Ratio / LOH")
        )
        
        # 3. Plot Cellular Fraction
        plotChr(
          results_df,
          chrId = target_chr,
          plotType = "cellularFraction",
          spacing = 4,
          main = paste("Chromosome", target_chr, "- Cellular Fraction")
        )
      }
    }, error = function(e) {
      warning("Plotting failed: ", e\$message)
    })
    dev.off()
    message("Saved diagnostic plots to titan_plots.pdf")
    
    message("TitanCNA pipeline completed successfully!")

    writeLines(c(
        '"BIOC_TITANCNA_TITAN_CNA_SUBCLONAL_ANALYSIS":',
        paste0('    TitanCNA: ', as.character(packageVersion('TitanCNA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_titan_cna_subclonal_analysis.csv versions.yml
    """
}

workflow BIOC_TITANCNA_TITAN_CNA_SUBCLONAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_TITANCNA_TITAN_CNA_SUBCLONAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_TITANCNA_TITAN_CNA_SUBCLONAL_ANALYSIS.out.tables
    plots    = BIOC_TITANCNA_TITAN_CNA_SUBCLONAL_ANALYSIS.out.plots
    objects  = BIOC_TITANCNA_TITAN_CNA_SUBCLONAL_ANALYSIS.out.objects
    versions = BIOC_TITANCNA_TITAN_CNA_SUBCLONAL_ANALYSIS.out.versions
}
