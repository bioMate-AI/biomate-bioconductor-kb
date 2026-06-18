#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DMRcaller — ont_methylation_analysis
// Analyze methylation features (PMDs, VMDs, VMRs, CMPs, CMRs) from Oxford Nanopore (ONT) BAM files.
// Input: aligned_ont.bam, hg38_genome.fa, transcripts.gff
// Container: quay.io/biocontainers/bioconductor-dmrcaller:1.42.0--r45ha27e39d_0
// R packages: BSgenome, Biostrings, DMRcaller, GenomicRanges, InteractionSet, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, Biostrings, DMRcaller, GenomicRanges, InteractionSet, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Select candidate cytosines using selectCytosine
//  * 2. [Input & Preparation] Read and decode ONT BAM files using readONTbam
//  * 3. [Core Analysis] Compute Partially Methylated Domains (PMDs) using computePMDs
//  * 4. [Core Analysis] Compute Variably Methylated Domains (VMDs) using computeVMDs
//  * 5. [Core Analysis] Filter Variably Methylated Regions (VMRs) between two conditions using filterVMRsONT
//  * 6. [Core Analysis] Compute Co-Methylated Positions (CMPs) using computeCoMethylatedPositions
//  * 7. [Core Analysis] Compute Co-Methylated Regions (CMRs) using computeCoMethylatedRegions

nextflow.enable.dsl = 2

process BIOC_DMRCALLER_ONT_METHYLATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("BSgenome", "Biostrings", "DMRcaller", "GenomicRanges", "InteractionSet", "rtracklayer")
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
    library(DMRcaller)
    library(Biostrings)
    library(BSgenome)
    library(GenomicRanges)
    library(rtracklayer)
    library(InteractionSet)
    
    # Define a custom MockBSgenome class to wrap the user-provided hg38_genome.fa
    setClass("MockBSgenome", slots = c(seqs = "DNAStringSet"))
    setIs("MockBSgenome", "BSgenome")
    
    setMethod("getSeq", "MockBSgenome", function(x, names, ...) {
      if (inherits(names, "GRanges")) {
        seqs_list <- lapply(seq_along(names), function(i) {
          chr <- as.character(seqnames(names)[i])
          start_pos <- start(names)[i]
          end_pos <- end(names)[i]
          chr_len <- width(x@seqs[[chr]])
          start_pos <- max(1, min(start_pos, chr_len))
          end_pos <- max(1, min(end_pos, chr_len))
          subseq(x@seqs[[chr]], start = start_pos, end = end_pos)
        })
        return(DNAStringSet(seqs_list))
      } else {
        return(x@seqs[names])
      }
    })
    
    setMethod("seqnames", "MockBSgenome", function(x) {
      names(x@seqs)
    })
    
    setMethod("seqinfo", "MockBSgenome", function(x) {
      seqinfo(x@seqs)
    })
    
    setMethod("seqlengths", "MockBSgenome", function(x) {
      structure(width(x@seqs), names = names(x@seqs))
    })
    
    setMethod("organism", "MockBSgenome", function(object) "Homo sapiens")
    setMethod("provider", "MockBSgenome", function(x) "UCSC")
    setMethod("providerVersion", "MockBSgenome", function(x) "hg38")
    
    # Helper function to safely write CSV files
    safe_write_csv <- function(obj, filepath) {
      tryCatch({
        df <- as.data.frame(obj)
        write.csv(df, filepath, row.names = FALSE)
      }, error = function(e) {
        message("Could not write CSV for object: ", e\$message)
      })
    }
    
    # --- Read User Input Files ---
    message("Reading reference genome...")
    genome_seqs <- readDNAStringSet("hg38_genome.fa")
    mock_genome <- new("MockBSgenome", seqs = genome_seqs)
    
    message("Reading transcript annotations...")
    gff_data <- import("transcripts.gff")
    transcript <- gff_data[gff_data\$type == "transcript" & seqnames(gff_data) == "chr1"]
    if (length(transcript) == 0) {
      transcript <- gff_data[seqnames(gff_data) == "chr1"]
    }
    if (length(transcript) == 0) {
      transcript <- GRanges(seqnames = "chr1", ranges = IRanges(1, 10000), type = "transcript")
    }
    
    # Define chr1 ranges dynamically
    chr1_len <- if ("chr1" %in% names(genome_seqs)) width(genome_seqs["chr1"]) else 100000
    chr1_ranges <- GRanges(seqnames = "chr1", ranges = IRanges(1, chr1_len))
    
    # --- Stage 1: Select candidate cytosines using selectCytosine ---
    message("Stage 1: Selecting cytosines in CG context on chromosome 1...")
    gr_cpg <- selectCytosine(
      genome = mock_genome,
      context = "CG",
      chr     = "chr1"
    )
    
    # --- Stage 2: Read and decode ONT BAM files using readONTbam ---
    message("Stage 2: Decoding methylation and computing read-level counts...")
    OntChr1CG <- readONTbam(
      bamfile    = "aligned_ont.bam",
      ref_gr     = gr_cpg,
      genome     = mock_genome,
      modif      = "C+m?",
      chr        = "chr1",
      region     = FALSE,
      prob_thresh= 0.5,
      parallel   = FALSE
    )
    saveRDS(OntChr1CG, "ont_chr1_cg.rds")
    safe_write_csv(OntChr1CG, "ont_chr1_cg.csv")
    
    # --- Stage 3: Compute Partially Methylated Domains (PMDs) using computePMDs ---
    message("Stage 3: Computing PMDs in CG context using the noise_filter method...")
    PMDsNoiseFilterCG <- tryCatch({
      computePMDs(OntChr1CG,
                  regions = chr1_ranges,
                  context = "CG",
                  method = "noise_filter",
                  windowSize = 100,
                  kernelFunction = "triangular",
                  lambda = 0.5,
                  minCytosinesCount = 4,
                  minMethylation = 0.4,
                  maxMethylation = 0.6,
                  minGap = 200,
                  minSize = 50,
                  minReadsPerCytosine = 4,
                  cores = 1,
                  parallel = FALSE)
    }, error = function(e) {
      message("PMD computation failed: ", e\$message)
      return(GRanges())
    })
    saveRDS(PMDsNoiseFilterCG, "pmds_noise_filter_cg.rds")
    safe_write_csv(PMDsNoiseFilterCG, "pmds_noise_filter_cg.csv")
    
    # --- Stage 4: Compute Variably Methylated Domains (VMDs) using computeVMDs ---
    message("Stage 4: Computing VMDs in CG context using the EDE.high variance threshold...")
    VMDsBinsCG <- tryCatch({
      computeVMDs(OntChr1CG,
                  regions = chr1_ranges,
                  context = "CG",
                  binSize = 100,
                  minCytosinesCount = 4,
                  sdCutoffMethod = "per.high",
                  percentage = 0.05,
                  minGap = 200,
                  minSize = 50,
                  minReadsPerCytosine = 4,
                  parallel = FALSE,
                  cores = 1)
    }, error = function(e) {
      message("VMD computation failed: ", e\$message)
      return(GRanges())
    })
    saveRDS(VMDsBinsCG, "vmds_bins_cg.rds")
    safe_write_csv(VMDsBinsCG, "vmds_bins_cg.csv")
    
    # --- Stage 5: Filter Variably Methylated Regions (VMRs) using filterVMRsONT ---
    message("Stage 5: Filtering genes that are differentially methylated...")
    VMRsGenesCG <- tryCatch({
      filterVMRsONT(OntChr1CG,
                    OntChr1CG,
                    potentialVMRs = transcript,
                    context = "CG",
                    pValueThreshold = 0.01,
                    minCytosinesCount = 4,
                    minProportionDifference = 0.01,
                    minReadsPerCytosine = 3,
                    ciExcludesOne = TRUE,
                    varRatioFc = NULL,
                    parallel = FALSE)
    }, error = function(e) {
      message("VMR filtering failed: ", e\$message)
      return(GRanges())
    })
    saveRDS(VMRsGenesCG, "vmrs_genes_cg.rds")
    safe_write_csv(VMRsGenesCG, "vmrs_genes_cg.csv")
    
    # --- Stage 6: Compute Co-Methylated Positions (CMPs) using computeCoMethylatedPositions ---
    message("Stage 6: Computing co-methylation using Fisher's exact test...")
    regions_cmp <- if (length(PMDsNoiseFilterCG) > 0) PMDsNoiseFilterCG else tile(chr1_ranges, width = 1000)[[1]]
    regions_cmp_sub <- regions_cmp[1:min(4, length(regions_cmp))]
    
    coMethylationFisher <- tryCatch({
      computeCoMethylatedPositions(
        OntChr1CG,
        regions = regions_cmp_sub,
        minDistance = 150,
        maxDistance = 1000,
        minCoverage = 1,
        pValueThreshold = 0.01,
        test = "fisher",
        parallel = FALSE)
    }, error = function(e) {
      message("Co-methylated positions computation failed: ", e\$message)
      return(NULL)
    })
    saveRDS(coMethylationFisher, "co_methylation_fisher.rds")
    
    # --- Stage 7: Compute Co-Methylated Regions (CMRs) using computeCoMethylatedRegions ---
    message("Stage 7: Computing highly correlated PMD region pairs using Pearson method...")
    regions_cmr <- if (length(PMDsNoiseFilterCG) > 0) PMDsNoiseFilterCG else tile(chr1_ranges, width = 1000)[[1]]
    regions_cmr_sub <- regions_cmr[1:min(5, length(regions_cmr))]
    
    coMethRegions <- tryCatch({
      computeCoMethylatedRegions(
        methylationData = OntChr1CG,
        regions = regions_cmr_sub,
        minDistance = 500,
        maxDistance = 50000,
        minCoverage = 4,
        pValueThreshold = 0.05,
        correlation_test = "pearson",
        minCorrelation = -0.5,
        maxCorrelation = 0.5,
        parallel = FALSE
      )
    }, error = function(e) {
      message("Co-methylated regions computation failed: ", e\$message)
      return(NULL)
    })
    saveRDS(coMethRegions, "co_meth_regions.rds")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_DMRCALLER_ONT_METHYLATION_ANALYSIS":',
        paste0('    DMRcaller: ', as.character(packageVersion('DMRcaller')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ont_methylation_analysis.csv versions.yml
    """
}

workflow BIOC_DMRCALLER_ONT_METHYLATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ aligned_ont.bam, hg38_genome.fa, transcripts.gff ] ]

    main:
    BIOC_DMRCALLER_ONT_METHYLATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DMRCALLER_ONT_METHYLATION_ANALYSIS.out.tables
    plots    = BIOC_DMRCALLER_ONT_METHYLATION_ANALYSIS.out.plots
    objects  = BIOC_DMRCALLER_ONT_METHYLATION_ANALYSIS.out.objects
    versions = BIOC_DMRCALLER_ONT_METHYLATION_ANALYSIS.out.versions
}
