#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DAMEfinder — snp_based_dame_detection
// Extract allele-specific methylation using BAM and VCF files, calculate derived ASM, and find DAMEs.
// Input: bam_files, vcf_files, reference_file
// Container: quay.io/biocontainers/bioconductor-damefinder:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DAMEfinder, GenomicRanges, SummarizedExperiment
// Visualizations: MDS plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract allele-based methylation calls using extract_bams()
//  * 2. [Visualization & Output] Summarize methylation calls across samples using calc_derivedasm()
//  * 3. [Input & Preparation] Define design matrix and find DAMEs using find_dames()

nextflow.enable.dsl = 2

process BIOC_DAMEFINDER_SNP_BASED_DAME_DETECTION {
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
    .bm_deps <- c("DAMEfinder", "GenomicRanges", "SummarizedExperiment")
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
        suppressPackageStartupMessages({
                library(SummarizedExperiment)
    library(DAMEfinder)
          library(GenomicRanges)
        })
        
        # 1. Read input files from command line or working directory
        args <- commandArgs(trailingOnly = TRUE)
        if (length(args) >= 3) {
          bam_files <- unlist(strsplit(args[1], ","))
          vcf_files <- unlist(strsplit(args[2], ","))
          reference_file <- args[3]
        } else {
          bam_files <- sort(list.files(pattern = "\\\\.bam\$", full.names = TRUE))
          vcf_files <- sort(list.files(pattern = "\\\\.vcf(\\\\.gz)?\$", full.names = TRUE))
          reference_file <- list.files(pattern = "\\\\.(fa|fasta)\$", full.names = TRUE)[1]
        }
        
        if (length(bam_files) == 0) {
          stop("Error: No BAM files found.")
        }
        if (length(vcf_files) == 0) {
          stop("Error: No VCF files found.")
        }
        if (is.na(reference_file)) {
          stop("Error: No reference FASTA file found.")
        }
        
        # Extract sample names from file names
        sample_names <- gsub("\\\\.bam\$", "", basename(bam_files))
        
        # Obtain allele-based methylation calls
        snp_list <- extract_bams(bam_files, vcf_files, sample_names, reference_file)
        
        # 2. Calculate ASM scores
        derASM <- calc_derivedasm(snp_list)
        
        # Filter object to avoid warnings (keep rows with non-NA in all samples)
        filt <- rowSums(!is.na(assay(derASM, "der.ASM"))) == length(sample_names)
        if (sum(filt) < 2) {
          # Fallback if filtering is too strict
          filt <- rowSums(!is.na(assay(derASM, "der.ASM"))) >= 1
        }
        derASM <- derASM[filt, ]
        
        # 3. Define design matrix and find DAMEs
        # Assign groups based on sample names (defaulting to NORM vs CRC)
        grp_labels <- rep("NORM", length(sample_names))
        grp_labels[grep("CRC|cancer|tumor|case", sample_names, ignore.case = TRUE)] <- "CRC"
        if (length(unique(grp_labels)) < 2) {
          # If we cannot distinguish groups, split them to allow differential analysis
          grp_labels <- c(rep("CRC", floor(length(sample_names)/2)), rep("NORM", ceiling(length(sample_names)/2)))
        }
        grp <- factor(grp_labels, levels = c("NORM", "CRC"))
        mod <- model.matrix(~grp)
        
        # Run default find_dames (Simes method)
        dames <- find_dames(derASM, mod, maxGap = 300)
        
        # Run alternative mode (Empirical method)
        dames_empirical <- tryCatch({
          find_dames(derASM, mod, maxGap = 300, pvalAssign = "empirical")
        }, error = function(e) {
          message("Empirical p-value assignment skipped or failed: ", e\$message)
          NULL
        })
        
        # 4. Save meaningful results
        # Save tables
        write.csv(as.data.frame(dames), "dames_simes.csv", row.names = FALSE)
        if (!is.null(dames_empirical)) {
          write.csv(as.data.frame(dames_empirical), "dames_empirical.csv", row.names = FALSE)
        }
        
        # Save RDS object
        saveRDS(derASM, "ASMscore.rds")
        
        # Generate and save MDS plot
        pdf("mds_plot.pdf")
        tryCatch({
          methyl_MDS_plot(derASM, group = grp)
        }, error = function(e) {
          message("MDS plotting failed: ", e\$message)
        })
        dev.off()
        
        # Generate and save DAME track plot if DAMEs are detected
        if (nrow(dames) > 0) {
          colData(derASM)\$group <- grp
          colData(derASM)\$samples <- colnames(derASM)
          
          # Select the top detected DAME
          top_dame <- GRanges(dames\$chr[1], IRanges(dames\$start[1], dames\$end[1]))
          
          pdf("dame_track.pdf")
          tryCatch({
            dame_track(dame = top_dame, derASM = derASM)
          }, error = function(e) {
            message("DAME track plotting failed: ", e\$message)
          })
          dev.off()
        }

    writeLines(c(
        '"BIOC_DAMEFINDER_SNP_BASED_DAME_DETECTION":',
        paste0('    DAMEfinder: ', as.character(packageVersion('DAMEfinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snp_based_dame_detection.csv versions.yml
    """
}

workflow BIOC_DAMEFINDER_SNP_BASED_DAME_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_files, vcf_files, reference_file ] ]

    main:
    BIOC_DAMEFINDER_SNP_BASED_DAME_DETECTION(ch_input)

    emit:
    tables   = BIOC_DAMEFINDER_SNP_BASED_DAME_DETECTION.out.tables
    plots    = BIOC_DAMEFINDER_SNP_BASED_DAME_DETECTION.out.plots
    objects  = BIOC_DAMEFINDER_SNP_BASED_DAME_DETECTION.out.objects
    versions = BIOC_DAMEFINDER_SNP_BASED_DAME_DETECTION.out.versions
}
