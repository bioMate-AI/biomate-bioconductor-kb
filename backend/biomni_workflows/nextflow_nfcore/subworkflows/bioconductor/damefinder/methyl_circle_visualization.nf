#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DAMEfinder — methyl_circle_visualization
// Visualize the methylation state of individual reads overlapping a specific SNP or CpG site.
// Input: bam.file, vcf.file, reference_file
// Container: quay.io/biocontainers/bioconductor-damefinder:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, DAMEfinder, GenomicRanges
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define SNP or CpG site as a GRanges object
//  * 2. [Visualization & Output] Plot methyl-circle plot using methyl_circle_plot() or methyl_circle_plotCpG()

nextflow.enable.dsl = 2

process BIOC_DAMEFINDER_METHYL_CIRCLE_VISUALIZATION {
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
    .bm_deps <- c("DAMEfinder", "GenomicRanges", "Biostrings")
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
        
        # Load required libraries
        library(DAMEfinder)
        library(GenomicRanges)
        library(Biostrings)
        
        # Define input file paths from the working directory
        bam_input <- "bam.file"
        vcf_input <- "vcf.file"
        ref_input <- "reference_file"
        
        # Verify that the required input files exist
        if (!file.exists(bam_input)) {
          stop(paste("Required input file missing:", bam_input))
        }
        if (!file.exists(vcf_input)) {
          stop(paste("Required input file missing:", vcf_input))
        }
        if (!file.exists(ref_input)) {
          stop(paste("Required input file missing:", ref_input))
        }
        
        # Read the reference genome FASTA file as a DNAStringSet
        reference_file <- Biostrings::readDNAStringSet(ref_input)
        
        # Assign the user-provided files to the variables used in the documented code
        bam.file <- bam_input
        vcf.file <- vcf_input
        
        # 1. Define SNP or CpG site as a GRanges object dynamically from the VCF file
        vcf_con <- gzfile(vcf.file, "rt")
        first_snp_line <- NULL
        while (TRUE) {
          line <- readLines(vcf_con, n = 1)
          if (length(line) == 0) break
          if (!grepl("^#", line)) {
            first_snp_line <- line
            break
          }
        }
        close(vcf_con)
        
        if (is.null(first_snp_line)) {
          stop("No SNPs found in the provided VCF file.")
        }
        
        first_snp <- unlist(strsplit(first_snp_line, "\t"))
        snp <- GRanges(seqnames = first_snp[1], 
                       ranges = IRanges(start = as.numeric(first_snp[2]), width = 1))
        
        # 2. Plot methyl-circle plots and save them to PDF files
        
        # Plot 1: SNP only
        tryCatch({
          p1 <- methyl_circle_plot(snp = snp, vcfFile = vcf.file, bamFile = bam.file, 
                                   refFile = reference_file)
          pdf("methyl_circle_plot_snp.pdf", width = 10, height = 8)
          print(p1)
          dev.off()
          message("Successfully generated methyl_circle_plot_snp.pdf")
        }, error = function(e) {
          warning("Failed to generate Plot 1: ", e\$message)
        })
        
        # Plot 2: SNP and specific CpG site
        cpgsite <- snp
        
        tryCatch({
          p2 <- methyl_circle_plot(snp = snp, vcfFile = vcf.file, bamFile = bam.file, 
                                   refFile = reference_file, cpgsite = cpgsite)
          pdf("methyl_circle_plot_snp_cpg.pdf", width = 10, height = 8)
          print(p2)
          dev.off()
          message("Successfully generated methyl_circle_plot_snp_cpg.pdf")
        }, error = function(e) {
          warning("Failed to generate Plot 2: ", e\$message)
        })
        
        # Plot 3: CpG site only (using methyl_circle_plotCpG)
        tryCatch({
          p3 <- methyl_circle_plotCpG(cpgsite = cpgsite, bamFile = bam.file, 
                                refFile = reference_file)
          pdf("methyl_circle_plot_cpg_only.pdf", width = 10, height = 8)
          print(p3)
          dev.off()
          message("Successfully generated methyl_circle_plot_cpg_only.pdf")
        }, error = function(e) {
          warning("Failed to generate Plot 3: ", e\$message)
        })
        
        # Plot 4: SNP and a random DAME region
        dame <- snp + 50
        
        tryCatch({
          p4 <- methyl_circle_plot(snp = snp, vcfFile = vcf.file, bamFile = bam.file, 
                                   refFile = reference_file, dame = dame)
          pdf("methyl_circle_plot_dame.pdf", width = 10, height = 8)
          print(p4)
          dev.off()
          message("Successfully generated methyl_circle_plot_dame.pdf")
        }, error = function(e) {
          warning("Failed to generate Plot 4: ", e\$message)
        })
        
        message("Pipeline execution completed.")

    writeLines(c(
        '"BIOC_DAMEFINDER_METHYL_CIRCLE_VISUALIZATION":',
        paste0('    DAMEfinder: ', as.character(packageVersion('DAMEfinder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methyl_circle_visualization.csv versions.yml
    """
}

workflow BIOC_DAMEFINDER_METHYL_CIRCLE_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam.file, vcf.file, reference_file ] ]

    main:
    BIOC_DAMEFINDER_METHYL_CIRCLE_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_DAMEFINDER_METHYL_CIRCLE_VISUALIZATION.out.tables
    plots    = BIOC_DAMEFINDER_METHYL_CIRCLE_VISUALIZATION.out.plots
    objects  = BIOC_DAMEFINDER_METHYL_CIRCLE_VISUALIZATION.out.objects
    versions = BIOC_DAMEFINDER_METHYL_CIRCLE_VISUALIZATION.out.versions
}
