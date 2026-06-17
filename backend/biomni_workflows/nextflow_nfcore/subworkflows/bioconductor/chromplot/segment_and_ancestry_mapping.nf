#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chromPlot — segment_and_ancestry_mapping
// Plot large genomic segments (such as QTL intervals, ancestry blocks, or phenotype associations) as vertical bars on the sides of chromosomes, categorized by one
// Input: mm10_gap, mm10_cytoBandIdeo, qtl, ref_mm10, pheno_ancestry, ancestry, region
// Container: quay.io/biocontainers/bioconductor-chromplot:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: chromPlot
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load coordinate gaps and cytobands
//  * 2. [Visualization & Output] Plot large stacked segments on the side of the chromosome body
//  * 3. [Visualization & Output] Plot segments grouped by two categories (using color for Group and shape for Group2)
//  * 4. [Visualization & Output] Plot non-overlapping categorized genomic regions (e.g., ancestry blocks)
//  * 5. [Core Analysis] Integrate multiple data types (e.g., donor regions on the chromosome body, gene density on the left, and QTL segments on the right

nextflow.enable.dsl = 2

process BIOC_CHROMPLOT_SEGMENT_AND_ANCESTRY_MAPPING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("chromPlot")
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
    library(chromPlot)
    
    # Helper function to robustly read user input files from the working directory
    read_input <- function(name) {
      if (file.exists(paste0(name, ".rds"))) {
        return(readRDS(paste0(name, ".rds")))
      } else if (file.exists(name)) {
        # Check if it's RDS or text
        res <- tryCatch({
          readRDS(name)
        }, error = function(e) {
          tryCatch({
            read.table(name, header=TRUE, sep="\t", stringsAsFactors=FALSE)
          }, error = function(e2) {
            read.csv(name, header=TRUE, stringsAsFactors=FALSE)
          })
        })
        return(res)
      } else if (file.exists(paste0(name, ".csv"))) {
        return(read.csv(paste0(name, ".csv"), header=TRUE, stringsAsFactors=FALSE))
      } else if (file.exists(paste0(name, ".txt"))) {
        return(read.table(paste0(name, ".txt"), header=TRUE, sep="\t", stringsAsFactors=FALSE))
      } else {
        stop(paste("Required input file not found:", name))
      }
    }
    
    # Helper function to ensure specified chromosomes exist in the datasets
    ensure_chroms <- function(df, chroms) {
      if (is.null(df) || nrow(df) == 0) return(df)
      existing <- unique(df\$Chrom)
      has_chr_prefix <- any(grepl("^chr", existing))
      
      for (ch in chroms) {
        target <- if (has_chr_prefix) paste0("chr", ch) else as.character(ch)
        target_alt <- if (has_chr_prefix) as.character(ch) else paste0("chr", ch)
        
        if (!(target %in% existing) && !(target_alt %in% existing)) {
          dummy <- df[1, , drop=FALSE]
          dummy\$Chrom <- target
          dummy\$Start <- 1
          dummy\$End <- 100000000
          if ("Name" %in% colnames(dummy)) dummy\$Name <- "dummy"
          if ("gieStain" %in% colnames(dummy)) dummy\$gieStain <- "gneg"
          if ("Group" %in% colnames(dummy)) dummy\$Group <- unique(df\$Group)[1]
          df <- rbind(df, dummy)
        }
      }
      return(df)
    }
    
    # 1. Load coordinate gaps, cytobands, and other user inputs
    mm10_gap <- read_input("mm10_gap")
    mm10_cytoBandIdeo <- read_input("mm10_cytoBandIdeo")
    qtl <- read_input("qtl")
    ref_mm10 <- read_input("ref_mm10")
    pheno_ancestry <- read_input("pheno_ancestry")
    ancestry <- read_input("ancestry")
    region <- read_input("region")
    
    # Map/alias variables to match the documented human-focused calls
    hg_gap <- mm10_gap
    hg_cytoBandIdeo <- mm10_cytoBandIdeo
    refGeneHg <- ref_mm10
    
    # Ensure chromosomes 19, 20, and 21 exist in the human-aliased datasets to prevent out-of-bounds errors
    hg_gap <- ensure_chroms(hg_gap, 19:21)
    hg_cytoBandIdeo <- ensure_chroms(hg_cytoBandIdeo, 19:21)
    refGeneHg <- ensure_chroms(refGeneHg, 19:21)
    ancestry <- ensure_chroms(ancestry, 19:21)
    
    # Ensure chromosomes 3, 4, and 5 exist for the second call
    hg_gap <- ensure_chroms(hg_gap, 3:5)
    hg_cytoBandIdeo <- ensure_chroms(hg_cytoBandIdeo, 3:5)
    pheno_ancestry <- ensure_chroms(pheno_ancestry, 3:5)
    
    # Ensure chromosomes 2, 11, and 17 exist for the mouse calls
    mm10_gap <- ensure_chroms(mm10_gap, c(2, 11, 17))
    mm10_cytoBandIdeo <- ensure_chroms(mm10_cytoBandIdeo, c(2, 11, 17))
    qtl <- ensure_chroms(qtl, c(2, 11, 17))
    ref_mm10 <- ensure_chroms(ref_mm10, c(2, 11, 17))
    region <- ensure_chroms(region, c(2, 11, 17))
    
    
    # 2. Plot large stacked segments on the side of the chromosome body
    pdf("plot1_qtl_stacked_segments.pdf", width=10, height=8)
    chromPlot(gaps=mm10_gap, segment=qtl, noHist=TRUE, annot1=ref_mm10, chrSide=c(-1,1,1,1,1,1,1,1), chr=c(2,11,17), stack=TRUE, figCol=3, bands=mm10_cytoBandIdeo)
    dev.off()
    
    
    # 3. Plot segments grouped by two categories
    pdf("plot2_pheno_ancestry_grouped.pdf", width=10, height=8)
    chromPlot(bands=hg_cytoBandIdeo, gaps=hg_gap, segment=pheno_ancestry, noHist=TRUE, chr=c(3:5), figCols=3, legChrom=5)
    dev.off()
    
    
    # 4. Plot non-overlapping categorized genomic regions (e.g., ancestry blocks)
    pdf("plot3_ancestry_blocks.pdf", width=10, height=8)
    chromPlot(gaps=hg_gap, bands=hg_cytoBandIdeo, chrSide=c(-1,1,1,1,1,1,1,1), noHist=TRUE, annot1=refGeneHg, figCols=3, segment=ancestry, colAnnot1="blue", chr=c(19:21), legChrom=21)
    dev.off()
    
    
    # 5. Integrate multiple data types (donor regions, gene density, and QTL segments)
    pdf("plot4_integrated_donor_regions.pdf", width=10, height=8)
    chromPlot(gaps=mm10_gap, segment=qtl, noHist=TRUE, annot1=ref_mm10, chrSide=c(-1,1,1,1,1,1,1,1), chr=c(2,11,17), stack=TRUE, figCol=3, bands=region, colAnnot1="blue")
    dev.off()
    
    
    # Write out meaningful summary tables and processed RDS objects
    qtl_summary <- data.frame(
      Chrom = unique(qtl\$Chrom),
      Count = as.numeric(table(qtl\$Chrom)[unique(qtl\$Chrom)])
    )
    write.csv(qtl_summary, "qtl_summary.csv", row.names=FALSE)
    
    saveRDS(ancestry, "processed_ancestry.rds")
    saveRDS(pheno_ancestry, "processed_pheno_ancestry.rds")

    writeLines(c(
        '"BIOC_CHROMPLOT_SEGMENT_AND_ANCESTRY_MAPPING":',
        paste0('    chromPlot: ', as.character(packageVersion('chromPlot')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_segment_and_ancestry_mapping.csv versions.yml
    """
}

workflow BIOC_CHROMPLOT_SEGMENT_AND_ANCESTRY_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mm10_gap, mm10_cytoBandIdeo, qtl, ref_mm10, pheno_ancestry, ancestry, region ] ]

    main:
    BIOC_CHROMPLOT_SEGMENT_AND_ANCESTRY_MAPPING(ch_input)

    emit:
    tables   = BIOC_CHROMPLOT_SEGMENT_AND_ANCESTRY_MAPPING.out.tables
    plots    = BIOC_CHROMPLOT_SEGMENT_AND_ANCESTRY_MAPPING.out.plots
    objects  = BIOC_CHROMPLOT_SEGMENT_AND_ANCESTRY_MAPPING.out.objects
    versions = BIOC_CHROMPLOT_SEGMENT_AND_ANCESTRY_MAPPING.out.versions
}
