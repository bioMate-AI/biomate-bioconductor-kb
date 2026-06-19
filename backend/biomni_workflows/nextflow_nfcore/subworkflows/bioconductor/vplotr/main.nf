#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: VplotR — vplot_and_footprint_analysis
// Import paired-end sequencing data, compute fragment size distributions, generate normalized V-plots, and plot footprints and local profiles over genomic loci.
// Input: ex1.bam, genomic loci of interest
// Container: quay.io/biocontainers/bioconductor-vplotr:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, VplotR, ggplot2, rtracklayer
// Visualizations: profile plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load User Input Files
//  * 2. [Visualization & Output] Import Paired-End BAM Files
//  * 3. [Visualization & Output] Fragment Size Distribution
//  * 4. [Visualization & Output] Generate V-plots
//  * 5. [Visualization & Output] Generate Footprint Profiles
//  * 6. [Visualization & Output] Plot Local Fragment Distribution

nextflow.enable.dsl = 2

process BIOC_VPLOTR_VPLOT_AND_FOOTPRINT_ANALYSIS {
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
    .bm_deps <- c("VplotR", "GenomicRanges", "ggplot2")
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
    library(VplotR)
    library(GenomicRanges)
    library(ggplot2)
    
    # ==========================================
    # --- Load User Input Files ---
    # ==========================================
    
    # Define input file paths
    bamfile <- "ex1.bam"
    loci_file_rds <- "loci.rds"
    loci_file_bed <- "loci.bed"
    annots_file_rds <- "annotations.rds"
    annots_file_bed <- "annotations.bed"
    
    # Verify that the BAM file exists
    if (!file.exists(bamfile)) {
        stop(paste("Required BAM file not found in the working directory:", bamfile))
    }
    
    # Load genomic loci of interest (GRanges object)
    if (file.exists(loci_file_rds)) {
        ABF1_sacCer3 <- readRDS(loci_file_rds)
    } else if (file.exists(loci_file_bed)) {
        if (!requireNamespace("rtracklayer", quietly = TRUE)) {
            stop("rtracklayer package is required to import BED files.")
        }
        ABF1_sacCer3 <- rtracklayer::import(loci_file_bed)
    } else {
        stop("Required genomic loci file ('loci.rds' or 'loci.bed') not found in the working directory.")
    }
    
    # Load genomic annotations (GRanges object)
    if (file.exists(annots_file_rds)) {
        genes_sacCer3 <- readRDS(annots_file_rds)
    } else if (file.exists(annots_file_bed)) {
        if (!requireNamespace("rtracklayer", quietly = TRUE)) {
            stop("rtracklayer package is required to import BED files.")
        }
        genes_sacCer3 <- rtracklayer::import(annots_file_bed)
    } else {
        # Fallback to using the same loci of interest as annotations if none provided
        genes_sacCer3 <- ABF1_sacCer3
    }
    
    # ==========================================
    # --- Import Paired-End BAM Files ---
    # ==========================================
    
    fragments <- importPEBamFiles(
        bamfile, 
        shift_ATAC_fragments = TRUE
    )
    
    # Map imported fragments to the vignette variable names to preserve exact function calls
    MNase_sacCer3_Henikoff2011 <- fragments
    MNase_sacCer3_Henikoff2011_subset <- fragments
    
    # Save imported fragments to RDS
    saveRDS(fragments, "imported_fragments.rds")
    
    # ==========================================
    # --- Fragment Size Distribution ---
    # ==========================================
    
    df <- getFragmentsDistribution(
        MNase_sacCer3_Henikoff2011, 
        ABF1_sacCer3
    )
    
    # Save distribution data frame
    write.csv(df, "fragment_size_distribution.csv", row.names = FALSE)
    
    # Plot and save distribution
    p_dist <- ggplot(df, aes(x = x, y = y)) + geom_line() + theme_ggplot2()
    ggsave("fragment_size_distribution.pdf", plot = p_dist, width = 7, height = 5)
    
    # ==========================================
    # --- Generate V-plots ---
    # ==========================================
    
    # Single V-plot
    p_single <- plotVmat(x = MNase_sacCer3_Henikoff2011, granges = ABF1_sacCer3)
    ggsave("vplot_single.pdf", plot = p_single, width = 7, height = 6)
    
    # Multiple V-plots
    list_params <- list(
        "MNase\n@ ABF1" = list(MNase_sacCer3_Henikoff2011, ABF1_sacCer3), 
        "MNase\n@ random loci" = list(
            MNase_sacCer3_Henikoff2011, sampleGRanges(ABF1_sacCer3)
        )
    )
    
    p_multi <- plotVmat(
        list_params, 
        cores = 1
    )
    ggsave("vplot_multiple.pdf", plot = p_multi, width = 10, height = 6)
    
    # Multiple V-plots with custom normalization (none)
    p_multi_norm_none <- plotVmat(
        list_params, 
        cores = 1, 
        nrow = 2, ncol = 5, 
        verbose = FALSE,
        normFun = 'none'
    )
    ggsave("vplot_multiple_norm_none.pdf", plot = p_multi_norm_none, width = 12, height = 6)
    
    # ==========================================
    # --- Generate Footprint Profiles ---
    # ==========================================
    
    p_footprint <- plotFootprint(
        MNase_sacCer3_Henikoff2011,
        ABF1_sacCer3
    )
    ggsave("footprint_profile.pdf", plot = p_footprint, width = 8, height = 5)
    
    # ==========================================
    # --- Plot Local Fragment Distribution ---
    # ==========================================
    
    # Dynamically define a genomic window based on the first locus of interest to ensure overlap
    first_locus <- ABF1_sacCer3[1]
    chrom <- as.character(seqnames(first_locus))
    w_start <- max(1, start(first_locus) - 500)
    w_end <- end(first_locus) + 500
    
    # Format window string with commas (e.g., "seq1:100-1,100")
    window_val <- paste0(chrom, ":", format(w_start, big.mark = ","), "-", format(w_end, big.mark = ","))
    window_val <- gsub(" ", "", window_val)
    
    p_profile <- plotProfile(
        fragments = MNase_sacCer3_Henikoff2011_subset,
        window = window_val, 
        loci = ABF1_sacCer3, 
        annots = genes_sacCer3,
        min = 20, max = 200, alpha = 0.1, size = 1.5
    )
    ggsave("local_profile.pdf", plot = p_profile, width = 10, height = 6)
    
    # Save session info
    writeLines(capture.output(sessionInfo()), "session_info.txt")

    writeLines(c(
        '"BIOC_VPLOTR_VPLOT_AND_FOOTPRINT_ANALYSIS":',
        paste0('    VplotR: ', as.character(packageVersion('VplotR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vplot_and_footprint_analysis.csv versions.yml
    """
}

workflow BIOC_VPLOTR_VPLOT_AND_FOOTPRINT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ex1.bam, genomic loci of interest ] ]

    main:
    BIOC_VPLOTR_VPLOT_AND_FOOTPRINT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_VPLOTR_VPLOT_AND_FOOTPRINT_ANALYSIS.out.tables
    plots    = BIOC_VPLOTR_VPLOT_AND_FOOTPRINT_ANALYSIS.out.plots
    objects  = BIOC_VPLOTR_VPLOT_AND_FOOTPRINT_ANALYSIS.out.objects
    versions = BIOC_VPLOTR_VPLOT_AND_FOOTPRINT_ANALYSIS.out.versions
}
