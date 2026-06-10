#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: raer — alu_editing_index
// Calculate the Alu Editing Index (AEI) to summarize global ADAR editing activity.
// Input: bam_files.bam, fafn.fasta, alus.gr, alu_snps.gr
// Container: quay.io/biocontainers/bioconductor-raer:1.8.0--r45h01b2380_2
// R packages: Biostrings, GenomicRanges, raer
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, GenomicRanges, raer
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Obtain and format Alu coordinates and overlapping SNPs
//  * 2. [Core Analysis] Configure filtering parameters using FilterParam()
//  * 3. [Core Analysis] Calculate the Alu Editing Index using calc_AEI()

nextflow.enable.dsl = 2

process BIOC_RAER_ALU_EDITING_INDEX {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("Biostrings", "GenomicRanges", "raer")
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
    library(raer)
    library(GenomicRanges)
    library(Biostrings)
    
    # Stage 1: Obtain and format Alu coordinates and overlapping SNPs
    # Read the declared user input files from the working directory
    bam_files <- "bam_files.bam"
    fafn <- "fafn.fasta"
    
    # Read the GRanges/GPos objects from the RDS files
    alus <- readRDS("alus.gr")
    alu_snps <- readRDS("alu_snps.gr")
    
    # Stage 2: Configure filtering parameters using FilterParam()
    fp <- FilterParam(
        only_keep_variants = TRUE,
        trim_5p = 5,
        trim_3p = 5,
        min_base_quality = 30,
        min_mapq = 255,
        library_type = "fr-first-strand",
        min_splice_overhang = 10
    )
    
    # Stage 3: Calculate the Alu Editing Index using calc_AEI()
    alu_index <- calc_AEI(bam_files,
        fasta = fafn,
        snp_db = alu_snps,
        alu_ranges = alus,
        param = fp
    )
    
    # Stage 4: Write named output files for the meaningful results
    # Save the complete list object containing AEI results
    saveRDS(alu_index, "alu_index.rds")
    
    # Save the overall AEI matrix as a CSV table
    if (!is.null(alu_index\$AEI)) {
        write.csv(as.data.frame(alu_index\$AEI), "aei_summary.csv", row.names = TRUE)
    }
    
    # Save the detailed chromosome-level AEI table as a CSV table
    if (!is.null(alu_index\$AEI_per_chrom)) {
        write.csv(as.data.frame(alu_index\$AEI_per_chrom), "aei_per_chrom.csv", row.names = TRUE)
    }
    
    # Generate a PDF plot of the A-to-G Alu Editing Index across samples
    if (!is.null(alu_index\$AEI)) {
        pdf("aei_plot.pdf", width = 7, height = 5)
        
        # Check if A-to-G (AG) editing index is present in the columns
        if ("AG" %in% colnames(alu_index\$AEI)) {
            barplot(alu_index\$AEI[, "AG"], 
                    main = "Alu Editing Index (A-to-G)", 
                    col = "skyblue", 
                    las = 2, 
                    ylab = "AEI")
        } else if (ncol(alu_index\$AEI) > 0) {
            # Fallback to the first available column if "AG" is not explicitly named
            barplot(alu_index\$AEI[, 1], 
                    main = paste("Alu Editing Index -", colnames(alu_index\$AEI)[1]), 
                    col = "skyblue", 
                    las = 2, 
                    ylab = "AEI")
        }
        
        dev.off()
    }

    writeLines(c(
        '"BIOC_RAER_ALU_EDITING_INDEX":',
        paste0('    raer: ', as.character(packageVersion('raer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alu_editing_index.csv versions.yml
    """
}

workflow BIOC_RAER_ALU_EDITING_INDEX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_files.bam, fafn.fasta, alus.gr, alu_snps.gr ] ]

    main:
    BIOC_RAER_ALU_EDITING_INDEX(ch_input)

    emit:
    tables   = BIOC_RAER_ALU_EDITING_INDEX.out.tables
    plots    = BIOC_RAER_ALU_EDITING_INDEX.out.plots
    objects  = BIOC_RAER_ALU_EDITING_INDEX.out.objects
    versions = BIOC_RAER_ALU_EDITING_INDEX.out.versions
}
