#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MBASED — single_sample_ase
// Detect allele-specific gene expression (ASE) in a single sample using SNV-level RNA-seq counts.
// Input: snv_coordinates.bed, rna_seq_counts.tsv
// Container: quay.io/biocontainers/bioconductor-mbased:1.44.0--r45hdfd78af_0
// R packages: BiocParallel, GenomicRanges, SummarizedExperiment, MBASED
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, GenomicRanges, MBASED, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define SNV coordinates and gene assignments using GRanges
//  * 2. [Visualization & Output] Construct a SummarizedExperiment with allele count assays
//  * 3. [Core Analysis] Run runMBASED to calculate gene-level ASE and locus-level statistics
//  * 4. [Visualization & Output] Extract and summarize the results

nextflow.enable.dsl = 2

process BIOC_MBASED_SINGLE_SAMPLE_ASE {
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
    .bm_deps <- c("BiocParallel", "GenomicRanges", "SummarizedExperiment", "MBASED")
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
    library(GenomicRanges)
    library(SummarizedExperiment)
    library(MBASED)
    library(BiocParallel)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Check if input files exist
    if (!file.exists("snv_coordinates.bed")) {
      stop("Error: 'snv_coordinates.bed' not found in the working directory.")
    }
    if (!file.exists("rna_seq_counts.tsv")) {
      stop("Error: 'rna_seq_counts.tsv' not found in the working directory.")
    }
    
    # Read SNV coordinates (BED format)
    # Expected columns: chrom, start, end, name, score, strand, aseID, allele1, allele2
    bed_data <- read.table("snv_coordinates.bed", header=FALSE, sep="\t", stringsAsFactors=FALSE)
    colnames(bed_data)[1:3] <- c("seqnames", "start", "end")
    if (ncol(bed_data) >= 4) colnames(bed_data)[4] <- "name"
    if (ncol(bed_data) >= 7) colnames(bed_data)[7] <- "aseID"
    if (ncol(bed_data) >= 8) colnames(bed_data)[8] <- "allele1"
    if (ncol(bed_data) >= 9) colnames(bed_data)[9] <- "allele2"
    
    # Construct GRanges object (converting 0-based BED start to 1-based IRanges)
    mySNVs <- GRanges(
      seqnames = bed_data\$seqnames,
      ranges = IRanges(start = bed_data\$start + 1, end = bed_data\$end),
      aseID = bed_data\$aseID,
      allele1 = bed_data\$allele1,
      allele2 = bed_data\$allele2
    )
    names(mySNVs) <- bed_data\$name
    
    # Read RNA-seq counts
    # Expected columns: snvID, lociAllele1Counts, lociAllele2Counts
    counts_data <- read.table("rna_seq_counts.tsv", header=TRUE, sep="\t", stringsAsFactors=FALSE)
    rownames(counts_data) <- counts_data\$snvID
    
    # Align counts with the GRanges object
    counts_data <- counts_data[names(mySNVs), ]
    
    # ==========================================
    # 2. Construct SummarizedExperiment Object
    # ==========================================
    mySample <- SummarizedExperiment(
      assays=list(
        lociAllele1Counts=matrix(
          counts_data\$lociAllele1Counts,
          ncol=1,
          dimnames=list(
           names(mySNVs), 
           'mySample'
          )
        ),
        lociAllele2Counts=matrix(
          counts_data\$lociAllele2Counts,
          ncol=1, 
          dimnames=list(
           names(mySNVs), 
           'mySample'
          )
        )
      ),
      rowRanges=mySNVs
    )
    
    # ==========================================
    # 3. Run MBASED Analysis
    # ==========================================
    ASEresults_1s_haplotypesKnown <- runMBASED(
      ASESummarizedExperiment=mySample,
      isPhased=TRUE,
      numSim=10^6,
      BPPARAM = SerialParam()
    )
    
    # Explore the return object (as documented)
    class(ASEresults_1s_haplotypesKnown)
    names(assays(ASEresults_1s_haplotypesKnown))
    assays(ASEresults_1s_haplotypesKnown)\$majorAlleleFrequency
    assays(ASEresults_1s_haplotypesKnown)\$pValueASE
    assays(ASEresults_1s_haplotypesKnown)\$pValueHeterogeneity
    rowRanges(ASEresults_1s_haplotypesKnown)
    names(metadata(ASEresults_1s_haplotypesKnown))
    class(metadata(ASEresults_1s_haplotypesKnown)\$locusSpecificResults)
    names(assays(metadata(ASEresults_1s_haplotypesKnown)\$locusSpecificResults))
    assays(metadata(ASEresults_1s_haplotypesKnown)\$locusSpecificResults)\$allele1IsMajor
    assays(metadata(ASEresults_1s_haplotypesKnown)\$locusSpecificResults)\$MAF
    rowRanges(metadata(ASEresults_1s_haplotypesKnown)\$locusSpecificResults)
    
    # ==========================================
    # 4. Summarize and Export Results
    # ==========================================
    summarizeASEResults_1s <- function(MBASEDOutput) {
      geneOutputDF <- data.frame(
       majorAlleleFrequency=assays(MBASEDOutput)\$majorAlleleFrequency[,1],
       pValueASE=assays(MBASEDOutput)\$pValueASE[,1],  
       pValueHeterogeneity=assays(MBASEDOutput)\$pValueHeterogeneity[,1]
      )   
      lociOutputGR <- rowRanges(metadata(MBASEDOutput)\$locusSpecificResults)
      lociOutputGR\$allele1IsMajor <- assays(metadata(MBASEDOutput)\$locusSpecificResults)\$allele1IsMajor[,1]
      lociOutputGR\$MAF <- assays(metadata(MBASEDOutput)\$locusSpecificResults)\$MAF[,1]
      lociOutputList <- split(lociOutputGR, factor(lociOutputGR\$aseID, levels=unique(lociOutputGR\$aseID))) 
      return(
       list(
         geneOutput=geneOutputDF,
         locusOutput=lociOutputList
       )
      )
    }
    
    results_summary <- summarizeASEResults_1s(ASEresults_1s_haplotypesKnown)
    
    # Write outputs to files
    write.csv(results_summary\$geneOutput, file="gene_level_results.csv", row.names=TRUE)
    
    # Flatten locus-specific results for CSV export
    locus_df <- as.data.frame(unlist(as(results_summary\$locusOutput, "GRangesList")))
    write.csv(locus_df, file="locus_level_results.csv", row.names=TRUE)
    
    # Save full R objects for downstream analysis
    saveRDS(ASEresults_1s_haplotypesKnown, file="mbased_results.rds")
    saveRDS(results_summary, file="mbased_summary.rds")
    
    message("MBASED pipeline completed successfully. Outputs written to gene_level_results.csv, locus_level_results.csv, mbased_results.rds, and mbased_summary.rds.")

    writeLines(c(
        '"BIOC_MBASED_SINGLE_SAMPLE_ASE":',
        paste0('    MBASED: ', as.character(packageVersion('MBASED')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_ase.csv versions.yml
    """
}

workflow BIOC_MBASED_SINGLE_SAMPLE_ASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ snv_coordinates.bed, rna_seq_counts.tsv ] ]

    main:
    BIOC_MBASED_SINGLE_SAMPLE_ASE(ch_input)

    emit:
    tables   = BIOC_MBASED_SINGLE_SAMPLE_ASE.out.tables
    plots    = BIOC_MBASED_SINGLE_SAMPLE_ASE.out.plots
    objects  = BIOC_MBASED_SINGLE_SAMPLE_ASE.out.objects
    versions = BIOC_MBASED_SINGLE_SAMPLE_ASE.out.versions
}
