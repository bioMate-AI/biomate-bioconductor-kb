#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chromPlot — xy_plotting_of_genomic_statistics
// Plot continuous genomic statistics (such as Fst, iHS, XP-EHH, or LOD scores) along chromosomes as points or lines, with optional thresholding and summarization.
// Input: hg_gap, hg_cytoBandIdeo, fst, ihs, xpehh, QTLs
// Container: quay.io/biocontainers/bioconductor-chromplot:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: chromPlot
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load coordinate gaps and cytobands
//  * 2. [Visualization & Output] Plot continuous statistics as points or lines
//  * 3. [Visualization & Output] Apply bin-level summarization (e.g., mean) to smooth the plot
//  * 4. [Visualization & Output] Plot multiple continuous tracks simultaneously with thresholds and text labels for specific data points
//  * 5. [Visualization & Output] Plot LOD curves from QTL mapping along with gene density

nextflow.enable.dsl = 2

process BIOC_CHROMPLOT_XY_PLOTTING_OF_GENOMIC_STATISTICS {
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
        read_user_input <- function(base_name) {
          extensions <- c(".rds", ".csv", ".tsv", ".txt", "")
          for (ext in extensions) {
            file_path <- paste0(base_name, ext)
            if (file.exists(file_path)) {
              if (ext == ".rds") {
                return(readRDS(file_path))
              } else if (ext == ".csv") {
                return(read.csv(file_path, header = TRUE, stringsAsFactors = FALSE))
              } else {
                df <- tryCatch({
                  read.table(file_path, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
                }, error = function(e) {
                  read.table(file_path, header = TRUE, sep = ",", stringsAsFactors = FALSE)
                })
                return(df)
              }
            }
          }
          stop(paste("Required input file not found for:", base_name))
        }
        
        # Helper function to ensure required columns exist and are correctly named
        ensure_columns <- function(df, required_cols) {
          col_map <- list(
            Chrom = c("chrom", "chr", "chromosome", "seqnames"),
            Start = c("start", "txstart", "chromstart"),
            End = c("end", "txend", "chromend")
          )
          
          for (req in names(col_map)) {
            if (!req %in% colnames(df)) {
              for (alt in col_map[[req]]) {
                alt_col <- grep(paste0("^", alt, "\$"), colnames(df), ignore.case = TRUE, value = TRUE)
                if (length(alt_col) > 0) {
                  colnames(df)[colnames(df) == alt_col[1]] <- req
                  break
                }
              }
            }
          }
          
          for (col in required_cols) {
            if (!col %in% colnames(df)) {
              alt_col <- grep(paste0("^", col, "\$"), colnames(df), ignore.case = TRUE, value = TRUE)
              if (length(alt_col) > 0) {
                colnames(df)[colnames(df) == alt_col[1]] <- col
              } else {
                if (col == "ID") {
                  df[[col]] <- ""
                } else {
                  stop(paste("Required column not found:", col))
                }
              }
            }
          }
          return(df)
        }
        
        # Helper function to standardize chromosome names
        standardize_chromosomes <- function(df) {
          if (is.null(df) || nrow(df) == 0) return(df)
          
          if (!"Chrom" %in% colnames(df)) {
            colnames(df)[1] <- "Chrom"
          }
          
          df\$Chrom <- gsub("^chr", "", as.character(df\$Chrom), ignore.case = TRUE)
          return(df)
        }
        
        # 1. Load coordinate gaps, cytobands, and statistics from user input files
        hg_gap <- read_user_input("hg_gap")
        hg_cytoBandIdeo <- read_user_input("hg_cytoBandIdeo")
        fst <- read_user_input("fst")
        ihs <- read_user_input("ihs")
        xpehh <- read_user_input("xpehh")
        QTLs <- read_user_input("QTLs")
        
        # Standardize columns
        hg_gap <- ensure_columns(hg_gap, c("Chrom", "Start", "End"))
        hg_cytoBandIdeo <- ensure_columns(hg_cytoBandIdeo, c("Chrom", "Start", "End"))
        fst <- ensure_columns(fst, c("Chrom", "Start", "End", "win.FST"))
        ihs <- ensure_columns(ihs, c("Chrom", "Start", "End", "iHS"))
        xpehh <- ensure_columns(xpehh, c("Chrom", "Start", "End", "XP", "ID"))
        QTLs <- ensure_columns(QTLs, c("Chrom", "Start", "LOD"))
        
        # Ensure chromosomes are standardized
        hg_gap <- standardize_chromosomes(hg_gap)
        hg_cytoBandIdeo <- standardize_chromosomes(hg_cytoBandIdeo)
        fst <- standardize_chromosomes(fst)
        ihs <- standardize_chromosomes(ihs)
        xpehh <- standardize_chromosomes(xpehh)
        
        # Prepare ID column for xpehh as in vignette
        if (!"Name" %in% colnames(xpehh)) {
          xpehh\$Name <- paste0("marker_", 1:nrow(xpehh))
        }
        xpehh\$ID <- ""
        xpehh[which.max(xpehh\$XP), "ID"] <- xpehh[which.max(xpehh\$XP), "Name"]
        
        # Prepare mouse-specific objects for the QTL plot
        mm10_gap <- standardize_chromosomes(hg_gap)
        mm10_cytoBandIdeo <- standardize_chromosomes(hg_cytoBandIdeo)
        ref_mm10 <- fst[, c("Chrom", "Start", "End")]
        if (!"Name" %in% colnames(ref_mm10)) {
          ref_mm10\$Name <- paste0("region_", 1:nrow(ref_mm10))
        }
        ref_mm10 <- standardize_chromosomes(ref_mm10)
        QTLs <- standardize_chromosomes(QTLs)
        
        # Dynamically determine chromosomes present in the data
        human_chrs <- unique(fst\$Chrom)
        mouse_chrs <- unique(QTLs\$Chrom)
        
        # 2. Plot continuous statistics as points or lines
        pdf("plot1_fst_points_none.pdf", width = 10, height = 8)
        chromPlot(bands=hg_cytoBandIdeo, gaps=hg_gap, stat=fst, statCol="win.FST", statName="win.FST", statTyp="p", chr=human_chrs, figCols=3, scex=0.7, spty=20, statSumm="none")
        dev.off()
        
        # 3. Apply bin-level summarization (e.g., mean) to smooth the plot
        pdf("plot2_fst_points_mean.pdf", width = 10, height = 8)
        chromPlot(bands=hg_cytoBandIdeo, gaps=hg_gap, stat=fst, statCol="win.FST", statName="win.FST", statTyp="p", chr=human_chrs, figCols=3, scex=0.7, spty=20, statSumm="mean")
        dev.off()
        
        pdf("plot3_fst_lines_none.pdf", width = 10, height = 8)
        chromPlot(bands=hg_cytoBandIdeo, gaps=hg_gap, stat=fst, statCol="win.FST", statName="win.FST", statTyp="l", chr=human_chrs, figCols=3, statSumm="none")
        dev.off()
        
        pdf("plot4_fst_lines_mean.pdf", width = 10, height = 8)
        chromPlot(bands=hg_cytoBandIdeo, gaps=hg_gap, stat=fst, statCol="win.FST", statName="win.FST", statTyp="l", chr=human_chrs, figCols=3, statSumm="mean")
        dev.off()
        
        # 4. Plot multiple continuous tracks simultaneously with thresholds and text labels
        pdf("plot5_multi_track.pdf", width = 10, height = 8)
        chromPlot(gaps=hg_gap, bands=fst, stat=ihs, stat2=xpehh, statCol="iHS", statCol2="XP", statName="iHS", statName2="normxpehh", colStat="red", colStat2="blue", statTyp="p", scex=2, spty=20, statThreshold=1.2, statThreshold2=1.5, chr=human_chrs, bin=1e6, figCols=3, cex=0.7, statSumm="none", legChrom=human_chrs[1], stack=FALSE)
        dev.off()
        
        # 5. Plot LOD curves from QTL mapping along with gene density
        pdf("plot6_qtl_mapping.pdf", width = 10, height = 8)
        chromPlot(gaps=mm10_gap, bands=mm10_cytoBandIdeo, annot1=ref_mm10, stat=QTLs, statCol="LOD", chrSide=c(-1,1,1,1,1,1,1,1), statTyp="l", chr=mouse_chrs, figCols=3)
        dev.off()
        
        # Save processed datasets as RDS and CSV files
        saveRDS(fst, "processed_fst.rds")
        saveRDS(ihs, "processed_ihs.rds")
        saveRDS(xpehh, "processed_xpehh.rds")
        write.csv(QTLs, "processed_QTLs.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_CHROMPLOT_XY_PLOTTING_OF_GENOMIC_STATISTICS":',
        paste0('    chromPlot: ', as.character(packageVersion('chromPlot')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xy_plotting_of_genomic_statistics.csv versions.yml
    """
}

workflow BIOC_CHROMPLOT_XY_PLOTTING_OF_GENOMIC_STATISTICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hg_gap, hg_cytoBandIdeo, fst, ihs, xpehh, QTLs ] ]

    main:
    BIOC_CHROMPLOT_XY_PLOTTING_OF_GENOMIC_STATISTICS(ch_input)

    emit:
    tables   = BIOC_CHROMPLOT_XY_PLOTTING_OF_GENOMIC_STATISTICS.out.tables
    plots    = BIOC_CHROMPLOT_XY_PLOTTING_OF_GENOMIC_STATISTICS.out.plots
    objects  = BIOC_CHROMPLOT_XY_PLOTTING_OF_GENOMIC_STATISTICS.out.objects
    versions = BIOC_CHROMPLOT_XY_PLOTTING_OF_GENOMIC_STATISTICS.out.versions
}
