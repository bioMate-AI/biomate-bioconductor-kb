#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: InTAD — loop_based_correlation
// Correlate gene expression and epigenetic signals connected via chromatin loops.
// Input: enhSel, enhSelGR, rpkmCountsSel, txsSel, mbAnnData, loopsDfSel
// Container: quay.io/biocontainers/bioconductor-intad:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, InTAD
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the InTADSig object
//  * 2. [Core Analysis] Filter low-expressed genes
//  * 3. [Core Analysis] Combine signals and genes using chromatin loops
//  * 4. [Core Analysis] Perform correlation analysis

nextflow.enable.dsl = 2

process BIOC_INTAD_LOOP_BASED_CORRELATION {
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
    .bm_deps <- c("InTAD", "GenomicRanges")
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
        library(InTAD)
        library(GenomicRanges)
        
        # Helper function to read GRanges objects from RDS or tabular formats
        read_granges <- function(base_name) {
          rds_path <- paste0(base_name, ".rds")
          csv_path <- paste0(base_name, ".csv")
          tsv_path <- paste0(base_name, ".tsv")
          
          if (file.exists(rds_path)) {
            return(readRDS(rds_path))
          } else if (file.exists(csv_path)) {
            df <- read.csv(csv_path, header = TRUE, check.names = FALSE)
            return(makeGRangesFromDataFrame(df, keep.extra.columns = TRUE))
          } else if (file.exists(tsv_path)) {
            df <- read.delim(tsv_path, header = TRUE, check.names = FALSE)
            return(makeGRangesFromDataFrame(df, keep.extra.columns = TRUE))
          } else {
            stop(paste("Required GRanges input file not found for:", base_name))
          }
        }
        
        # Helper function to read data frames or matrices from RDS or tabular formats
        read_df_or_matrix <- function(base_name, as_matrix = FALSE, row.names = 1) {
          rds_path <- paste0(base_name, ".rds")
          csv_path <- paste0(base_name, ".csv")
          tsv_path <- paste0(base_name, ".tsv")
          
          if (file.exists(rds_path)) {
            obj <- readRDS(rds_path)
            if (as_matrix) {
              return(as.matrix(obj))
            }
            return(obj)
          } else if (file.exists(csv_path)) {
            df <- read.csv(csv_path, row.names = row.names, check.names = FALSE)
            if (as_matrix) {
              return(as.matrix(df))
            }
            return(df)
          } else if (file.exists(tsv_path)) {
            df <- read.delim(tsv_path, row.names = row.names, check.names = FALSE)
            if (as_matrix) {
              return(as.matrix(df))
            }
            return(df)
          } else {
            stop(paste("Required input file not found for:", base_name))
          }
        }
        
        # 1. Load User Input Files from Working Directory
        message("Loading input datasets...")
        enhSel        <- read_df_or_matrix("enhSel", as_matrix = FALSE)
        enhSelGR      <- read_granges("enhSelGR")
        rpkmCountsSel <- read_df_or_matrix("rpkmCountsSel", as_matrix = FALSE)
        txsSel        <- read_granges("txsSel")
        mbAnnData     <- read_df_or_matrix("mbAnnData", as_matrix = FALSE)
        loopsDfSel    <- read_df_or_matrix("loopsDfSel", as_matrix = FALSE, row.names = NULL)
        
        # Validate consistency of inputs
        if (!all(colnames(rpkmCountsSel) == colnames(enhSel))) {
          stop("Sample names do not match between epigenetic signals (enhSel) and gene expression (rpkmCountsSel).")
        }
        if (length(enhSelGR) != nrow(enhSel)) {
          stop("The number of signal regions in enhSelGR does not match the number of rows in enhSel.")
        }
        if (!all(c("gene_id", "gene_name") %in% colnames(mcols(txsSel)))) {
          stop("txsSel GRanges must contain 'gene_id' and 'gene_name' metadata columns.")
        }
        
        # 2. Initialize the InTADSig object
        message("Initializing InTADSig object...")
        inTadSig <- newSigInTAD(enhSel, enhSelGR, rpkmCountsSel, txsSel, mbAnnData)
        
        # 3. Filter low-expressed genes
        message("Filtering gene expression...")
        inTadSig <- filterGeneExpr(inTadSig, checkExprDistr = TRUE)
        
        # 4. Combine signals and genes using chromatin loops
        message("Combining signals and genes using chromatin loops...")
        inTadSig <- combineWithLoops(inTadSig, loopsDfSel)
        
        # 5. Perform correlation analysis
        message("Performing correlation analysis from loops...")
        loopEag <- findCorFromLoops(inTadSig, method = "spearman")
        
        # 6. Save Results
        message("Saving results...")
        write.csv(loopEag, "loop_correlations.csv", row.names = FALSE)
        saveRDS(loopEag, "loop_correlations.rds")
        saveRDS(inTadSig, "inTadSig_processed.rds")
        
        # 7. Generate Visualization (if correlations are found)
        if (nrow(loopEag) > 0) {
          message("Generating correlation plot for the top correlated pair...")
          # Identify the pair with the highest absolute correlation
          top_pair <- loopEag[which.max(abs(loopEag\$cor)), ]
          cID <- top_pair\$peak
          gName <- top_pair\$name
          
          pdf("top_loop_correlation_plot.pdf", width = 7, height = 6)
          
          # Determine if a phenotype column is available for color-coding
          col_pheno <- NULL
          if (!is.null(mbAnnData) && ncol(mbAnnData) > 0) {
            col_pheno <- colnames(mbAnnData)[1]
          }
          
          if (!is.null(col_pheno)) {
            plotCorrelation(inTadSig, cID, gName,
                            xLabel = "RPKM gene expr log2",
                            yLabel = "Epigenetic signal log2",
                            colByPhenotype = col_pheno)
          } else {
            plotCorrelation(inTadSig, cID, gName,
                            xLabel = "RPKM gene expr log2",
                            yLabel = "Epigenetic signal log2")
          }
          
          dev.off()
          message("Plot saved to 'top_loop_correlation_plot.pdf'.")
        } else {
          message("No loop-supported correlations found to plot.")
        }
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_INTAD_LOOP_BASED_CORRELATION":',
        paste0('    InTAD: ', as.character(packageVersion('InTAD')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_loop_based_correlation.csv versions.yml
    """
}

workflow BIOC_INTAD_LOOP_BASED_CORRELATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ enhSel, enhSelGR, rpkmCountsSel, txsSel, mbAnnData, loopsDfSel ] ]

    main:
    BIOC_INTAD_LOOP_BASED_CORRELATION(ch_input)

    emit:
    tables   = BIOC_INTAD_LOOP_BASED_CORRELATION.out.tables
    plots    = BIOC_INTAD_LOOP_BASED_CORRELATION.out.plots
    objects  = BIOC_INTAD_LOOP_BASED_CORRELATION.out.objects
    versions = BIOC_INTAD_LOOP_BASED_CORRELATION.out.versions
}
